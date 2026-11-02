import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct AppleAssetCatalogTests {
  @Test func explicitRefreshWaitsForSupersededPageAndIgnoresOldPresenterCallback() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "catalog-refresh-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appending(path: "synthetic.test"))

    let record = StoredDestinationRecord(
      id: DestinationID.make().rawValue, displayName: "Synthetic", bookmark: Data([1]),
      identityArchive: Data([2]), disclosureAcknowledged: true)
    let store = CatalogDestinationStore(record: record)
    let platform = CatalogDestinationPlatform(root: root)
    let destination = AppleDestinationService(repository: store, platform: platform)
    let readGate = CatalogReadGate()
    var registry = CatalogAssetRegistry()
    registry.register(SuspendedCatalogHandler(gate: readGate))
    let catalog = AppleAssetCatalog(destination: destination, registry: registry)

    let firstStart = await catalog.begin()
    guard case .ready(_, var cursor) = firstStart else {
      Issue.record("Expected the initial catalog session")
      return
    }
    let oldPresenter = try #require(catalog.activePresenterID)
    let discovery = try await catalog.page(cursor)
    #expect(discovery.isDiscovering)
    cursor = try #require(discovery.continuation)

    let blockedPage = Task { try await catalog.page(cursor) }
    await readGate.waitUntilStarted()
    let replacement = Task { await catalog.begin() }
    await Task.yield()
    #expect(catalog.activePresenterID == nil)

    await readGate.release()
    _ = try? await blockedPage.value
    guard case .ready = await replacement.value else {
      Issue.record("A superseded traversal must restart instead of reporting unavailable")
      return
    }
    let currentPresenter = try #require(catalog.activePresenterID)
    #expect(currentPresenter != oldPresenter)

    catalog.providerChanged(presenterID: oldPresenter)
    #expect(catalog.activePresenterID == currentPresenter)
    #expect(platform.startCount == platform.stopCount)
    catalog.end()
  }
}

private actor CatalogReadGate {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func suspend() async {
    started = true
    for waiter in startWaiters { waiter.resume() }
    startWaiters.removeAll()
    await withCheckedContinuation { releaseWaiter = $0 }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

private struct SuspendedCatalogHandler: CatalogAssetHandler {
  let kind = "test"
  let gate: CatalogReadGate

  func descends(into _: [String]) -> Bool { false }

  func candidate(components: [String], safe: Bool) -> CatalogCandidate? {
    guard components.last?.hasSuffix(".test") == true else { return nil }
    return CatalogCandidate(
      components: components, handler: kind, date: Date(timeIntervalSince1970: 1),
      stableID: "synthetic", safe: safe)
  }

  func read(_: CatalogCandidate, root _: URL) async throws -> CatalogReadValue {
    await gate.suspend()
    return CatalogReadValue(
      version: "one", assetID: "synthetic", createdAt: Date(timeIntervalSince1970: 1),
      title: "Synthetic", favorite: false, payload: nil, issue: nil, hasText: true,
      hasAudio: true)
  }
}

@MainActor
private final class CatalogDestinationStore: DestinationSettingsStore {
  var record: StoredDestinationRecord?
  init(record: StoredDestinationRecord) { self.record = record }
  func loadDestination() -> StoredDestinationRecord? { record }
  func saveDestination(_ destination: StoredDestinationRecord) throws { record = destination }
}

@MainActor
private final class CatalogDestinationPlatform: DestinationPlatform {
  let root: URL
  var startCount = 0
  var stopCount = 0

  init(root: URL) { self.root = root }

  func startAccessing(_: URL) -> Bool {
    startCount += 1
    return true
  }

  func stopAccessing(_: URL) { stopCount += 1 }

  func inspect(_: URL) throws -> DestinationCandidateInspection {
    DestinationCandidateInspection(
      facts: DestinationCandidateFacts(
        isDirectory: true, isSymbolicLink: false, isUbiquitousItem: true,
        hasICloudIdentity: true),
      displayName: "Synthetic")
  }

  func makeBookmark(for _: URL) throws -> Data { Data([1]) }
  func resolveBookmark(_: Data) throws -> ResolvedDestinationBookmark {
    ResolvedDestinationBookmark(url: root, isStale: false)
  }
  func currentIdentityArchive() throws -> Data { Data([2]) }
  func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool { stored == current }
}
