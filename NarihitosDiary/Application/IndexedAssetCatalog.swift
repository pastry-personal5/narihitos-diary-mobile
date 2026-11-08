import Foundation

struct CatalogProjectionStatus: Sendable {
  let session: CatalogSessionID
  let metadataComplete: Bool
  let demandSatisfied: Bool
  let exhausted: Bool
  let recovery: [CatalogRecovery]
  var wait: CatalogIssue?
  var currentSummaries: [CatalogSummary] = []
}

@MainActor
protocol IndexedAssetCatalogPort: AssetCatalogPort {
  var usesRememberedRows: Bool { get }
  var projectionStatus: CatalogProjectionStatus? { get }
  func remembered(after cursor: CatalogIndexCursor?) async throws -> CatalogIndexPage
  func requestVisibleCount(_ count: Int)
  func requestReconciliation()
  func resolve(_ id: CatalogRowID) async throws -> CatalogDetail
  func endActivation()
}
