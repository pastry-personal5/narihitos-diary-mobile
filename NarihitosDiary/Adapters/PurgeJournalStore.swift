import Darwin
import Foundation

/// The existing purge intent also owns the durable fence for disposable projections.
struct PurgeJournalRecord: Codable, Equatable {
  let scope: PurgeScope
  let destinationID: String?
  let rootIdentity: String?
  let projectionGeneration: UUID?
  var sourceCompleted: Bool?

  init(transaction: PurgeTransaction, generation: UUID) {
    scope = transaction.scope
    destinationID = transaction.destinationID
    rootIdentity = transaction.rootIdentity
    projectionGeneration = generation
    sourceCompleted = false
  }

  var transaction: PurgeTransaction {
    PurgeTransaction(scope: scope, destinationID: destinationID, rootIdentity: rootIdentity)
  }

  func validate() throws {
    switch scope {
    case .internalStaging:
      guard destinationID == nil, rootIdentity == nil else { throw PurgeFailure.unsafeResource }
    case .activeFolder:
      guard let id = destinationID, DestinationID(rawValue: id) != nil,
        let rootIdentity, !rootIdentity.isEmpty
      else { throw PurgeFailure.unsafeResource }
    }
    // Legacy records have neither field and remain interrupted source transactions.
    guard (projectionGeneration == nil) == (sourceCompleted == nil) else {
      throw PurgeFailure.unsafeResource
    }
  }
}
struct PurgeJournalStore {
  let root: URL
  let manager: FileManager
  let protection: any DraftFileProtectionPolicy
  private var journal: URL { root.appending(path: "purge-transaction.json") }

  func read() throws -> PurgeJournalRecord? {
    var facts = stat()
    guard lstat(journal.path, &facts) == 0 else {
      if errno == ENOENT { return nil }
      throw PurgeFailure.unavailable
    }
    guard facts.st_mode & S_IFMT == S_IFREG, facts.st_nlink == 1,
      facts.st_size > 0, facts.st_size < 4_096
    else { throw PurgeFailure.unsafeResource }
    try protection.verify(journal)
    let record = try JSONDecoder().decode(PurgeJournalRecord.self, from: Data(contentsOf: journal))
    try record.validate()
    return record
  }

  func begin(_ transaction: PurgeTransaction) throws {
    let previous = try read()
    if let previous, previous.sourceCompleted != true {
      guard previous.transaction == transaction else { throw PurgeFailure.changedDestination }
    }
    let generation = previous?.sourceCompleted == false ? previous?.projectionGeneration : nil
    try write(PurgeJournalRecord(transaction: transaction, generation: generation ?? UUID()))
  }

  func complete() throws {
    guard var record = try read(), record.sourceCompleted == false,
      record.projectionGeneration != nil
    else { throw PurgeFailure.unavailable }
    record.sourceCompleted = true
    try write(record)
  }

  private func write(_ record: PurgeJournalRecord) throws {
    try record.validate()
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try PurgeFileTree.identity(root)
    // Atomic, protected intent publication precedes every destructive source mutation.
    try JSONEncoder().encode(record).write(
      to: journal, options: [.atomic, .completeFileProtection])
    try protection.applyAndVerify(to: journal)
    var url = journal
    var attributes = URLResourceValues()
    attributes.isExcludedFromBackup = true
    try url.setResourceValues(attributes)
    guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true,
      try read() == record
    else { throw PurgeFailure.unavailable }
  }
}
