import Darwin
import Foundation

private struct EditSnapshotBinding: Codable {
  let schema: Int
  let editBindingID: UUID
  let value: DiaryEditRecoverySnapshot
  let markdownBytes: Int64
  let audioBytes: Int64
}

struct DiaryEditConflictSnapshots: Sendable {
  let files: DiaryEditPrivateFiles

  private func snapshotFiles(_ record: DiaryEditRecord) throws -> DiaryEditPrivateFiles {
    DiaryEditPrivateFiles(
      root: try files.directory(record.id).appending(path: "ExternalSnapshots"),
      protection: files.protection)
  }

  /// Called inside coordinated access to this exact external pair. A shared
  /// audio reference is permitted only after matching the unchanged resource
  /// and validating the protected submitted-audio snapshot independently.
  func capture(
    _ record: DiaryEditRecord, binding: DiaryEditBinding, root: URL, control: CatalogReadControl
  ) throws -> DiaryEditRecoverySnapshot {
    guard try files.readRecord(record.id) == record,
      try CommittedDiaryResource.rootIdentity(root) == binding.rootIdentity
    else { throw DiaryEditIssue.changed }
    let stem = try CommittedDiaryResource.requiredStem(binding.candidate)
    let markdownPath = Array(binding.candidate.components.dropLast()) + [stem + ".md"]
    let (markdown, textVersion) = try CatalogSafeFiles.read(
      root: root, components: markdownPath, maximum: 1_114_122)
    guard case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(markdown),
      snippet.id.description == record.assetID,
      DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt).markdownFilename == stem
        + ".md",
      snippet.audioFilename == binding.audioComponents.last
    else { throw DiaryEditIssue.unsupported }
    if binding.audioComponents.isEmpty {
      guard snippet.creationMethod == .manual, !binding.sourceVersion.requiresAudio else {
        throw DiaryEditIssue.unsupported
      }
      return try retainManual(
        record, binding: binding, root: root, markdown: markdown,
        version: textVersion)
    }
    let audio = try CatalogAudioInspector.inspect(
      root: root, components: binding.audioComponents, maximumDuration: 301, control: control)
    let version = try pairVersion(markdown: textVersion, audio: audio.version)
    guard snippet.audioSHA256 == nil || snippet.audioSHA256 == version.audioDigest else {
      throw DiaryEditIssue.unsupported
    }
    let shared = try sharesAudio(binding, version: version, root: root)
    if shared { try files.verifyAudio(binding) }
    let markdownURL = markdownPath.reduce(root) { $0.appendingPathComponent($1) }
    let audioURL = binding.audioComponents.reduce(root) { $0.appendingPathComponent($1) }
    let value = DiaryEditRecoverySnapshot(
      id: UUID(), transactionID: record.id, assetID: record.assetID, version: version,
      modifiedAt: DiaryPairModificationTimes(
        markdown: NSFileVersion.currentVersionOfItem(at: markdownURL)?.modificationDate,
        audio: NSFileVersion.currentVersionOfItem(at: audioURL)?.modificationDate),
      sharesSubmittedAudio: shared,
      hasAdditionalProviderVersions: DiaryCatalogHandler.hasConflict(markdownURL)
        || DiaryCatalogHandler.hasConflict(audioURL))
    return try retain(value, binding: binding, markdown: markdown, root: root, control: control)
  }

  private func retainManual(
    _ record: DiaryEditRecord, binding: DiaryEditBinding, root: URL, markdown: Data,
    version: String
  ) throws -> DiaryEditRecoverySnapshot {
    let stem = try CommittedDiaryResource.requiredStem(binding.candidate)
    let path = Array(binding.candidate.components.dropLast()) + [stem + ".md"]
    let parts = version.split(separator: ":").map(String.init)
    guard parts.count == 2 else { throw DiaryEditIssue.changed }
    let url = path.reduce(root) { $0.appendingPathComponent($1) }
    let value = DiaryEditRecoverySnapshot(
      id: UUID(), transactionID: record.id, assetID: record.assetID,
      version: DiaryPairVersion(
        markdownIdentity: parts[0], audioIdentity: CommittedDiaryResource.absentAudio,
        markdownDigest: parts[1], audioDigest: CommittedDiaryResource.absentAudio,
        audioRequired: false),
      modifiedAt: DiaryPairModificationTimes(
        markdown: NSFileVersion.currentVersionOfItem(at: url)?.modificationDate, audio: nil),
      sharesSubmittedAudio: false,
      hasAdditionalProviderVersions: DiaryCatalogHandler.hasConflict(url))
    let snapshots = try snapshotFiles(record)
    try FileManager.default.createDirectory(at: snapshots.root, withIntermediateDirectories: true)
    try snapshots.protect(snapshots.root)
    let directory = try snapshots.directory(value.id)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try snapshots.protect(directory)
    try snapshots.write(markdown, named: "external.md", id: value.id)
    let (_, reopened) = try CatalogSafeFiles.read(root: root, components: path, maximum: 1_114_122)
    guard reopened == version else { throw DiaryEditIssue.changed }
    let metadata = EditSnapshotBinding(
      schema: 1, editBindingID: binding.id, value: value,
      markdownBytes: Int64(markdown.count), audioBytes: 0)
    try snapshots.write(try JSONEncoder().encode(metadata), named: "snapshot.json", id: value.id)
    _ = try preview(record, snapshotID: value.id)
    return value
  }

  private func retain(
    _ value: DiaryEditRecoverySnapshot, binding: DiaryEditBinding,
    markdown: Data, root: URL, control: CatalogReadControl
  ) throws -> DiaryEditRecoverySnapshot {
    let record = try files.readRecord(value.transactionID)
    let snapshots = try snapshotFiles(record)
    try FileManager.default.createDirectory(at: snapshots.root, withIntermediateDirectories: true)
    try snapshots.protect(snapshots.root)
    let directory = try snapshots.directory(value.id)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try snapshots.protect(directory)
    var info = stat()
    let source = try CatalogSafeFiles.descriptor(
      root: root, components: binding.audioComponents, directory: false)
    defer { close(source) }
    guard fstat(source, &info) == 0,
      DiaryFileIdentity.versionIdentity(info) == value.version.audioIdentity
    else {
      throw DiaryEditIssue.changed
    }
    if !value.sharesSubmittedAudio {
      try snapshots.copyAudio(
        root: root, components: binding.audioComponents,
        expected: DiaryFileVersion(
          identity: value.version.audioIdentity, digest: value.version.audioDigest,
          byteCount: info.st_size),
        to: directory, control: control)
    }
    try snapshots.write(markdown, named: "external.md", id: value.id)
    try verifyExternalUnchanged(value, binding: binding, root: root, control: control)
    let metadata = EditSnapshotBinding(
      schema: 1, editBindingID: binding.id, value: value,
      markdownBytes: Int64(markdown.count), audioBytes: info.st_size)
    try snapshots.write(try JSONEncoder().encode(metadata), named: "snapshot.json", id: value.id)
    _ = try preview(record, snapshotID: value.id)
    return value
  }

  private func verifyExternalUnchanged(
    _ value: DiaryEditRecoverySnapshot, binding: DiaryEditBinding, root: URL,
    control: CatalogReadControl
  ) throws {
    let stem = try CommittedDiaryResource.requiredStem(binding.candidate)
    let markdown = Array(binding.candidate.components.dropLast()) + [stem + ".md"]
    let (_, textVersion) = try CatalogSafeFiles.read(
      root: root, components: markdown, maximum: 1_114_122)
    let audio = try CatalogAudioInspector.inspect(
      root: root, components: binding.audioComponents, maximumDuration: 301, control: control)
    guard try pairVersion(markdown: textVersion, audio: audio.version) == value.version else {
      throw DiaryEditIssue.changed
    }
  }

  func list(_ record: DiaryEditRecord) throws -> [DiaryEditRecoverySnapshot] {
    let snapshots = try snapshotFiles(record)
    var info = stat()
    guard lstat(snapshots.root.path, &info) == 0 else {
      if errno == ENOENT { return [] }
      throw DiaryEditIssue.localData
    }
    let cursor = try CatalogDirectoryCursor(root: snapshots.root, components: [])
    var values: [DiaryEditRecoverySnapshot] = []
    repeat {
      let slice = try cursor.next(root: snapshots.root, components: [], maximum: 50)
      for entry in slice.entries where entry.safe && entry.isDirectory {
        guard let id = UUID(uuidString: entry.name), id.uuidString.lowercased() == entry.name,
          let metadata = try? metadata(record, snapshotID: id)
        else { continue }
        values.append(metadata.value)
      }
      if slice.ended { break }
    } while true
    return values
  }

  func preview(_ record: DiaryEditRecord, snapshotID: UUID) throws -> DiarySnippetV1 {
    let metadata = try metadata(record, snapshotID: snapshotID)
    let snapshots = try snapshotFiles(record)
    let markdown = try snapshots.read("external.md", id: snapshotID, maximum: 1_114_122)
    guard markdown.count == metadata.markdownBytes,
      CommittedDiaryResource.digest(markdown) == metadata.value.version.markdownDigest,
      case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(markdown),
      snippet.id.description == record.assetID
    else { throw DiaryEditIssue.invalidCandidate }
    if !metadata.value.version.requiresAudio {
      guard snippet.creationMethod == .manual, metadata.audioBytes == 0 else {
        throw DiaryEditIssue.invalidCandidate
      }
      return snippet
    }
    guard snippet.creationMethod == .recording else { throw DiaryEditIssue.invalidCandidate }
    let audioRoot =
      metadata.value.sharesSubmittedAudio
      ? try files.directory(record.id) : try snapshots.directory(snapshotID)
    let audio = try CatalogAudioInspector.inspect(
      root: audioRoot, components: ["audio.m4a"], maximumDuration: 301,
      control: CatalogReadControl())
    guard
      audio.version.split(separator: ":").last.map(String.init)
        == metadata.value.version.audioDigest
    else {
      throw DiaryEditIssue.invalidCandidate
    }
    try files.protection.verify(audioRoot.appending(path: "audio.m4a"))
    return snippet
  }

  private func metadata(_ record: DiaryEditRecord, snapshotID: UUID) throws -> EditSnapshotBinding {
    let snapshots = try snapshotFiles(record)
    let data = try snapshots.read("snapshot.json", id: snapshotID, maximum: 64 * 1_024)
    let metadata = try JSONDecoder().decode(EditSnapshotBinding.self, from: data)
    guard metadata.schema == 1, metadata.editBindingID == record.bindingID,
      metadata.value.id == snapshotID, metadata.value.transactionID == record.id,
      metadata.value.assetID == record.assetID, metadata.markdownBytes > 0,
      metadata.markdownBytes <= 1_114_122,
      metadata.value.version.requiresAudio
        ? metadata.audioBytes > 0 && metadata.audioBytes <= CatalogAudioInspector.maximumBytes
        : metadata.audioBytes == 0
    else { throw DiaryEditIssue.changed }
    return metadata
  }

  private func pairVersion(markdown: String, audio: String) throws -> DiaryPairVersion {
    let text = markdown.split(separator: ":").map(String.init)
    let sound = audio.split(separator: ":").map(String.init)
    guard text.count == 2, sound.count == 2 else { throw DiaryEditIssue.changed }
    return DiaryPairVersion(
      markdownIdentity: text[0], audioIdentity: sound[0], markdownDigest: text[1],
      audioDigest: sound[1])
  }

  // swiftlint:disable opening_brace
  private func sharesAudio(_ binding: DiaryEditBinding, version: DiaryPairVersion, root: URL) throws
    -> Bool
  {
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: binding.audioComponents, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw DiaryEditIssue.unavailable }
    return version.audioDigest == binding.sourceVersion.audioDigest
      && DiaryFileIdentity.contentVersionIdentity(info) == binding.audioContentIdentity
  }
  // swiftlint:enable opening_brace
}
