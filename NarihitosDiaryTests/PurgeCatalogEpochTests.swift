import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
private final class PurgeCatalogSettlement {
  weak var catalog: AppleIndexedAssetCatalog?
  var calls = 0
  func settleWithoutRemovingCache() async {
    calls += 1
    catalog?.endActivation()
    await catalog?.settled()
    // Simulates an unavailable cache-removal operation. Source deletion must still succeed.
  }
}

@MainActor
struct PurgeCatalogEpochTests {
  @Test(arguments: PurgeScope.allCases)
  func retainedCacheCannotCrossCompletedPurge(_ scope: PurgeScope) async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("icloud/2026/01/03/0.note")
    let settlement = PurgeCatalogSettlement()
    let purge = ApplePurgeService(
      destination: fixture.destination, support: fixture.support,
      protection: DiaryFixtureProtection(), protectedDataAvailable: { true },
      settleProjection: { await settlement.settleWithoutRemovingCache() })
    let clock = IndexedCatalogClock()
    var registry = CatalogAssetRegistry()
    registry.register(ReconciliationBucketHandler(probe: CatalogReadProbe()))
    let cache = fixture.support.appending(path: "CatalogProjection")
    let catalog = AppleIndexedAssetCatalog(
      destination: fixture.destination, registry: registry,
      index: SQLiteCatalogIndex(root: cache, protection: DiaryFixtureProtection()),
      environment: CatalogProjectionEnvironment(
        installation: IndexedCatalogInstallation(), protectedDataAvailable: { true },
        projectionGeneration: { try purge.projectionGeneration() },
        sleep: { try await clock.sleep($0) }))
    settlement.catalog = catalog
    _ = await catalog.begin()
    _ = try await catalog.remembered(after: nil)
    try await wait { catalog.projectionStatus?.metadataComplete == true }
    let old = try #require(try await catalog.remembered(after: nil).rows.first)
    catalog.endActivation()
    await catalog.settled()
    let transaction = try await purge.prepare(scope)
    try purge.begin(transaction)
    // A new process obeys durable admission even if the old database is readable.
    guard case .unavailable = await catalog.begin() else {
      Issue.record("Interrupted purge must not reveal remembered titles")
      return
    }
    try await purge.perform(transaction) { _ in }
    try purge.finish()
    #expect(settlement.calls == 1)
    #expect(FileManager.default.fileExists(atPath: cache.appending(path: "catalog.sqlite").path))
    _ = await catalog.begin()
    let fresh = try await catalog.remembered(after: nil)
    #expect(fresh.rows.isEmpty)
    try await wait { catalog.projectionStatus?.metadataComplete == true }
    let final = try await catalog.remembered(after: nil).rows
    if scope == .internalStaging {
      #expect(final.count == 1)
      #expect(final.first?.id != old.id)
    } else {
      #expect(final.isEmpty)
    }
    catalog.endActivation()
    await catalog.settled()
  }

  private func wait(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<5_000 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Catalog did not settle")
  }
}
