import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
final class RememberedCatalogFixture: IndexedAssetCatalogPort {
  var onEvent: (@MainActor (CatalogEvent) -> Void)?
  var usesRememberedRows = true
  let session = CatalogSessionID()
  var projectionStatus: CatalogProjectionStatus?
  var source: [CatalogRememberedRow]
  var revision: Int64 = 0
  var demands: [Int] = []
  var queries = 0
  var ends = 0
  var unavailable = false
  var afterQuery: (() -> Void)?
  var holdQuery = false
  var heldQuery: CheckedContinuation<Void, Never>?
  var holdResolve = false
  var heldResolve: CheckedContinuation<Void, Never>?
  var resolved: [CatalogRowID] = []

  init(count: Int) {
    source = (0..<count).map(Self.row)
    projectionStatus = CatalogProjectionStatus(
      session: session, metadataComplete: false, demandSatisfied: false, exhausted: false,
      recovery: [])
  }

  func begin() async -> CatalogStart {
    unavailable ? .unavailable : .ready(session, CatalogCursor(session: session, token: UUID()))
  }
  func page(_ cursor: CatalogCursor) async throws -> CatalogPage {
    Issue.record("Remembered presentation must not drain strict pages")
    throw CatalogIssue.unavailable
  }
  func remembered(after cursor: CatalogIndexCursor?) async throws -> CatalogIndexPage {
    queries += 1
    if holdQuery {
      holdQuery = false
      await withCheckedContinuation { heldQuery = $0 }
    }
    guard cursor == nil || cursor?.orderingRevision == revision else {
      throw CatalogIndexFailure.changed
    }
    let start: Int
    if let cursor {
      guard let index = source.firstIndex(where: { $0.resourceOrder == cursor.after.resourceOrder })
      else {
        throw CatalogIndexFailure.changed
      }
      start = index + 1
    } else {
      start = 0
    }
    let rows = Array(source.dropFirst(start).prefix(10))
    let next =
      start + rows.count < source.count
      ? rows.last.map {
        CatalogIndexCursor(
          scope: CatalogIndexScope(key: String(repeating: "a", count: 64), validatorRevision: 1),
          session: session.rawValue, epoch: session.rawValue, orderingRevision: revision,
          after: CatalogTimelineKey(
            instant: $0.createdAt, sortID: $0.assetID ?? $0.resourceOrder,
            resourceOrder: $0.resourceOrder))
      } : nil
    let callback = afterQuery
    afterQuery = nil
    callback?()
    return CatalogIndexPage(rows: rows, continuation: next, enumerationComplete: false)
  }
  func requestVisibleCount(_ count: Int) { demands.append(count) }
  func requestReconciliation() {}
  func resolve(_ id: CatalogRowID) async throws -> CatalogDetail {
    resolved.append(id)
    if holdResolve { await withCheckedContinuation { heldResolve = $0 } }
    guard let row = source.first(where: { $0.id == id }) else { throw CatalogIssue.unavailable }
    return CatalogDetail(
      handle: CatalogItemHandle(
        session: session, resource: id.rawValue, version: UUID(), kind: row.kind),
      payload: ReconciliationFixturePayload(text: "Fresh"))
  }
  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail {
    throw CatalogIssue.changed
  }
  func end() { ends += 1 }
  func endActivation() { end() }

  static func row(_ number: Int) -> CatalogRememberedRow {
    CatalogRememberedRow(
      id: CatalogRowID(), kind: "test", assetID: "synthetic-\(number)",
      resourceOrder: "resource-\(number)",
      createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 - Double(number)),
      title: "Synthetic \(number)", favorite: nil)
  }
}
