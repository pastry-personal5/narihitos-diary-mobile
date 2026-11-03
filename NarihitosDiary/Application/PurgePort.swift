import Foundation

enum PurgeScope: String, Codable, CaseIterable, Sendable {
  case activeFolder
  case internalStaging

  var title: String {
    switch self {
    case .activeFolder: "Purge Active Folder Contents"
    case .internalStaging: "Purge Internal Staging"
    }
  }

  var warning: String {
    switch self {
    case .activeFolder:
      "Permanently remove every file and folder inside the active iCloud folder, including files "
        + "not created by this app. The folder itself is kept. This cannot be undone. "
        + "Pending work must finish or be purged separately first."
    case .internalStaging:
      "Permanently remove pending and failed recordings, their audio, unsaved diary drafts, "
        + "and other private staging files. Saved iCloud diaries, Settings, and installed models "
        + "are kept. This cannot be undone."
    }
  }
}

struct PurgeTransaction: Codable, Equatable, Sendable {
  let scope: PurgeScope
  let destinationID: String?
  var rootIdentity: String?
}

enum PurgeFailure: Error {
  case unavailable
  case changedDestination
  case pendingWork
  case unsafeResource
}

/// Implementations retain a durable barrier before deleting anything. A successful
/// return means deletion has relinquished all resources, including coordination.
@MainActor
protocol PurgePort: AnyObject {
  func pendingTransaction() throws -> PurgeTransaction?
  func prepare(_ scope: PurgeScope) async throws -> PurgeTransaction
  func begin(_ transaction: PurgeTransaction) throws
  func perform(_ transaction: PurgeTransaction, progress: @escaping @Sendable (Int) -> Void)
    async throws
  func finish() throws
}
