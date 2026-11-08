import CryptoKit
import Foundation
import UIKit

@MainActor
struct CatalogProjectionEnvironment {
  let installation: any InstallationIdentityPort
  var protectedDataAvailable: @MainActor () -> Bool = {
    UIApplication.shared.isProtectedDataAvailable
  }
  var maintenanceBlocked: @MainActor () -> Bool = { false }
  var projectionGeneration: @MainActor () throws -> String = { "initial" }
  var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  var sweepInterval: Duration = .seconds(30)
  var allowed: Bool { protectedDataAvailable() && !maintenanceBlocked() }
}

/// Scoped orchestration only; SQLite never joins an authoritative diary transaction.
@MainActor
final class AppleIndexedAssetCatalog: IndexedAssetCatalogPort, CatalogActionBindingSource {
  // Adapter-internal state is shared with the reconciliation extension; ports expose values only.
  var onEvent: (@MainActor (CatalogEvent) -> Void)?
  var usesRememberedRows = false
  var projectionStatus: CatalogProjectionStatus?
  let destination: AppleDestinationService
  let registry: CatalogAssetRegistry
  let index: SQLiteCatalogIndex
  let environment: CatalogProjectionEnvironment
  let fallback: AppleAssetCatalog
  let access: CatalogProviderAccess
  var worker: CatalogReconciliationWorker?
  var scope: CatalogIndexScope?
  var destinationID: DestinationID?
  var presenter: CatalogFolderPresenter?
  var epoch = UUID()
  var cursor: CatalogCursor?
  var demand = 10
  var pump: Task<Void, Never>?
  var restart: Task<Void, Never>?
  var restartID: UUID?
  var cleanup: Task<Void, Never>?
  var resetBudgetOnCleanup = false
  var waitingForSweep = false
  var initialPage: CatalogIndexPage?
  var usingFallback = false
  var projectionDisabled = false
  var retryAttempt = 0
  var delivered: Set<UUID> = []
  var rootIdentity: String?
  var purgeGeneration: String?
  var activePresenterID: UUID? { presenter?.id ?? fallback.activePresenterID }
  func settled() async {
    await cleanup?.value
    await access.settled()
  }

  init(
    destination: AppleDestinationService, registry: CatalogAssetRegistry,
    index: SQLiteCatalogIndex, environment: CatalogProjectionEnvironment
  ) {
    self.destination = destination
    self.registry = registry
    self.index = index
    self.environment = environment
    fallback = AppleAssetCatalog(destination: destination, registry: registry)
    access = CatalogProviderAccess(destination: destination, allowed: { environment.allowed })
    fallback.onEvent = { [weak self] event in self?.onEvent?(event) }
  }

  func begin() async -> CatalogStart {
    end()
    let generation = epoch
    await cleanup?.value
    guard generation == epoch, environment.allowed, !Task.isCancelled else { return .unavailable }
    guard let purgeGeneration = try? environment.projectionGeneration() else { return .unavailable }
    self.purgeGeneration = purgeGeneration
    if projectionDisabled {
      usingFallback = true
      return await fallback.begin()
    }
    let current = await destination.activeDestination()
    guard generation == epoch else { return .unavailable }
    guard let id = current.summary?.id else { return .noFolder }
    guard current.accessState == .accessible else { return .unavailable }
    destinationID = id
    let session = CatalogSessionID()
    do {
      guard case .available(let installation) = environment.installation.currentOrCreate() else {
        throw CatalogIndexFailure.unavailable
      }
      let record = try await destination.committedDestinationRecord()
      let result = try await access.perform(expectedID: id, userRequested: true) { root in
        try await prepare(
          root: root, installation: installation, record: record, session: session,
          generation: generation)
      }
      guard generation == epoch, environment.allowed else { throw CatalogIssue.changed }
      try verifyPurgeGeneration()
      scope = result.0
      initialPage = result.1
      usesRememberedRows = true
      let firstCursor = CatalogCursor(session: session, token: UUID())
      cursor = firstCursor
      projectionStatus = CatalogProjectionStatus(
        session: session, metadataComplete: false, demandSatisfied: false, exhausted: false,
        recovery: [])
      return .ready(session, firstCursor)
    } catch {
      return await fallbackAfterStartFailure(error, generation: generation)
    }
  }

  func remembered(after requested: CatalogIndexCursor?) async throws -> CatalogIndexPage {
    guard usesRememberedRows, let scope, let id = destinationID else {
      throw CatalogIssue.unavailable
    }
    let generation = epoch
    let page = try await currentAccess(id) { root in
      try await verifyRoot(root)
      if requested == nil, let initialPage {
        self.initialPage = nil
        return initialPage
      }
      return try await index.page(scope: scope, after: requested)
    }
    guard generation == epoch, environment.allowed else { throw CatalogIssue.changed }
    if pump == nil, let worker { startPump(worker, generation: generation) }
    return page
  }

  func requestVisibleCount(_ count: Int) {
    guard count > demand else { return }
    demand = count
    if waitingForSweep, let worker {
      pump?.cancel()
      waitingForSweep = false
      startPump(worker, generation: epoch)
    }
  }

  func page(_ requested: CatalogCursor) async throws -> CatalogPage {
    if usingFallback { return try await fallback.page(requested) }
    guard usesRememberedRows, cursor == requested, let worker, let id = destinationID else {
      throw CatalogIssue.changed
    }
    let generation = epoch
    let progress = try await currentAccess(id) { root in
      try await worker.step(root: root, demand: demand)
    }
    guard generation == epoch else { throw CatalogIssue.changed }
    let summaries = await worker.summaries()
    let fresh = Array(summaries.filter { !delivered.contains($0.id) }.prefix(10))
    delivered.formUnion(fresh.map(\.id))
    let more = !progress.exhausted || delivered.count < summaries.count
    cursor = more ? CatalogCursor(session: requested.session, token: UUID()) : nil
    return CatalogPage(
      session: requested.session, summaries: fresh, recovery: await worker.recovery(),
      continuation: cursor, examinedCandidates: progress.candidateVisits,
      isDiscovering: !progress.metadataComplete)
  }

  func resolve(_ id: CatalogRowID) async throws -> CatalogDetail {
    guard usesRememberedRows, let worker, let destinationID else { throw CatalogIssue.changed }
    return try await currentAccess(destinationID) { root in
      try await worker.resolve(id, root: root)
    }
  }

  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail {
    if usingFallback { return try await fallback.detail(handle) }
    guard let worker, let destinationID else { throw CatalogIssue.changed }
    return try await currentAccess(destinationID) { root in
      try await worker.detail(handle, root: root)
    }
  }

  func actionBinding(_ handle: CatalogItemHandle) async throws -> CatalogActionBinding {
    if usingFallback { return try await fallback.actionBinding(handle) }
    guard let worker, let destinationID else { throw CatalogIssue.changed }
    return try await currentAccess(destinationID) { root in
      while await !worker.metadataIsComplete() {
        _ = try await worker.step(root: root, demand: 0)
        try Task.checkCancellation()
        await Task.yield()
      }
      let resource = try await worker.actionResource(handle, root: root)
      let stored = try await destination.committedDestinationRecord()
      guard stored.id == destinationID.rawValue else { throw CatalogIssue.changed }
      return CatalogActionBinding(destination: stored, resource: resource)
    }
  }

  func endActivation() {
    resetBudgetOnCleanup = true
    projectionDisabled = false
    retryAttempt = 0
    end()
  }

  func discardForPurge() async {
    endActivation()
    await settled()
    // The purge journal's generation already fences any artifact that cannot be removed.
    try? await index.discard()
  }

  func sourceDidChange() {
    guard let presenter else { return }
    providerChanged(presenterID: presenter.id)
  }

  func requestReconciliation() { sourceDidChange() }

  func end() {
    epoch = UUID()
    worker?.lifetime.cancel()
    worker = nil
    pump?.cancel()
    pump = nil
    restart?.cancel()
    restart = nil
    restartID = nil
    waitingForSweep = false
    if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
    presenter = nil
    fallback.end()
    access.invalidate()
    usesRememberedRows = false
    projectionStatus = nil
    usingFallback = false
    initialPage = nil
    scope = nil
    destinationID = nil
    rootIdentity = nil
    purgeGeneration = nil
    cursor = nil
    demand = 10
    delivered = []
    if cleanup == nil {
      cleanup = Task { [weak self] in
        guard let self else { return }
        await access.settled()
        await fallback.waitForSettlement()
        if resetBudgetOnCleanup { await index.close() } else { await index.suspend() }
        resetBudgetOnCleanup = false
        cleanup = nil
      }
    }
  }

  func providerChanged(presenterID: UUID) {
    guard presenter?.id == presenterID, usesRememberedRows else { return }
    worker?.lifetime.cancel()
    pump?.cancel()
    waitingForSweep = false
    initialPage = nil
    if let status = projectionStatus {
      projectionStatus = CatalogProjectionStatus(
        session: status.session, metadataComplete: false, demandSatisfied: false,
        exhausted: false, recovery: status.recovery)
    }
    if restart == nil { onEvent?(.bindingsInvalidated) }
    scheduleRestart(after: .milliseconds(50), generation: epoch)
  }

  static func scopeKey(
    installation: String, record: StoredDestinationRecord, rootIdentity: String,
    purgeGeneration: String
  ) throws -> String {
    let account = record.identityArchive
    let root = Data(rootIdentity.utf8)
    let parts = [Data(installation.utf8), Data(record.id.utf8), account, root]
    let data = try JSONEncoder().encode(parts + [Data(purgeGeneration.utf8)])
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
