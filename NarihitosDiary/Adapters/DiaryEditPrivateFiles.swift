import CryptoKit
import Darwin
import Foundation

// swift-format uses trailing commas for multiline collections.
// swiftlint:disable trailing_comma

struct DiaryEditBinding: Codable, Equatable, Sendable {
  let schema: Int
  let id: UUID
  let transactionID: UUID
  let installationBinding: String
  let resourceKey: String
  let destination: StoredDestinationRecord
  let rootIdentity: String
  let candidate: CatalogCandidate
  let sourceVersion: DiaryPairVersion
  let markdownContentIdentity: String
  let audioContentIdentity: String
  let audioComponents: [String]
  let audioByteCount: Int64
  let submissionDigest: String
  let publicationToken: UUID
}

/// All files live in the existing purge allowlist. Candidate bytes are addressed
/// by digest so a crash between their write and the journal checkpoint cannot
/// destroy the last valid submitted revision.
struct DiaryEditPrivateFiles: Sendable {
  let root: URL
  let protection: any DraftFileProtectionPolicy

  func directory(_ id: UUID) throws -> URL {
    let name = id.uuidString.lowercased()
    _ = try WorkspaceID(name)
    return root.appending(path: name, directoryHint: .isDirectory)
  }

  func prepare(_ binding: DiaryEditBinding) throws -> URL {
    let manager = FileManager.default
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try requireDirectory(root)
    let directory = try directory(binding.transactionID)
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    try requireDirectory(directory)
    try protect(directory)
    try write(try JSONEncoder().encode(binding), named: "binding.json", id: binding.transactionID)
    return directory
  }

  func readBinding(_ id: UUID) throws -> DiaryEditBinding {
    let bytes = try read("binding.json", id: id, maximum: 128 * 1_024)
    let binding = try JSONDecoder().decode(DiaryEditBinding.self, from: bytes)
    guard binding.schema == 1, binding.transactionID == id,
      Self.validDigest(binding.resourceKey), Self.validDigest(binding.submissionDigest),
      binding.audioComponents.isEmpty
        ? !binding.sourceVersion.requiresAudio && binding.audioByteCount == 0
          && binding.audioContentIdentity == CommittedDiaryResource.absentAudio
          && binding.sourceVersion.audioIdentity == CommittedDiaryResource.absentAudio
          && binding.sourceVersion.audioDigest == CommittedDiaryResource.absentAudio
        : binding.sourceVersion.requiresAudio && binding.audioByteCount > 0
          && binding.audioByteCount <= CatalogAudioInspector.maximumBytes
          && binding.audioComponents.count == 5,
      binding.candidate.components.count == 4,
      Self.validDigest(binding.markdownContentIdentity),
      Self.validDigest(binding.audioContentIdentity),
      Self.validDigest(binding.sourceVersion.markdownIdentity),
      Self.validDigest(binding.sourceVersion.audioIdentity),
      Self.validDigest(binding.sourceVersion.markdownDigest),
      Self.validDigest(binding.sourceVersion.audioDigest),
      DestinationID(rawValue: binding.destination.id) != nil,
      binding.resourceKey
        == CommittedDiaryResource.resourceKey(
          destinationID: binding.destination.id, rootIdentity: binding.rootIdentity,
          candidate: binding.candidate),
      !binding.installationBinding.isEmpty, binding.installationBinding.utf8.count <= 256
    else { throw DiaryEditIssue.changed }
    try validateLayout(binding)
    return binding
  }

  private func validateLayout(_ binding: DiaryEditBinding) throws {
    let stem = try CommittedDiaryResource.requiredStem(binding.candidate)
    guard let parsed = DiaryCatalogHandler.currentStem(stem),
      binding.candidate.stableID == parsed.id.description
    else { throw DiaryEditIssue.changed }
    let instant = try SchemaInstant.from(date: parsed.date)
    let layout = DiarySnippetLayout(id: parsed.id, createdAt: instant)
    guard binding.candidate.components == layout.directoryComponents + [stem],
      binding.audioComponents.isEmpty
        || binding.audioComponents == layout.directoryComponents + [
          layout.assetsDirectoryName, layout.audioFilename,
        ]
    else { throw DiaryEditIssue.changed }
  }

  func readRecord(_ id: UUID) throws -> DiaryEditRecord {
    let binding = try readBinding(id)
    let bytes = try read("record.json", id: id, maximum: 64 * 1_024)
    let record = try JSONDecoder().decode(DiaryEditRecord.self, from: bytes)
    try validateRecord(record, binding: binding)
    return record
  }

  private func validateRecord(_ record: DiaryEditRecord, binding: DiaryEditBinding) throws {
    guard record.schema == 1, record.id == binding.transactionID, record.bindingID == binding.id,
      record.installationBinding == binding.installationBinding,
      record.resourceKey == binding.resourceKey, record.sourceVersion == binding.sourceVersion,
      record.destinationID == binding.destination.id, record.assetID == binding.candidate.stableID,
      Self.validDigest(record.candidateDigest),
      record.candidateByteCount > 0, record.candidateByteCount <= 1_114_122
    else { throw DiaryEditIssue.changed }
    if record.stage == .published || record.stage == .completed {
      guard record.publishedVersion != nil else { throw DiaryEditIssue.changed }
    }
    if record.stage == .completed {
      guard record.markdownUploaded, record.audioUploaded else { throw DiaryEditIssue.changed }
    }
    if record.stage == .accepted || record.stage == .ready {
      guard record.publishedVersion == nil, !record.markdownUploaded, !record.audioUploaded else {
        throw DiaryEditIssue.changed
      }
    }
    if let version = record.publishedVersion {
      guard version.requiresAudio == binding.sourceVersion.requiresAudio,
        version.markdownDigest == record.candidateDigest,
        version.audioDigest == binding.sourceVersion.audioDigest,
        Self.validDigest(version.markdownIdentity), Self.validDigest(version.audioIdentity)
      else { throw DiaryEditIssue.changed }
    }
  }

  func recordExists(_ id: UUID) throws -> Bool {
    let directory = try directory(id)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: directory, components: [], directory: true)
    defer { close(descriptor) }
    var info = stat()
    if fstatat(descriptor, "record.json", &info, AT_SYMLINK_NOFOLLOW) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
        throw DiaryEditIssue.changed
      }
      return true
    }
    guard errno == ENOENT else { throw DiaryEditIssue.localData }
    return false
  }

  func removeUnaccepted(_ binding: DiaryEditBinding) throws {
    guard try readBinding(binding.transactionID) == binding,
      try !recordExists(binding.transactionID)
    else { throw DiaryEditIssue.changed }
    let directory = try directory(binding.transactionID)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: directory, components: [], directory: true)
    defer { close(descriptor) }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    for name in names {
      guard
        name == "binding.json" || name == "audio.m4a"
          || (name.hasSuffix(".md") && Self.validDigest(String(name.dropLast(3))))
      else { throw DiaryEditIssue.changed }
      let file = try CatalogSafeFiles.descriptor(
        root: directory, components: [name], directory: false)
      close(file)
    }
    for name in names where name != "binding.json" {
      guard unlinkat(descriptor, name, 0) == 0 else { throw DiaryEditIssue.storage }
    }
    guard unlinkat(descriptor, "binding.json", 0) == 0 else { throw DiaryEditIssue.storage }
    let parent = try CatalogSafeFiles.descriptor(root: root, components: [], directory: true)
    defer { close(parent) }
    guard unlinkat(parent, binding.transactionID.uuidString.lowercased(), AT_REMOVEDIR) == 0 else {
      throw DiaryEditIssue.storage
    }
  }

  func candidate(_ record: DiaryEditRecord) throws -> DiarySnippetV1 {
    let current = try readRecord(record.id)
    guard current == record else { throw DiaryEditIssue.changed }
    let data = try read(record.candidateDigest + ".md", id: record.id, maximum: 1_114_122)
    guard data.count == record.candidateByteCount,
      CommittedDiaryResource.digest(data) == record.candidateDigest,
      case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(data),
      snippet.id.description == record.assetID,
      (snippet.creationMethod == .manual) == (try readBinding(record.id).audioComponents.isEmpty)
    else { throw DiaryEditIssue.invalidCandidate }
    return snippet
  }

  func writeCandidate(_ candidate: DiarySnippetV1, id: UUID) throws -> (
    digest: String, bytes: Int64
  ) {
    let data: Data
    do { data = try DiarySnippetMarkdownCodec().encode(candidate) } catch {
      throw DiaryEditIssue.invalidCandidate
    }
    let digest = CommittedDiaryResource.digest(data)
    try write(data, named: digest + ".md", id: id)
    return (digest, Int64(data.count))
  }

  func checkpoint(_ record: DiaryEditRecord) throws {
    let binding = try readBinding(record.id)
    try validateRecord(record, binding: binding)
    try write(try JSONEncoder().encode(record), named: "record.json", id: record.id)
    guard try readRecord(record.id) == record else { throw DiaryEditIssue.storage }
  }

  func read(_ name: String, id: UUID, maximum: Int) throws -> Data {
    let directory = try directory(id)
    try requireDirectory(root)
    try requireDirectory(directory)
    let (data, _) = try CatalogSafeFiles.read(root: directory, components: [name], maximum: maximum)
    let url = directory.appending(path: name)
    try protection.verify(url)
    guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else { throw DiaryEditIssue.localData }
    return data
  }

  func write(_ data: Data, named name: String, id: UUID) throws {
    let directory = try directory(id)
    try requireDirectory(root)
    try requireDirectory(directory)
    guard !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
      throw DiaryEditIssue.changed
    }
    let url = directory.appending(path: name)
    // Atomic replacement creates a protected file, then verifies all attributes
    // before the caller can publish a journal checkpoint referencing it.
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    try protect(url)
    let reopened = try read(name, id: id, maximum: max(data.count, 1))
    guard reopened == data else { throw DiaryEditIssue.storage }
  }

}

extension DiaryEditPrivateFiles {
  func copyAudio(
    root sourceRoot: URL, components: [String], expected: DiaryFileVersion,
    to directory: URL, control: CatalogReadControl
  ) throws {
    try requireDirectory(directory)
    let source = try CatalogSafeFiles.descriptor(
      root: sourceRoot, components: components, directory: false)
    defer { close(source) }
    var before = stat()
    guard fstat(source, &before) == 0, before.st_size == expected.byteCount,
      expected.byteCount > 0, expected.byteCount <= CatalogAudioInspector.maximumBytes,
      DiaryFileIdentity.versionIdentity(before) == expected.identity
    else { throw DiaryEditIssue.changed }
    let target = directory.appending(path: "audio.m4a")
    let output = Darwin.open(
      target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { throw DiaryEditIssue.storage }
    defer { close(output) }
    try protect(target)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
    defer { buffer.deallocate() }
    var total: Int64 = 0
    while true {
      try control.check()
      let count = Darwin.read(source, buffer, 65_536)
      guard count >= 0 else { throw DiaryEditIssue.unavailable }
      if count == 0 { break }
      total += Int64(count)
      guard total <= expected.byteCount else { throw DiaryEditIssue.changed }
      var offset = 0
      while offset < count {
        let written = Darwin.write(output, buffer.advanced(by: offset), count - offset)
        guard written > 0 else { throw DiaryEditIssue.storage }
        offset += written
      }
    }
    var after = stat()
    guard fstat(source, &after) == 0, DiaryFileIdentity.sameVersion(before, after),
      total == expected.byteCount, fsync(output) == 0
    else { throw DiaryEditIssue.changed }
    let reopened = try CatalogSafeFiles.descriptor(
      root: sourceRoot, components: components, directory: false)
    defer { close(reopened) }
    var path = stat()
    guard fstat(reopened, &path) == 0, DiaryFileIdentity.sameVersion(after, path) else {
      throw DiaryEditIssue.changed
    }
  }

  func verifyAudio(_ binding: DiaryEditBinding) throws {
    if binding.audioComponents.isEmpty { return }
    let directory = try directory(binding.transactionID)
    let result = try CatalogAudioInspector.inspect(
      root: directory, components: ["audio.m4a"], maximumDuration: 301,
      control: CatalogReadControl())
    guard
      result.version.split(separator: ":").last.map(String.init)
        == binding.sourceVersion.audioDigest
    else { throw DiaryEditIssue.changed }
    try protection.verify(directory.appending(path: "audio.m4a"))
  }

  func protect(_ url: URL) throws {
    try protection.applyAndVerify(to: url)
    var url = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else { throw DiaryEditIssue.localData }
  }

  private func requireDirectory(_ url: URL) throws {
    let descriptor = try CatalogSafeFiles.descriptor(root: url, components: [], directory: true)
    close(descriptor)
  }

  static func validDigest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

// swiftlint:enable trailing_comma
