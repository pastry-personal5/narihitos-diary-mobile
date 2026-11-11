import Combine
import Foundation

@MainActor
final class CatalogModel: ObservableObject {
  static let maximumAutomaticChangedPageRestarts = 3

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
  @Published var detail: CatalogDetail?
  @Published var detailIssue: CatalogIssue?
  @Published var selection: CatalogSelection? {
    didSet {
      // Navigation dismissal owns detail cleanup. A tab switch can hide the detail while its
      // route remains selected; clearing only its content would strand that route on a spinner.
      if selection == nil { clearDetail() }
    }
  }
  var selectedItem: CatalogItemHandle? {
    get {
      guard let selection else { return nil }
      return selection.handle ?? detail?.handle
    }
    set { selection = newValue.map(CatalogSelection.current) }
  }
  private(set) var knownRecoveryDestinations: Set<CatalogRecoveryDestination> = []
  private var scopeID: DestinationID?
  var onChange: (@MainActor () -> Void)?
  let catalog: any AssetCatalogPort
  let remembered: RememberedCatalogPresentation?
  var collection = CatalogCollection()
  private var session: CatalogSessionID?
  private var cursor: CatalogCursor?
  private var operation: Task<Void, Never>?
  var detailOperation: Task<Void, Never>?
  var generation = UUID()
  private var visible = false
  private var active = false
  var loading = false
  private var automaticChangedPageRestarts = 0
  private var reopenAssetID: String?
  private var reopenRowID: CatalogRowID?
  private var reopenEditKey: String?
  private var reopenAfterReconciliation = false
  private var lastViewportEvent: UUID?

  init(catalog: any AssetCatalogPort) {
    self.catalog = catalog
    remembered = (catalog as? any IndexedAssetCatalogPort).map(RememberedCatalogPresentation.init)
    remembered?.onChange = { [weak self] in self?.acceptRemembered() }
    catalog.onEvent = { [weak self] event in
      guard let self, self.active, self.visible else { return }
      switch event {
      case .projectionChanged: self.remembered?.refresh()
      case .bindingsInvalidated:
        if self.selection != nil {
          self.clearDetail()
          self.detailIssue = .changed
        }
        self.remembered?.refresh()
      case .invalidated, .accessChanged: self.startRefresh()
      }
    }
  }

  var canLoadMore: Bool {
    if let remembered, remembered.isActive { return remembered.canLoadMore }
    return cursor != nil && !loading && state != .unavailable
  }
  var rows: [CatalogListRow] {
    if let remembered, remembered.isActive { return remembered.rows }
    return summaries.map(CatalogListRow.current)
  }
  var isLoadingMore: Bool {
    guard let remembered, remembered.isActive else {
      return state == .loading || state == .discovering
    }
    return !rows.isEmpty && rows.count < remembered.requestedCount
      && remembered.catalog.projectionStatus?.exhausted != true
      && remembered.catalog.projectionStatus?.wait == nil
  }

  func requestMore(event: UUID) {
    guard event != lastViewportEvent else { return }
    lastViewportEvent = event
    if let remembered, remembered.isActive {
      remembered.requestMore(event: event)
    } else {
      loadMore()
    }
  }

  func activate(destinationID: DestinationID? = nil) {
    let changed = scopeID != destinationID
    if changed {
      reopenAssetID = nil
      scopeID = destinationID
      knownRecoveryDestinations = []
    }
    active = true
    if visible {
      if changed { startRefresh() } else { refresh() }
    }
  }

  func changeScope(_ id: DestinationID?) {
    reopenAssetID = nil
    scopeID = id
    knownRecoveryDestinations = []
    startRefresh()
  }

  func setVisible(_ visible: Bool) {
    self.visible = visible
    if visible, active {
      if session == nil {
        refresh()
      } else if remembered?.isActive != true, summaries.isEmpty {
        loadMore()
      }
    } else if !visible, loading || remembered?.isActive == true {
      suspendAccessPreservingProjections()
    }
  }

  func discard() {
    reopenAssetID = nil
    reset()
    state = .unavailable
  }

  func stop() {
    reopenAssetID = nil
    active = false
    reset()
    (catalog as? any IndexedAssetCatalogPort)?.endActivation()
    state = .idle
  }

  func refresh() {
    if let remembered, remembered.isActive, remembered.catalog.usesRememberedRows {
      remembered.catalog.requestReconciliation()
      remembered.refresh()
      return
    }
    automaticChangedPageRestarts = 0
    startRefresh()
  }

  private func startRefresh() {
    let pinnedItem = reopenAssetID == nil ? nil : selectedItem
    let pinnedDetail = reopenAssetID == nil ? nil : detail
    reset()
    if let pinnedItem {
      selectedItem = pinnedItem
      detail = pinnedDetail
    }
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
        if let indexed = catalog as? any IndexedAssetCatalogPort, indexed.usesRememberedRows {
          remembered?.start()
        } else {
          loadMore()
        }
      case .noFolder: state = .noFolder
      case .unavailable: state = .unavailable
      }
    }
  }

  func loadMore() {
    if let remembered, remembered.isActive {
      remembered.requestMore(event: UUID())
      return
    }
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
        if error as? CatalogIssue == .changed {
          await restartAfterChangedPage(epoch: epoch)
          return
        }
        loading = false
        state = .unavailable
      }
    }
  }

  private func accept(_ page: CatalogPage) {
    automaticChangedPageRestarts = 0
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
    if let reopenAssetID {
      if let replacement = summaries.first(where: { $0.assetID == reopenAssetID }) {
        self.reopenAssetID = nil
        open(replacement.handle)
      } else if page.continuation == nil {
        self.reopenAssetID = nil
        selectedItem = nil
        clearDetail()
      } else if !loading {
        loadMore()
      }
    }
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

}

extension CatalogModel {
  func nearEnd(_ id: CatalogRowID, event: UUID) {
    guard rows.suffix(3).contains(where: { $0.id == id }) else { return }
    requestMore(event: event)
  }

  func refreshAfterDeletion() {
    reopenRowID = nil
    reopenEditKey = nil
    reopenAfterReconciliation = false
    selection = nil
    clearDetail()
    refresh()
  }

  func refreshAfterMutation(assetID: String, resourceKey: String? = nil) {
    if remembered?.isActive != true || resourceKey == nil {
      holdSelectionForMutation(assetID: assetID, resourceKey: resourceKey)
    }
    if remembered?.isActive == true {
      if resourceKey == reopenEditKey { reopenAfterReconciliation = true }
      clearDetail()
      refresh()
      return
    }
    refresh()
  }

  func holdSelectionForMutation(assetID: String, resourceKey: String? = nil) {
    let matches = summaries.contains { $0.handle == selectedItem && $0.assetID == assetID }
    let selectedMatches = matches || (detail?.payload as? DiaryCatalogDetail)?.assetID == assetID
    if remembered?.isActive == true, let selectedItem, selectedMatches {
      reopenRowID = CatalogRowID(selectedItem.resource)
      reopenEditKey = resourceKey
      reopenAfterReconciliation = false
      return
    }
    if matches { reopenAssetID = assetID }
  }

  private func acceptRemembered() {
    guard let remembered, remembered.isActive else { return }
    summaries = remembered.summaries
    recovery = remembered.recovery
    state = remembered.state
    pageRevision = remembered.pageRevision
    let destinations = Set(recovery.map(\.destination))
    if remembered.catalog.projectionStatus?.metadataComplete == true {
      knownRecoveryDestinations = destinations
    } else {
      knownRecoveryDestinations.formUnion(destinations)
    }
    if let selectedItem, let issue = recovery.first(where: { $0.id == selectedItem.id })?.issue {
      clearDetail()
      detailIssue = issue
    }
    let canReopen =
      reopenAfterReconciliation && remembered.catalog.projectionStatus?.metadataComplete == true
    if let id = reopenRowID, canReopen {
      reopenRowID = nil
      reopenEditKey = nil
      reopenAfterReconciliation = false
      if selection?.id == id.rawValue { open(CatalogSelection.remembered(id)) }
    }
    onChange?()
  }

  private func restartAfterChangedPage(epoch: UUID) async {
    guard automaticChangedPageRestarts < Self.maximumAutomaticChangedPageRestarts else {
      loading = false
      state = .unavailable
      return
    }
    automaticChangedPageRestarts += 1
    do {
      try await Task.sleep(for: .milliseconds(100))
    } catch {
      return
    }
    guard epoch == generation, !Task.isCancelled, active, visible else { return }
    startRefresh()
  }

  private func reset() {
    generation = UUID()
    reopenRowID = nil
    reopenEditKey = nil
    reopenAfterReconciliation = false
    operation?.cancel()
    operation = nil
    clearDetail()
    selectedItem = nil
    remembered?.reset()
    catalog.end()
    session = nil
    cursor = nil
    loading = false
    lastViewportEvent = nil
    collection = CatalogCollection()
    summaries = []
    recovery = []
    onChange?()
  }

  /// All can explain already observed recovery while Main is hidden. Catalog handles are not kept
  /// live: returning to Main starts a new selection-fenced traversal before anything can open.
  private func suspendAccessPreservingProjections() {
    reopenAssetID = nil
    generation = UUID()
    operation?.cancel()
    operation = nil
    clearDetail()
    selectedItem = nil
    remembered?.reset()
    catalog.end()
    session = nil
    cursor = nil
    loading = false
    state = .idle
  }
}
