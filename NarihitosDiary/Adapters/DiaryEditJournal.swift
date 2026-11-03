import Darwin
import Foundation

// swift-format places braces after multiline result types.
// swiftlint:disable opening_brace

actor DiaryEditJournal {
  let files: DiaryEditPrivateFiles
  private var traversal: CatalogDirectoryCursor?
  private var cursor: String?
  private var claims: [String: Set<UUID>] = [:]
  private var discovered = false
  private var unaccepted: [DiaryEditBinding] = []
  private var retirements: Set<UUID> = []
  private var retirementClaims: [UUID: String] = [:]

  init(files: DiaryEditPrivateFiles) { self.files = files }

  func inventory(after requested: String?, installation: String) throws -> DiaryEditInventory {
    if requested == nil {
      try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
      try files.protect(files.root)
      traversal = try CatalogDirectoryCursor(root: files.root, components: [])
      cursor = nil
      claims.removeAll()
      unaccepted.removeAll()
      retirements.removeAll()
      retirementClaims.removeAll()
      discovered = false
    }
    guard requested == cursor, let traversal else { throw DiaryEditIssue.changed }
    let slice = try traversal.next(root: files.root, components: [], maximum: 50)
    var records: [DiaryEditRecord] = []
    var isolated = 0
    for entry in slice.entries {
      do {
        if let record = try readEntry(entry, installation: installation) { records.append(record) }
      } catch {
        isolated += 1
      }
    }
    if slice.ended {
      isolated += finishDiscovery(installation: installation)
    } else {
      cursor = UUID().uuidString
    }
    return DiaryEditInventory(records: records, continuation: cursor, isolatedCount: isolated)
  }

  private func finishDiscovery(installation: String) -> Int {
    traversal = nil
    cursor = nil
    discovered = true
    var isolated = 0
    for binding in unaccepted {
      do {
        try files.removeUnaccepted(binding)
        claims[binding.resourceKey]?.remove(binding.transactionID)
      } catch { isolated += 1 }
    }
    unaccepted.removeAll()
    for id in retirements {
      do {
        try files.completeRetirement(id, installation: installation)
        if let key = retirementClaims[id] { claims[key]?.remove(id) }
      } catch { isolated += 1 }
    }
    retirements.removeAll()
    retirementClaims.removeAll()
    return isolated
  }

  private func readEntry(_ entry: CatalogDirectorySlice.Entry, installation: String) throws
    -> DiaryEditRecord?
  {
    if entry.safe, let id = files.retirementID(entry.name) {
      retirements.insert(id)
      return nil
    }
    guard entry.safe, entry.isDirectory, let id = UUID(uuidString: entry.name),
      id.uuidString.lowercased() == entry.name
    else { throw DiaryEditIssue.changed }
    let binding = try files.readBinding(id)
    claims[binding.resourceKey, default: []].insert(id)
    if try !files.recordExists(id) {
      guard binding.installationBinding == installation else { throw DiaryEditIssue.reviewRequired }
      unaccepted.append(binding)
      return nil
    }
    var record = try files.readRecord(id)
    if record.installationBinding != installation {
      record.stage = .quarantined
      record.issue = .reviewRequired
      try files.checkpoint(record)
    }
    if record.stage == .completed, try files.cleanupReceiptExists(id) {
      retirements.insert(id)
      retirementClaims[id] = binding.resourceKey
      return nil
    }
    return record
  }

  func assertAvailable(resourceKey: String, transactionID: UUID? = nil) throws {
    guard discovered else { throw DiaryEditIssue.busy }
    let existing = claims[resourceKey] ?? []
    guard existing.count <= 1 else { throw DiaryEditIssue.conflict }
    guard existing.isEmpty || (existing.count == 1 && existing.first == transactionID) else {
      throw DiaryEditIssue.busy
    }
  }

  func existing(_ submission: DiaryEditSubmission, session: DiaryEditSession) throws
    -> DiaryEditRecord?
  {
    guard try contains(submission.id) else { return nil }
    let binding = try files.readBinding(submission.id)
    guard binding.submissionDigest == CommittedDiaryResource.submissionDigest(submission.change),
      binding.resourceKey == session.resourceKey, binding.sourceVersion == session.sourceVersion
    else { throw DiaryEditIssue.submissionMismatch }
    return try files.readRecord(submission.id)
  }

  func prepare(_ binding: DiaryEditBinding) throws -> URL {
    try assertAvailable(resourceKey: binding.resourceKey)
    let directory = try files.prepare(binding)
    claims[binding.resourceKey, default: []].insert(binding.transactionID)
    return directory
  }

  func accept(_ binding: DiaryEditBinding, candidate: DiarySnippetV1, regeneratesTitle: Bool) throws
    -> DiaryEditRecord
  {
    guard try files.readBinding(binding.transactionID) == binding else {
      throw DiaryEditIssue.changed
    }
    try files.verifyAudio(binding)
    let encoded = try files.writeCandidate(candidate, id: binding.transactionID)
    let record = DiaryEditRecord(
      schema: 1, id: binding.transactionID, installationBinding: binding.installationBinding,
      resourceKey: binding.resourceKey, bindingID: binding.id, sourceVersion: binding.sourceVersion,
      regeneratesTitle: regeneratesTitle, destinationID: binding.destination.id,
      assetID: candidate.id.description, stage: .accepted,
      candidateDigest: encoded.digest, candidateByteCount: encoded.bytes,
      publishedVersion: nil, markdownUploaded: false, audioUploaded: false, issue: nil)
    try files.checkpoint(record)
    _ = try files.candidate(record)
    return record
  }

  func abandonUnaccepted(_ binding: DiaryEditBinding) throws {
    guard try !files.recordExists(binding.transactionID) else { return }
    try files.removeUnaccepted(binding)
    claims[binding.resourceKey]?.remove(binding.transactionID)
  }

  func candidate(_ record: DiaryEditRecord) throws -> DiarySnippetV1 {
    let binding = try files.readBinding(record.id)
    do { try files.verifyAudio(binding) } catch CatalogIssue.invalidAudio {
      throw DiaryEditIssue.invalidCandidate
    }
    return try files.candidate(record)
  }

  func record(_ id: UUID) throws -> DiaryEditRecord { try files.readRecord(id) }

  func binding(_ record: DiaryEditRecord) throws -> DiaryEditBinding {
    guard try files.readRecord(record.id) == record else { throw DiaryEditIssue.changed }
    return try files.readBinding(record.id)
  }

  func finalize(_ record: DiaryEditRecord, candidate: DiarySnippetV1) throws -> DiaryEditRecord {
    let previous = try files.candidate(record)
    var comparison = candidate
    comparison.title = previous.title
    comparison.titleProvenance = previous.titleProvenance
    guard record.stage == .accepted, comparison == previous,
      record.regeneratesTitle || candidate == previous
    else { throw DiaryEditIssue.changed }
    let encoded = try files.writeCandidate(candidate, id: record.id)
    var finalized = record
    finalized.candidateDigest = encoded.digest
    finalized.candidateByteCount = encoded.bytes
    finalized.stage = .ready
    finalized.issue = nil
    try files.checkpoint(finalized)
    return finalized
  }

  func checkpoint(_ record: DiaryEditRecord) throws {
    let current = try files.readRecord(record.id)
    guard current.candidateDigest == record.candidateDigest,
      current.candidateByteCount == record.candidateByteCount,
      current.regeneratesTitle == record.regeneratesTitle,
      current.stage.permitsCheckpoint(record.stage)
    else { throw DiaryEditIssue.changed }
    try files.checkpoint(record)
  }

  func cleanup(_ record: DiaryEditRecord) throws {
    try files.remove(record)
    claims[record.resourceKey]?.remove(record.id)
  }

  private func contains(_ id: UUID) throws -> Bool {
    let descriptor = try CatalogSafeFiles.descriptor(
      root: files.root, components: [], directory: true)
    defer { close(descriptor) }
    var info = stat()
    if fstatat(descriptor, id.uuidString.lowercased(), &info, AT_SYMLINK_NOFOLLOW) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFDIR else { throw DiaryEditIssue.changed }
      return true
    }
    guard errno == ENOENT else { throw DiaryEditIssue.localData }
    return false
  }
}

// swiftlint:enable opening_brace
