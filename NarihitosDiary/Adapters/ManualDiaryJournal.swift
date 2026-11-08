// swift-format wraps multiline declarations and collections.
// swiftlint:disable opening_brace
import Darwin
import Foundation

struct ManualDiaryEnvelope: Codable, Sendable {
  let schema: Int
  let id: UUID
  let installation: String
  let destination: StoredDestinationRecord
  let rootIdentity: String
  let token: UUID
  let submissionDigest: String
  var markdown: Data
  var needsTitle: Bool
  var completed: Bool

  var record: ManualDiaryRecord {
    ManualDiaryRecord(
      id: id, destinationID: destination.id, folderName: destination.displayName,
      needsTitle: needsTitle, issue: nil)
  }
}

struct ManualDiaryCompletion: Codable, Sendable {
  let schema: Int
  let id: UUID
  let installation: String
  let submissionDigest: String
  let destinationID: String
  let folderName: String

  var record: ManualDiaryRecord {
    ManualDiaryRecord(
      id: id, destinationID: destinationID, folderName: folderName,
      needsTitle: false, issue: nil, completed: true)
  }
}

/// A single protected envelope is the acceptance checkpoint. Its body and original
/// destination survive termination without masquerading as a recording queue job.
actor ManualDiaryJournal {
  let files: DiaryEditPrivateFiles

  init(files: DiaryEditPrivateFiles) { self.files = files }

  func accept(
    _ submission: ManualDiarySubmission, destination: StoredDestinationRecord,
    rootIdentity: String, installation: String
  ) throws -> ManualDiaryRecord {
    try prepareRoot()
    let id = submission.id
    if let completion = try completion(id, installation: installation) {
      guard completion.submissionDigest == Self.digest(submission) else {
        throw DiaryEditIssue.submissionMismatch
      }
      return completion.record
    }
    let directory = try files.directory(id)
    if try exists(id) {
      let current = try envelope(id, installation: installation)
      guard current.submissionDigest == Self.digest(submission) else {
        throw DiaryEditIssue.submissionMismatch
      }
      return current.record
    }
    let root = try CatalogSafeFiles.descriptor(root: files.root, components: [], directory: true)
    defer { close(root) }
    guard mkdirat(root, id.uuidString.lowercased(), 0o700) == 0 || errno == EEXIST else {
      throw DiaryEditIssue.storage
    }
    try files.protect(directory)
    guard try PurgeFileTree.isEmpty(directory) else { throw DiaryEditIssue.localData }
    let body = try DiaryBody(submission.body)
    let title = DiaryTitlePolicy.fallback(body.text)
    let snippet = DiarySnippetV1.manual(
      id: try AssetID(id.uuidString.lowercased()),
      createdAt: try SchemaInstant.from(date: submission.createdAt),
      body: body, title: title.text, provenance: title.provenance)
    let envelope = ManualDiaryEnvelope(
      schema: 1, id: id, installation: installation,
      destination: destination, rootIdentity: rootIdentity, token: UUID(),
      submissionDigest: Self.digest(submission),
      markdown: try DiarySnippetMarkdownCodec().encode(snippet), needsTitle: true, completed: false)
    try write(envelope)
    return try self.envelope(id, installation: installation).record
  }

  func inventory(installation: String) throws -> [ManualDiaryRecord] {
    try prepareRoot()
    let cursor = try CatalogDirectoryCursor(root: files.root, components: [])
    var records: [ManualDiaryRecord] = []
    var hasIsolated = false
    repeat {
      let slice = try cursor.next(root: files.root, components: [], maximum: 50)
      for entry in slice.entries {
        do {
          if entry.safe, !entry.isDirectory, let id = Self.completionID(entry.name) {
            _ = try completion(id, installation: installation)
            continue
          }
          guard entry.safe, entry.isDirectory, let id = UUID(uuidString: entry.name),
            id.uuidString.lowercased() == entry.name
          else { throw DiaryEditIssue.localData }
          if try !exists(id) {
            // A crash before acceptance, or after the last completed cleanup unlink.
            guard try PurgeFileTree.isEmpty(files.directory(id)) else {
              throw DiaryEditIssue.localData
            }
            try removeEmpty(id)
          } else {
            let envelope = try envelope(id, installation: installation)
            if envelope.completed { try cleanup(envelope) } else { records.append(envelope.record) }
          }
        } catch { hasIsolated = true }
      }
      if slice.ended { break }
    } while true
    // Fail closed for unknown/restored entries rather than silently ignoring submitted work.
    guard !hasIsolated else { throw DiaryEditIssue.reviewRequired }
    return records
  }

  func envelope(_ id: UUID, installation: String) throws -> ManualDiaryEnvelope {
    let data = try files.read("request.json", id: id, maximum: 2_300_000)
    let value = try JSONDecoder().decode(ManualDiaryEnvelope.self, from: data)
    guard value.schema == 1, value.id == id, value.installation == installation,
      DestinationID(rawValue: value.destination.id) != nil,
      DiaryEditPrivateFiles.validDigest(value.submissionDigest),
      case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(value.markdown),
      snippet.creationMethod == .manual, snippet.id.description == id.uuidString.lowercased()
    else { throw DiaryEditIssue.reviewRequired }
    return value
  }

  func finalize(_ id: UUID, installation: String, title: GeneratedDiaryTitle) throws
    -> ManualDiaryRecord
  {
    var value = try envelope(id, installation: installation)
    guard value.needsTitle, !value.completed,
      case .supported(var snippet) = DiarySnippetMarkdownCodec().decode(value.markdown)
    else { return value.record }
    snippet.title = title.text
    snippet.titleProvenance = title.provenance
    value.markdown = try DiarySnippetMarkdownCodec().encode(snippet)
    value.needsTitle = false
    try write(value)
    return value.record
  }

  func complete(_ id: UUID, installation: String) throws {
    var value = try envelope(id, installation: installation)
    value.completed = true
    try write(value)
    try cleanup(value)
  }

  func retireCompleted(_ id: UUID, installation: String) throws -> Bool {
    guard try completion(id, installation: installation) != nil else { return false }
    let parent = try CatalogSafeFiles.descriptor(root: files.root, components: [], directory: true)
    defer { close(parent) }
    var info = stat()
    if fstatat(parent, id.uuidString.lowercased(), &info, AT_SYMLINK_NOFOLLOW) != 0 {
      guard errno == ENOENT else { throw DiaryEditIssue.localData }
      return true
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR else { throw DiaryEditIssue.localData }
    if try exists(id) {
      try cleanup(envelope(id, installation: installation))
    } else {
      guard try PurgeFileTree.isEmpty(files.directory(id)) else { throw DiaryEditIssue.localData }
      try removeEmpty(id)
    }
    return true
  }

  func completion(_ id: UUID, installation: String) throws -> ManualDiaryCompletion? {
    guard FileManager.default.fileExists(atPath: files.root.path) else { return nil }
    guard
      try CatalogSafeFiles.resourceExists(root: files.root, components: [Self.completionName(id)])
    else { return nil }
    let url = files.root.appending(path: Self.completionName(id))
    try files.protection.verify(url)
    guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else {
      throw DiaryEditIssue.localData
    }
    let (data, _) = try CatalogSafeFiles.read(
      root: files.root, components: [Self.completionName(id)], maximum: 16_384)
    let value = try JSONDecoder().decode(ManualDiaryCompletion.self, from: data)
    guard value.schema == 1, value.id == id, value.installation == installation,
      DiaryEditPrivateFiles.validDigest(value.submissionDigest),
      DestinationID(rawValue: value.destinationID) != nil
    else { throw DiaryEditIssue.reviewRequired }
    return value
  }

  nonisolated static func completionName(_ id: UUID) -> String {
    "completed-" + id.uuidString.lowercased() + ".json"
  }

  nonisolated static func completionID(_ name: String) -> UUID? {
    guard name.hasPrefix("completed-"), name.hasSuffix(".json") else { return nil }
    let raw = String(name.dropFirst(10).dropLast(5))
    guard let id = UUID(uuidString: raw), id.uuidString.lowercased() == raw else { return nil }
    return id
  }

  nonisolated static func hasPending(in root: URL) throws -> Bool {
    let cursor = try CatalogDirectoryCursor(root: root, components: [])
    repeat {
      let slice = try cursor.next(root: root, components: [], maximum: 50)
      for entry in slice.entries {
        guard entry.safe, !entry.isDirectory, let id = completionID(entry.name) else { return true }
        let (data, _) = try CatalogSafeFiles.read(
          root: root, components: [entry.name], maximum: 16_384)
        let value = try JSONDecoder().decode(ManualDiaryCompletion.self, from: data)
        guard value.schema == 1, value.id == id,
          DiaryEditPrivateFiles.validDigest(value.submissionDigest)
        else { return true }
      }
      if slice.ended { return false }
    } while true
  }

  private func write(_ envelope: ManualDiaryEnvelope) throws {
    try files.write(try JSONEncoder().encode(envelope), named: "request.json", id: envelope.id)
  }

  private func cleanup(_ value: ManualDiaryEnvelope) throws {
    guard value.completed else { throw DiaryEditIssue.changed }
    let receipt = ManualDiaryCompletion(
      schema: 1, id: value.id, installation: value.installation,
      submissionDigest: value.submissionDigest, destinationID: value.destination.id,
      folderName: value.destination.displayName)
    let url = files.root.appending(path: Self.completionName(value.id))
    try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
    try files.protect(url)
    let directory = try files.directory(value.id)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: directory, components: [], directory: true)
    defer { close(descriptor) }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    guard Set(names).isSubset(of: ["request.json", "publication.json"]) else {
      throw DiaryEditIssue.localData
    }
    for name in names {
      let file = try CatalogSafeFiles.descriptor(
        root: directory, components: [name], directory: false)
      close(file)
    }
    // The completion envelope is removed last. Any interrupted cleanup is replayable.
    if names.contains("publication.json") {
      guard unlinkat(descriptor, "publication.json", 0) == 0 else { throw DiaryEditIssue.storage }
    }
    guard unlinkat(descriptor, "request.json", 0) == 0 else { throw DiaryEditIssue.storage }
    try removeEmpty(value.id)
  }

  private func removeEmpty(_ id: UUID) throws {
    let parent = try CatalogSafeFiles.descriptor(root: files.root, components: [], directory: true)
    defer { close(parent) }
    guard unlinkat(parent, id.uuidString.lowercased(), AT_REMOVEDIR) == 0 else {
      throw DiaryEditIssue.storage
    }
  }

  private func exists(_ id: UUID) throws -> Bool {
    let directory = try files.directory(id)
    let root = try CatalogSafeFiles.descriptor(root: files.root, components: [], directory: true)
    defer { close(root) }
    var info = stat()
    if fstatat(root, id.uuidString.lowercased(), &info, AT_SYMLINK_NOFOLLOW) != 0 {
      guard errno == ENOENT else { throw DiaryEditIssue.localData }
      return false
    }
    return try CatalogSafeFiles.resourceExists(root: directory, components: ["request.json"])
  }

  private func prepareRoot() throws {
    try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: files.root, components: [], directory: true)
    close(descriptor)
    try files.protect(files.root)
  }

  static func digest(_ submission: ManualDiarySubmission) -> String {
    CommittedDiaryResource.digest(
      Data((submission.createdAt.timeIntervalSince1970.description + "\0" + submission.body).utf8))
  }
}

// swiftlint:enable opening_brace
