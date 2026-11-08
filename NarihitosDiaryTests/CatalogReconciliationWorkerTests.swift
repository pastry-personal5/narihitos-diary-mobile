import Foundation
import Testing

@testable import NarihitosDiary

struct CatalogReconciliationWorkerTests {
  private let scope = CatalogIndexScope(
    key: String(repeating: "e", count: 64), validatorRevision: 1)

  @Test func firstTenAvoidOlderContentAndMetadataSweepContinuesWithoutScroll() async throws {
    let root = try makeReconciliationFixture([1: 200, 2: 70, 3: 15])
    let cache = root.appending(path: "private-cache")
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = CatalogReadProbe()
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: probe))
    let index = SQLiteCatalogIndex(root: cache, protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    var progress = try await worker.step(root: root, demand: 10)
    var steps = 1
    while !progress.demandSatisfied, steps < 100 {
      progress = try await worker.step(root: root, demand: 10)
      #expect(progress.candidateVisits <= 50)
      #expect(progress.enumerationVisits <= 50)
      steps += 1
    }
    #expect(progress.demandSatisfied)
    #expect(await worker.summaries().count == 10)
    #expect(await probe.keys.count == 10)
    #expect(await probe.keys.allSatisfy { $0.contains("2026/01/03/") })
    while !progress.metadataComplete, steps < 100 {
      progress = try await worker.step(root: root, demand: 10)
      #expect(progress.candidateVisits <= 50)
      #expect(progress.enumerationVisits <= 50)
      steps += 1
    }
    #expect(progress.metadataComplete)
    #expect(await probe.keys.count == 10)
    #expect(try await index.page(scope: scope, after: nil).enumerationComplete)
    await index.close()
  }

  @Test func demandFillsAcrossFailuresAndMatchesStrictTraversalAfterAllRows() async throws {
    let root = try makeReconciliationFixture([1: 60, 3: 15])
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("bad".utf8).write(to: root.appending(path: "2026/01/03/14.note"))
    try Data("unavailable".utf8).write(to: root.appending(path: "2026/01/03/13.note"))
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: CatalogReadProbe()))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    let final = try await drain(worker, root: root, demand: 100)
    #expect(final.exhausted)
    let current = await worker.summaries()
    #expect(current.count == 73)
    #expect(await worker.recovery().count == 2)
    let session = CatalogSessionID()
    var cursor: CatalogCursor? = CatalogCursor(session: session, token: UUID())
    let strict = FileCatalogWorker(
      session: session, cursor: try #require(cursor), registry: registry)
    var oracle = CatalogCollection()
    while let next = cursor {
      let page = try await strict.page(next, root: root)
      oracle.merge(page)
      cursor = page.continuation
    }
    #expect(current.map(\.assetID) == oracle.ordered.map(\.assetID))
    #expect(current.map(\.createdAt) == oracle.ordered.map(\.createdAt))
    await index.close()
  }

  @Test func laterDuplicateClaimRemovesEarlierRowAndRefillsDemandWithoutOldAudio() async throws {
    let root = try makeReconciliationFixture([1: 13, 3: 15])
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = CatalogReadProbe()
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: probe, duplicateNumber: 12))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    _ = try await drain(worker, root: root, demand: 10)
    #expect(await worker.summaries().count == 10)
    #expect(await worker.summaries().allSatisfy { $0.assetID != "duplicate" })
    #expect(await worker.recovery().filter { $0.issue == .duplicateID }.count == 2)
    #expect(await probe.keys.allSatisfy { $0.contains("2026/01/03/") })
    #expect(
      try await index.page(scope: scope, after: nil).rows.allSatisfy { $0.assetID != "duplicate" })
    await index.close()
  }

  @Test func rescanRetiresMissingRowsAndFindsChangedBytes() async throws {
    let root = try makeReconciliationFixture([3: 11])
    defer { try? FileManager.default.removeItem(at: root) }
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: CatalogReadProbe()))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    _ = try await drain(worker, root: root, demand: 20)
    try FileManager.default.removeItem(at: root.appending(path: "2026/01/03/10.note"))
    try Data("Replaced!".utf8).write(to: root.appending(path: "2026/01/03/9.note"))
    try await worker.begin()
    #expect(try await index.page(scope: scope, after: nil).rows.count == 10)
    _ = try await drain(worker, root: root, demand: 20)
    let rows = try await index.page(scope: scope, after: nil).rows
    #expect(rows.count == 10)
    #expect(rows.first?.title == "Replaced!")
    #expect(await worker.summaries().count == 10)
    await index.close()
  }

  @Test func cancellationOwnsHeldReadUntilSettlementAndPublishesNothingLate() async throws {
    let root = try makeReconciliationFixture([3: 12])
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = CatalogReadProbe()
    await probe.hold()
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: probe))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let lifetime = CatalogWorkerLifetime()
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID(),
      lifetime: lifetime)
    try await worker.begin()
    let operation = Task { try await drain(worker, root: root, demand: 10) }
    for _ in 0..<1_000 {
      if await probe.isHeld { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await probe.isHeld)
    lifetime.cancel()
    operation.cancel()
    await probe.release()
    await #expect(throws: CancellationError.self) { try await operation.value }
    #expect(try await index.page(scope: scope, after: nil).rows.isEmpty)
    await index.close()
  }

  private func drain(
    _ worker: CatalogReconciliationWorker, root: URL, demand: Int
  ) async throws -> CatalogReconciliationProgress {
    var last = try await worker.step(root: root, demand: demand)
    for _ in 0..<1_000 {
      if last.metadataComplete && (last.demandSatisfied || last.exhausted) { return last }
      last = try await worker.step(root: root, demand: demand)
      #expect(last.candidateVisits <= 50)
      #expect(last.enumerationVisits <= 50)
    }
    Issue.record("Reconciliation did not converge")
    return last
  }
}
