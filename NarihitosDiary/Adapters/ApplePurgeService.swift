// swiftlint:disable trailing_comma
import Darwin
import Foundation
import UIKit

@MainActor
final class ApplePurgeService: PurgePort {
  static let stagingNames = [
    "Captures", "ProcessingQueue", "ConflictSnapshots", "PrivateWorkspaces",
  ]
  private let support: URL
  private let journalStore: PurgeJournalStore
  private let destination: AppleDestinationService
  private let manager: FileManager
  private let protection: any DraftFileProtectionPolicy
  private let protectedDataAvailable: () -> Bool
  private let tree: PurgeFileTree
  private let settleProjection: @MainActor () async -> Void

  init(
    destination: AppleDestinationService, support: URL? = nil,
    manager: FileManager = .default,
    protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    protectedDataAvailable: @escaping () -> Bool = {
      UIApplication.shared.isProtectedDataAvailable
    },
    tree: PurgeFileTree = PurgeFileTree(),
    settleProjection: @escaping @MainActor () async -> Void = {}
  ) {
    self.destination = destination
    self.manager = manager
    self.support =
      support
      ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "NarihitosDiary", directoryHint: .isDirectory)
    self.protection = protection
    self.protectedDataAvailable = protectedDataAvailable
    self.tree = tree
    self.settleProjection = settleProjection
    journalStore = PurgeJournalStore(root: self.support, manager: manager, protection: protection)
  }

  func pendingTransaction() throws -> PurgeTransaction? {
    try requireAccess()
    guard let record = try journalStore.read(), record.sourceCompleted != true else { return nil }
    return record.transaction
  }

  func projectionGeneration() throws -> String {
    try requireAccess()
    guard let record = try journalStore.read() else { return "initial" }
    guard record.sourceCompleted == true, let generation = record.projectionGeneration else {
      throw PurgeFailure.unavailable
    }
    return generation.uuidString
  }

  func prepare(_ scope: PurgeScope) async throws -> PurgeTransaction {
    try requireAccess()
    let pending = try pendingTransaction()
    guard pending == nil || pending?.scope == scope else { throw PurgeFailure.unavailable }
    if scope == .internalStaging {
      return PurgeTransaction(scope: scope, destinationID: nil)
    }
    guard try await stagingHasNoPendingWork() else { throw PurgeFailure.pendingWork }
    let active = await destination.activeDestination()
    guard active.accessState == .accessible, let id = active.summary?.id else {
      throw PurgeFailure.unavailable
    }
    let identity = try await destination.withActiveCatalog(expectedID: id) { root in
      try PurgeFileTree.identity(root)
    }
    let transaction = PurgeTransaction(
      scope: scope, destinationID: id.rawValue, rootIdentity: identity)
    guard pending == nil || pending == transaction else { throw PurgeFailure.changedDestination }
    return transaction
  }

  func begin(_ transaction: PurgeTransaction) throws {
    try requireAccess()
    try journalStore.begin(transaction)
  }

  func perform(
    _ transaction: PurgeTransaction, progress: @escaping @Sendable (Int) -> Void
  ) async throws {
    try requireAccess()
    guard try pendingTransaction() == transaction else { throw PurgeFailure.unavailable }
    // Enrich a legacy interrupted intent before touching any source. The generation
    // remains durable even when cache removal fails or the process exits after deletion.
    try journalStore.begin(transaction)
    await settleProjection()
    try Task.checkCancellation()
    try requireAccess()
    guard try pendingTransaction() == transaction else { throw PurgeFailure.unavailable }
    switch transaction.scope {
    case .internalStaging:
      let roots = try stagingRoots()
      let tree = tree
      try await Task.detached(priority: .utility) {
        var completed = 0
        for root in roots {
          let offset = completed
          completed += try tree.purge(root) { count in progress(offset + count) }
        }
      }.value
    case .activeFolder:
      guard try await stagingHasNoPendingWork(), let rawID = transaction.destinationID,
        let id = DestinationID(rawValue: rawID)
      else { throw PurgeFailure.pendingWork }
      try await purgeFolder(transaction, id: id, progress: progress)
    }
    try requireAccess()
  }

  private func purgeFolder(
    _ transaction: PurgeTransaction, id: DestinationID,
    progress: @escaping @Sendable (Int) -> Void
  ) async throws {
    var completed = 0
    // Bound continuous external additions; a partial attempt keeps the journal.
    for _ in 0..<100_000 {
      let offset = completed
      let removed: Int? = try await destination.withActiveCatalog(expectedID: id) { root in
        try await self.purgeSubtree(transaction, root: root) { progress(offset + $0) }
      }
      guard let removed else { return }
      completed += removed
      progress(completed)
    }
    throw PurgeFailure.unavailable
  }

  private func purgeSubtree(
    _ transaction: PurgeTransaction, root: URL, progress: @escaping @Sendable (Int) -> Void
  ) async throws -> Int? {
    let entry = try await Task.detached(priority: .utility) {
      try PurgeFileTree.firstEntry(root, expectedIdentity: transaction.rootIdentity)
    }.value
    let child = entry.map { root.appending(path: $0.name) }
    // Coordinate the root update and each subtree deletion together. This sends
    // deletion notifications to descendant presenters without deleting the root.
    var intents = [NSFileAccessIntent.writingIntent(with: root, options: [])]
    if let child { intents.append(.writingIntent(with: child, options: .forDeleting)) }
    let tree = tree
    return try await BoundedFileCoordinator().perform(
      intents: intents, timeout: .seconds(30)
    ) { urls in
      guard urls.first?.standardizedFileURL == root.standardizedFileURL else {
        throw PurgeFailure.unsafeResource
      }
      if let entry, let child {
        guard urls.count == 2, urls[1].standardizedFileURL == child.standardizedFileURL else {
          throw PurgeFailure.unsafeResource
        }
        return try tree.purgeEntry(
          entry, in: root, expectedIdentity: transaction.rootIdentity, progress: progress)
      }
      guard try PurgeFileTree.identity(root) == transaction.rootIdentity,
        try PurgeFileTree.isEmpty(root)
      else { throw PurgeFailure.unsafeResource }
      return nil
    }
  }

  func finish() throws {
    try requireAccess()
    try journalStore.complete()
  }

  private func stagingHasNoPendingWork() async throws -> Bool {
    let roots = try stagingRoots()
    let maximumRecordBytes = FileQueueStore.maximumRecordBytes
    return try await Task.detached(priority: .utility) {
      for root in roots {
        if root.lastPathComponent == "ProcessingQueue" {
          guard try PurgeQueueHistory.isComplete(root, maximumRecordBytes: maximumRecordBytes)
          else {
            return false
          }
        } else if root.lastPathComponent == "PrivateWorkspaces" {
          guard try DiaryStagingNamespaces.isEmpty(root) else { return false }
        } else if try !PurgeFileTree.isEmpty(root) {
          return false
        }
      }
      return true
    }.value
  }

  private func stagingRoots() throws -> [URL] {
    guard try exists(support) else { return [] }
    _ = try PurgeFileTree.identity(support)
    return try Self.stagingNames.compactMap { name in
      let root = support.appending(path: name, directoryHint: .isDirectory)
      guard try exists(root) else { return nil }
      _ = try PurgeFileTree.identity(root)
      return root
    }
  }

  private func exists(_ url: URL) throws -> Bool {
    var value = stat()
    if lstat(url.path, &value) == 0 { return true }
    if errno == ENOENT { return false }
    throw PurgeFailure.unavailable
  }

  private func requireAccess() throws {
    guard protectedDataAvailable() else { throw PurgeFailure.unavailable }
    if try exists(support) { _ = try PurgeFileTree.identity(support) }
  }
}

// swiftlint:enable trailing_comma
