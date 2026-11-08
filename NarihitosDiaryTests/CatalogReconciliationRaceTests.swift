import Foundation
import Testing

@testable import NarihitosDiary

struct CatalogReconciliationRaceTests {
  private let scope = CatalogIndexScope(
    key: String(repeating: "f", count: 64), validatorRevision: 1)

  @Test func ineligibleMetadataConvergesAfterVisibleDemandIsSatisfied() async throws {
    let root = try makeReconciliationFixture([1: 50, 3: 15])
    defer { try? FileManager.default.removeItem(at: root) }
    for number in 0..<120 {
      try Data("Do not decode".utf8).write(to: root.appending(path: "2026/01/01/\(number).junk"))
    }
    let probe = CatalogReadProbe()
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: probe))
    registry.register(MetadataRecoveryHandler())
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    try await drain(worker, root: root, demand: 10)
    #expect(await worker.summaries().count == 10)
    #expect(await worker.recovery().count == 120)
    #expect(await probe.keys.count == 10)
    await index.close()
  }

  @Test func unboundedHandlerCompletesMetadataBeforePublishingNewestRows() async throws {
    let root = try makeReconciliationFixture([1: 300, 3: 15])
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = CatalogReadProbe()
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: probe, bounded: false))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    for _ in 0..<5 {
      _ = try await worker.step(root: root, demand: 10)
      #expect(await worker.summaries().isEmpty)
      #expect(await probe.keys.isEmpty)
    }
    try await drain(worker, root: root, demand: 10)
    #expect(await worker.summaries().count == 10)
    #expect(await probe.keys.count == 10)
    #expect(await probe.keys.allSatisfy { $0.contains("2026/01/03/") })
    await index.close()
  }

  @Test func cancelledPartialScanCannotRetireHistoricalMissingRow() async throws {
    let root = try makeReconciliationFixture([1: 100, 3: 12])
    defer { try? FileManager.default.removeItem(at: root) }
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: CatalogReadProbe()))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    try await drain(worker, root: root, demand: 10)
    let removed = try #require(try await index.page(scope: scope, after: nil).rows.first)
    try FileManager.default.removeItem(at: root.appending(path: "2026/01/03/11.note"))
    try await worker.begin()
    _ = try await worker.step(root: root, demand: 10)
    worker.lifetime.cancel()
    _ = try await index.locator(for: removed.id, scope: scope)
    let replacement = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await replacement.begin()
    try await drain(replacement, root: root, demand: 10)
    await #expect(throws: CatalogIndexFailure.changed) {
      try await index.locator(for: removed.id, scope: scope)
    }
    await index.close()
  }

  @Test func restoredMtimeRevalidatesBytesAndRejectsOldHandle() async throws {
    let root = try makeReconciliationFixture([3: 11])
    defer { try? FileManager.default.removeItem(at: root) }
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: CatalogReadProbe()))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    try await drain(worker, root: root, demand: 10)
    let old = try #require(await worker.summaries().first)
    let file = root.appending(path: "2026/01/03/10.note")
    let date = try #require(
      try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    try Data("Replaced!".utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    await #expect(throws: CatalogIssue.changed) { try await worker.detail(old.handle, root: root) }
    try await worker.begin()
    try await drain(worker, root: root, demand: 10)
    let fresh = try #require(await worker.summaries().first)
    #expect(fresh.title == "Replaced!")
    #expect(fresh.id == old.id)
    #expect(fresh.handle != old.handle)
    await index.close()
  }

  @Test func dirtyScanRejectsLateObservationAndRetirement() async throws {
    let root = try makeReconciliationFixture([3: 1])
    defer { try? FileManager.default.removeItem(at: root) }
    let handler = ReconciliationBucketHandler(probe: CatalogReadProbe())
    let candidate = try #require(
      handler.candidate(components: ["2026", "01", "03", "0.note"], safe: true))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let scan = try await index.beginScan(scope: scope)
    let stamp = try await index.bind(candidate, scope: scope)
    let read = try await handler.read(candidate, root: root)
    try await index.invalidate(scope: scope)
    #expect(try await !index.apply(read, to: stamp, scope: scope))
    #expect(try await !index.retire([stamp], scan: scan, scope: scope))
    #expect(try await !index.markSeen([stamp.rowID], scan: scan, scope: scope))
    #expect(try await !index.finishScan(scan, scope: scope))
    _ = try await index.locator(for: stamp.rowID, scope: scope)
    await index.close()
  }

  private func drain(_ worker: CatalogReconciliationWorker, root: URL, demand: Int) async throws {
    for _ in 0..<1_000 {
      let progress = try await worker.step(root: root, demand: demand)
      #expect(progress.candidateVisits <= 50)
      #expect(progress.enumerationVisits <= 50)
      if progress.metadataComplete && (progress.demandSatisfied || progress.exhausted) { return }
    }
    Issue.record("Reconciliation did not converge")
  }
}

private struct MetadataRecoveryHandler: CatalogAssetHandler {
  let kind = "test.metadata-recovery"
  func descends(into components: [String]) -> Bool {
    DiaryCatalogHandler().descends(into: components)
  }
  func unexploredDateUpperBound(in components: [String]) -> Date? { .distantPast }
  func mayAppearInTimeline(_ candidate: CatalogCandidate) -> Bool { false }
  func candidate(components: [String], safe: Bool) -> CatalogCandidate? {
    guard components.last?.hasSuffix(".junk") == true else { return nil }
    return CatalogCandidate(
      components: components, handler: kind, date: nil, stableID: "", safe: safe)
  }
  func read(_ candidate: CatalogCandidate, root: URL) async throws -> CatalogReadValue {
    Issue.record("Known ineligible resources require metadata only")
    throw CatalogIssue.unsupported
  }
}
