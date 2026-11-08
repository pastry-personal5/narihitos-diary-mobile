import Foundation

/// One coalesced reader rebuilds the demanded window from a single keyset revision.
@MainActor
final class RememberedCatalogPresentation {
  let catalog: any IndexedAssetCatalogPort
  var onChange: (@MainActor () -> Void)?
  private(set) var rows: [CatalogListRow] = []
  private(set) var summaries: [CatalogSummary] = []
  private(set) var recovery: [CatalogRecovery] = []
  private(set) var state: CatalogModel.State = .idle
  private(set) var isActive = false
  private(set) var requestedCount = 10
  private(set) var isReading = false
  private(set) var pageRevision = UUID()
  private var continuation: CatalogIndexCursor?
  private var operation: Task<Void, Never>?
  private var generation = UUID()
  private var pendingRefresh = false
  private var lastViewportEvent: UUID?

  init(catalog: any IndexedAssetCatalogPort) { self.catalog = catalog }

  var canLoadMore: Bool {
    isActive && !isReading && state != .unavailable && rows.count >= requestedCount
      && catalog.projectionStatus?.wait == nil
      && (continuation != nil || catalog.projectionStatus?.exhausted != true)
  }

  func start() {
    reset()
    isActive = true
    state = .loading
    catalog.requestVisibleCount(requestedCount)
    refresh()
  }

  func reset() {
    generation = UUID()
    operation?.cancel()
    operation = nil
    rows = []
    summaries = []
    recovery = []
    state = .idle
    isActive = false
    isReading = false
    requestedCount = 10
    pendingRefresh = false
    continuation = nil
    lastViewportEvent = nil
  }

  /// The caller supplies a new event only for another user scroll or explicit activation.
  func requestMore(event: UUID) {
    guard canLoadMore, event != lastViewportEvent else { return }
    lastViewportEvent = event
    requestedCount += 10
    catalog.requestVisibleCount(requestedCount)
    refresh()
  }

  func refresh() {
    guard isActive else { return }
    if isReading {
      pendingRefresh = true
      return
    }
    isReading = true
    let epoch = generation
    operation = Task { [weak self] in
      guard let self else { return }
      repeat {
        pendingRefresh = false
        do {
          let snapshot = try await readWindow()
          guard epoch == generation, !Task.isCancelled else { return }
          accept(snapshot)
        } catch {
          guard epoch == generation, !Task.isCancelled else { return }
          // A changing ordering revision never becomes an empty-source claim.
          state = rows.isEmpty ? .unavailable : .loaded
        }
      } while pendingRefresh && epoch == generation && !Task.isCancelled
      guard epoch == generation else { return }
      isReading = false
      onChange?()
    }
  }

  private func readWindow() async throws -> CatalogIndexPage {
    for attempt in 0..<3 {
      do {
        var result: [CatalogRememberedRow] = []
        var cursor: CatalogIndexCursor?
        var complete = false
        repeat {
          try Task.checkCancellation()
          let page = try await catalog.remembered(after: cursor)
          result += page.rows
          cursor = page.continuation
          complete = page.enumerationComplete
        } while result.count < requestedCount && cursor != nil
        return CatalogIndexPage(rows: result, continuation: cursor, enumerationComplete: complete)
      } catch CatalogIndexFailure.changed {
        if attempt == 2 { throw CatalogIndexFailure.changed }
        await Task.yield()
      }
    }
    throw CatalogIndexFailure.changed
  }

  private func accept(_ page: CatalogIndexPage) {
    let status = catalog.projectionStatus
    let current = Dictionary(
      uniqueKeysWithValues: (status?.currentSummaries ?? []).map { ($0.id, $0) })
    rows = page.rows.map { row in
      if let summary = current[row.id.rawValue], Self.matches(summary, row) {
        return .current(summary)
      }
      return .remembered(row)
    }
    summaries = rows.compactMap { row in
      if case .current(let summary) = row { return summary }
      return nil
    }
    recovery = status?.recovery ?? []
    continuation = page.continuation
    if rows.isEmpty {
      state = status?.wait != nil ? .unavailable : (status?.exhausted == true ? .end : .discovering)
    } else {
      state = status?.exhausted == true && continuation == nil ? .end : .loaded
    }
    pageRevision = UUID()
    onChange?()
  }

  private static func matches(_ summary: CatalogSummary, _ row: CatalogRememberedRow) -> Bool {
    summary.assetID == row.assetID && summary.title == row.title
      && summary.createdAt == row.createdAt
      && summary.favorite == row.favorite && summary.resourceOrder == row.resourceOrder
      && summary.handle.kind == row.kind
  }
}
