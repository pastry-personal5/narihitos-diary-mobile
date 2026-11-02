import Foundation

/// File-presenter callbacks carry only invalidation, never source paths or content.
private final class CatalogFolderPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
  let presentedItemURL: URL?
  let presentedItemOperationQueue: OperationQueue
  private let changed: @Sendable () -> Void

  init(root: URL, changed: @escaping @Sendable () -> Void) {
    presentedItemURL = root
    self.changed = changed
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    presentedItemOperationQueue = queue
  }

  func presentedItemDidChange() { changed() }
  func presentedSubitemDidAppear(at url: URL) { changed() }
  func presentedSubitemDidChange(at url: URL) { changed() }
  func presentedItemDidMove(to newURL: URL) { changed() }
  func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
  func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
    changed()
    completionHandler(nil)
  }
  func accommodatePresentedSubitemDeletion(
    at url: URL, completionHandler: @escaping (Error?) -> Void
  ) {
    changed()
    completionHandler(nil)
  }
}

@MainActor
final class AppleAssetCatalog: AssetCatalogPort {
  var onEvent: (@MainActor (CatalogEvent) -> Void)?
  private let destination: AppleDestinationService
  private let registry: CatalogAssetRegistry
  private var worker: FileCatalogWorker?
  private var destinationID: DestinationID?
  private var presenter: CatalogFolderPresenter?
  private var epoch = UUID()
  private var busy = false
  private var refreshAfterSettlement = false

  init(destination: AppleDestinationService, registry: CatalogAssetRegistry) {
    self.destination = destination
    self.registry = registry
  }

  func begin() async -> CatalogStart {
    end()
    guard !busy else {
      refreshAfterSettlement = true
      return .unavailable
    }
    let generation = epoch
    let access = await destination.activeDestination()
    guard generation == epoch else { return .unavailable }
    guard let id = access.summary?.id else { return .noFolder }
    guard access.accessState == .accessible else { return .unavailable }
    let session = CatalogSessionID()
    let cursor = CatalogCursor(session: session, token: UUID())
    busy = true
    defer { settled() }
    do {
      try await destination.withActiveCatalog(expectedID: id) { root in
        guard generation == epoch else { throw CatalogIssue.changed }
        let observer = CatalogFolderPresenter(root: root) { [weak self] in
          Task { @MainActor [weak self] in self?.providerChanged() }
        }
        presenter = observer
        NSFileCoordinator.addFilePresenter(observer)
      }
      guard generation == epoch else {
        end()
        return .unavailable
      }
      destinationID = id
      worker = FileCatalogWorker(session: session, cursor: cursor, registry: registry)
      return .ready(session, cursor)
    } catch {
      end()
      return .unavailable
    }
  }

  func page(_ cursor: CatalogCursor) async throws -> CatalogPage {
    guard !busy, let worker, let destinationID else { throw CatalogIssue.unavailable }
    busy = true
    let generation = epoch
    defer { settled() }
    let result = try await destination.withActiveCatalog(expectedID: destinationID) { root in
      try await worker.page(cursor, root: root)
    }
    guard generation == epoch, !Task.isCancelled else { throw CatalogIssue.changed }
    return result
  }

  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail {
    guard !busy, let worker, let destinationID else { throw CatalogIssue.unavailable }
    busy = true
    let generation = epoch
    defer { settled() }
    let result = try await destination.withActiveCatalog(expectedID: destinationID) { root in
      try await worker.detail(handle, root: root)
    }
    guard generation == epoch, !Task.isCancelled else { throw CatalogIssue.changed }
    return result
  }

  func end() {
    epoch = UUID()
    if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
    presenter = nil
    worker = nil
    destinationID = nil
  }

  private func providerChanged() {
    guard worker != nil else { return }
    end()
    if busy { refreshAfterSettlement = true }
    onEvent?(.invalidated)
  }

  private func settled() {
    busy = false
    guard refreshAfterSettlement else { return }
    refreshAfterSettlement = false
    onEvent?(.invalidated)
  }
}
