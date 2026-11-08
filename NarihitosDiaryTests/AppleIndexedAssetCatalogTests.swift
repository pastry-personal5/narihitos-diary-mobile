import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct AppleIndexedAssetCatalogTests {
  @Test func warmRowsReturnBeforeHeldValidationAndStopWaitsForActualLoanSettlement() async throws {
    let root = try makeReconciliationFixture([1: 50, 3: 15])
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = CatalogReadProbe()
    let fixture = makeCatalog(root: root, probe: probe)
    let catalog = fixture.catalog
    guard case .ready = await catalog.begin() else {
      Issue.record("Expected indexed start")
      return
    }
    _ = try await catalog.remembered(after: nil)
    try await wait { catalog.projectionStatus?.metadataComplete == true }
    let firstRows = try await catalog.remembered(after: nil).rows
    #expect(firstRows.count == 10)
    catalog.endActivation()
    await catalog.settled()
    await probe.hold()
    guard case .ready = await catalog.begin() else {
      Issue.record("Expected warm start")
      return
    }
    let remembered = try await catalog.remembered(after: nil)
    #expect(remembered.rows == firstRows)
    for _ in 0..<2_000 {
      if await probe.isHeld { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await probe.isHeld)
    catalog.end()
    var finished = false
    let cleanup = Task {
      await catalog.settled()
      finished = true
    }
    await Task.yield()
    #expect(!finished)
    #expect(fixture.platform.activeLoans > 0)
    await probe.release()
    await cleanup.value
    #expect(fixture.platform.starts == fixture.platform.stops)
    #expect(fixture.platform.maximumLoans == 1)
    #expect(!catalog.usesRememberedRows)
  }

  @Test func accountMismatchAndRootReplacementCannotReturnOldTitles() async throws {
    let root = try makeReconciliationFixture([3: 12])
    let replacement = try makeReconciliationFixture([1: 1])
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: replacement)
    }
    let fixture = makeCatalog(root: root, probe: CatalogReadProbe())
    let catalog = fixture.catalog
    _ = await catalog.begin()
    _ = try await catalog.remembered(after: nil)
    try await wait { catalog.projectionStatus?.metadataComplete == true }
    fixture.platform.root = replacement
    await #expect(throws: CatalogScopeAccessFailure.self) {
      try await catalog.remembered(after: nil)
    }
    catalog.endActivation()
    await catalog.settled()
    fixture.platform.identity = Data([3])
    guard case .unavailable = await catalog.begin() else {
      Issue.record("Changed account must require restored access")
      return
    }
    #expect(!catalog.usesRememberedRows)
    await #expect(throws: CatalogIssue.self) { try await catalog.remembered(after: nil) }
    catalog.endActivation()
    await catalog.settled()
  }

  @Test func periodicReconciliationFindsMissedDeletionWithoutEagerHistoricalReads() async throws {
    let root = try makeReconciliationFixture([1: 120, 3: 15])
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = IndexedCatalogClock()
    let probe = CatalogReadProbe()
    let fixture = makeCatalog(root: root, probe: probe, clock: clock)
    let catalog = fixture.catalog
    _ = await catalog.begin()
    _ = try await catalog.remembered(after: nil)
    try await wait { catalog.projectionStatus?.metadataComplete == true }
    #expect(await probe.keys.count == 10)
    try FileManager.default.removeItem(at: root.appending(path: "2026/01/03/14.note"))
    await clock.advance()
    try await wait {
      guard let first = try? await catalog.remembered(after: nil).rows.first else { return false }
      return first.assetID?.hasSuffix("14.note") == false
        && catalog.projectionStatus?.metadataComplete == true
    }
    #expect(await probe.keys.allSatisfy { $0.contains("2026/01/03/") })
    catalog.endActivation()
    await catalog.settled()
  }

  @Test func failedProjectionUsesStrictCatalogAndCanRetryOnNextActivation() async throws {
    let root = try makeReconciliationFixture([3: 12])
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IndexedCatalogDestinationStore()
    let platform = IndexedCatalogDestinationPlatform(root: root)
    let destination = AppleDestinationService(repository: store, platform: platform)
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: CatalogReadProbe()))
    let catalog = AppleIndexedAssetCatalog(
      destination: destination, registry: registry,
      index: SQLiteCatalogIndex(
        root: root.appending(path: "cache"), protection: FailingCatalogProtection()),
      environment: CatalogProjectionEnvironment(
        installation: IndexedCatalogInstallation(), protectedDataAvailable: { true }))
    guard case .ready(_, var cursor) = await catalog.begin() else {
      Issue.record("Strict fallback must remain available")
      return
    }
    #expect(!catalog.usesRememberedRows)
    var rows: [CatalogSummary] = []
    for _ in 0..<20 {
      let page = try await catalog.page(cursor)
      rows += page.summaries
      guard let next = page.continuation else { break }
      cursor = next
    }
    #expect(rows.count == 12)
    catalog.endActivation()
    await catalog.settled()
    #expect(platform.starts == platform.stops)
  }

  @Test func memoryReleaseAndInternalResetPreserveSourceAndAllowOlderReopening() async throws {
    let root = try makeReconciliationFixture([3: 25])
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeCatalog(root: root, probe: CatalogReadProbe())
    let catalog = fixture.catalog
    _ = await catalog.begin()
    _ = try await catalog.remembered(after: nil)
    catalog.requestVisibleCount(20)
    try await wait {
      catalog.projectionStatus?.metadataComplete == true
        && catalog.projectionStatus?.demandSatisfied == true
    }
    let first = try await catalog.remembered(after: nil)
    let next = try #require(first.continuation)
    let second = try await catalog.remembered(after: next)
    let older = try #require(second.rows.last)
    let source = root.appending(path: "2026/01/03/5.note")
    let bytes = try Data(contentsOf: source)
    await catalog.releaseMemory()
    #expect(!catalog.usesRememberedRows)
    _ = await catalog.begin()
    _ = try await catalog.remembered(after: nil)
    let detail = try await catalog.resolve(older.id)
    #expect((detail.payload as? ReconciliationFixturePayload)?.text == "Synthetic")
    await catalog.resetProjection()
    _ = await catalog.begin()
    #expect(try await catalog.remembered(after: nil).rows.isEmpty)
    catalog.requestVisibleCount(20)
    try await wait {
      catalog.projectionStatus?.metadataComplete == true
        && catalog.projectionStatus?.demandSatisfied == true
    }
    let rebuilt = try await catalog.remembered(after: nil)
    #expect(rebuilt.rows.count == 10)
    #expect(try Data(contentsOf: source) == bytes)
    #expect(fixture.platform.maximumLoans == 1)
    catalog.endActivation()
    await catalog.settled()
  }

  @Test func mutationHintFencesHeldInspectionAndCoalescesRestart() async throws {
    let root = try makeReconciliationFixture([3: 12])
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = CatalogReadProbe()
    let clock = IndexedCatalogClock()
    await probe.hold()
    let fixture = makeCatalog(root: root, probe: probe, clock: clock)
    let catalog = fixture.catalog
    _ = await catalog.begin()
    _ = try await catalog.remembered(after: nil)
    try await wait { await probe.isHeld }
    try Data("Replaced!".utf8).write(to: root.appending(path: "2026/01/03/11.note"))
    for _ in 0..<500 { catalog.sourceDidChange() }
    await probe.release()
    #expect(try await catalog.remembered(after: nil).rows.isEmpty)
    try await wait { await clock.pending == 1 }
    await clock.advance()
    try await wait { catalog.projectionStatus?.metadataComplete == true }
    #expect(try await catalog.remembered(after: nil).rows.first?.title == "Replaced!")
    #expect(fixture.platform.maximumLoans == 1)
    catalog.endActivation()
    await catalog.settled()
  }

  private func makeCatalog(
    root: URL, probe: CatalogReadProbe, clock: IndexedCatalogClock = IndexedCatalogClock()
  ) -> (catalog: AppleIndexedAssetCatalog, platform: IndexedCatalogDestinationPlatform) {
    let store = IndexedCatalogDestinationStore()
    let platform = IndexedCatalogDestinationPlatform(root: root)
    let destination = AppleDestinationService(repository: store, platform: platform)
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: probe))
    let catalog = AppleIndexedAssetCatalog(
      destination: destination, registry: registry,
      index: SQLiteCatalogIndex(
        root: root.appending(path: "cache"), protection: DiaryFixtureProtection()),
      environment: CatalogProjectionEnvironment(
        installation: IndexedCatalogInstallation(), protectedDataAvailable: { true },
        sleep: { try await clock.sleep($0) }))
    return (catalog, platform)
  }

  private func wait(_ condition: @MainActor () async throws -> Bool) async throws {
    for _ in 0..<5_000 {
      if try await condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Catalog did not reach the expected state")
  }
}
