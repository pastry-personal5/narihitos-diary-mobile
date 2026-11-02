import Combine
import Foundation

@MainActor
final class CatalogModel: ObservableObject {
  enum State: Equatable {
    case idle
    case loading
    case discovering
    case loaded
    case end
    case noFolder
    case unavailable
  }

  @Published private(set) var summaries: [CatalogSummary] = []
  @Published private(set) var recovery: [CatalogRecovery] = []
  @Published private(set) var state: State = .idle
  @Published private(set) var pageRevision = UUID()
  @Published private(set) var detail: CatalogDetail?
  @Published private(set) var detailIssue: CatalogIssue?
  @Published var selectedItem: CatalogItemHandle?
  private(set) var knownRecoveryDestinations: Set<CatalogRecoveryDestination> = []
  private var scopeID: DestinationID?
  var onChange: (@MainActor () -> Void)?
  private let catalog: any AssetCatalogPort
  private var collection = CatalogCollection()
  private var session: CatalogSessionID?
  private var cursor: CatalogCursor?
  private var operation: Task<Void, Never>?
  private var detailOperation: Task<Void, Never>?
  private var generation = UUID()
  private var visible = false
  private var active = false
  private var loading = false

  init(catalog: any AssetCatalogPort) {
    self.catalog = catalog
    catalog.onEvent = { [weak self] _ in
      guard let self, self.active, self.visible else { return }
      self.refresh()
    }
  }

  var canLoadMore: Bool { cursor != nil && !loading && state != .unavailable }

  func activate(destinationID: DestinationID? = nil) {
    if scopeID != destinationID {
      scopeID = destinationID
      knownRecoveryDestinations = []
    }
    active = true
    if visible { refresh() }
  }

  func changeScope(_ id: DestinationID?) {
    scopeID = id
    knownRecoveryDestinations = []
    refresh()
  }

  func setVisible(_ visible: Bool) {
    self.visible = visible
    if visible, active {
      if session == nil { refresh() } else if summaries.isEmpty { loadMore() }
    } else if !visible, loading {
      suspendAccessPreservingProjections()
    }
  }

  func discard() {
    reset()
    state = .unavailable
  }

  func stop() {
    active = false
    reset()
    state = .idle
  }

  func refresh() {
    reset()
    guard active, visible else {
      state = .idle
      return
    }
    state = .loading
    loading = true
    let epoch = generation
    operation = Task { [weak self] in
      guard let self else { return }
      let start = await catalog.begin()
      guard epoch == generation, !Task.isCancelled else { return }
      loading = false
      switch start {
      case .ready(let session, let cursor):
        self.session = session
        self.cursor = cursor
        state = .loaded
        loadMore()
      case .noFolder: state = .noFolder
      case .unavailable: state = .unavailable
      }
    }
  }

  func loadMore() {
    guard active, visible, canLoadMore, let cursor else { return }
    loading = true
    state = .loading
    let epoch = generation
    operation = Task { [weak self] in
      guard let self else { return }
      do {
        let page = try await catalog.page(cursor)
        guard epoch == generation, !Task.isCancelled, page.session == session else { return }
        accept(page)
        if summaries.isEmpty, page.continuation != nil {
          // Yield between progress-only slices; no busy polling or duplicate cursor request.
          try await Task.sleep(for: .milliseconds(30))
          guard epoch == generation, !Task.isCancelled else { return }
          loadMore()
        }
      } catch {
        guard epoch == generation, !Task.isCancelled else { return }
        loading = false
        state = .unavailable
      }
    }
  }

  private func accept(_ page: CatalogPage) {
    collection.merge(page)
    summaries = collection.ordered
    recovery = collection.recovery.values.sorted { $0.id.uuidString < $1.id.uuidString }
    let destinations = Set(recovery.map(\.destination))
    if page.continuation == nil {
      knownRecoveryDestinations = destinations
    } else {
      knownRecoveryDestinations.formUnion(destinations)
    }
    self.cursor = page.continuation
    loading = false
    state = page.continuation == nil ? .end : (page.isDiscovering ? .discovering : .loaded)
    pageRevision = UUID()
    onChange?()
    if let selectedItem {
      if let issue = recovery.first(where: { $0.id == selectedItem.id })?.issue {
        clearDetail()
        detailIssue = issue
      } else {
        let updated = summaries.first(where: { $0.id == selectedItem.id })
        if let updated, updated.handle != selectedItem {
          clearDetail()
          detailIssue = .changed
        }
      }
    }
  }

  func open(_ handle: CatalogItemHandle) {
    selectedItem = handle
    clearDetail()
    if collection.recovery[handle.id]?.issue == .duplicateID {
      detailIssue = .duplicateID
      return
    }
    let epoch = generation
    detailOperation = Task { [weak self] in
      guard let self else { return }
      do {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while loading {
          guard ContinuousClock.now < deadline else { throw CatalogIssue.unavailable }
          try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        let value = try await catalog.detail(handle)
        guard epoch == generation, !Task.isCancelled, selectedItem == handle else { return }
        detail = value
      } catch {
        guard epoch == generation, !Task.isCancelled else { return }
        let issue = (error as? CatalogIssue) ?? .unavailable
        if issue == .changed { refresh() } else { detailIssue = issue }
      }
    }
  }

  func clearDetail() {
    detailOperation?.cancel()
    detailOperation = nil
    detail = nil
    detailIssue = nil
  }

  private func reset() {
    generation = UUID()
    operation?.cancel()
    operation = nil
    clearDetail()
    selectedItem = nil
    catalog.end()
    session = nil
    cursor = nil
    loading = false
    collection = CatalogCollection()
    summaries = []
    recovery = []
    onChange?()
  }

  /// All can explain already observed recovery while Main is hidden. Catalog handles are not kept
  /// live: returning to Main starts a new selection-fenced traversal before anything can open.
  private func suspendAccessPreservingProjections() {
    generation = UUID()
    operation?.cancel()
    operation = nil
    clearDetail()
    selectedItem = nil
    catalog.end()
    session = nil
    cursor = nil
    loading = false
    state = .idle
  }
}

struct CatalogDateSection: Identifiable {
  let date: Date
  let entries: [CatalogSummary]
  var id: Date { date }
}

enum CatalogDateSections {
  static func group(_ summaries: [CatalogSummary], calendar: Calendar) -> [CatalogDateSection] {
    Dictionary(grouping: summaries) { calendar.startOfDay(for: $0.createdAt) }
      .map { CatalogDateSection(date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
  }
}
