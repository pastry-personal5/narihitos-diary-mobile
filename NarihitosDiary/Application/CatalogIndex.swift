import Foundation

struct CatalogRowID: Hashable, Codable, Sendable {
  let rawValue: UUID
  init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Opaque comparison key supplied only after current installation/account/folder access is checked.
struct CatalogIndexScope: Hashable, Sendable {
  let key: String
  let validatorRevision: Int
}

/// Historical successful inspection. It deliberately has no session handle or storage capability.
struct CatalogRememberedRow: Equatable, Sendable, Identifiable {
  let id: CatalogRowID
  let kind: String
  let assetID: String?
  let resourceOrder: String
  let createdAt: Date
  let title: String
  let favorite: Bool?
}

struct CatalogTimelineKey: Equatable, Sendable {
  let instant: Date
  let sortID: String
  let resourceOrder: String

  func precedes(_ other: Self) -> Bool {
    if instant != other.instant { return instant > other.instant }
    return sortID == other.sortID ? resourceOrder < other.resourceOrder : sortID < other.sortID
  }
}

struct CatalogIndexCursor: Equatable, Sendable {
  let scope: CatalogIndexScope
  let session: UUID
  let epoch: UUID
  let orderingRevision: Int64
  let after: CatalogTimelineKey
}

struct CatalogIndexPage: Sendable {
  let rows: [CatalogRememberedRow]
  let continuation: CatalogIndexCursor?
  /// Historical coverage only; never a current unique-claim or mutation prerequisite.
  let enumerationComplete: Bool
}

enum CatalogIndexFailure: Error, Equatable {
  case unavailable
  case busy
  case capacity
  case incompatible
  case corrupt
  case unsafe
  case changed
}

/// Persistent projection queries are independent of file-backed action and mutation ports.
protocol CatalogIndexPort: Sendable {
  func page(scope: CatalogIndexScope, after cursor: CatalogIndexCursor?) async throws
    -> CatalogIndexPage
  func close() async
}
