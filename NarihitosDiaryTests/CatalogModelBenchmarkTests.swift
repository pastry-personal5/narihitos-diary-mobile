// swiftlint:disable trailing_comma
import Foundation
import Testing

@testable import NarihitosDiary

@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["NDM_CATALOG_BENCHMARK"] == "1"))
struct CatalogModelBenchmarkTests {
  @MainActor
  @Test func visibleCollectionIncludesDiscoveryScheduling() async throws {
    for count in [100, 1_000, 10_000] {
      let root = try CatalogBenchmarkTests().makeMetadata(count: count)
      defer { try? FileManager.default.removeItem(at: root) }
      for repeatIndex in 0..<5 {
        let source = BenchmarkLocalCatalog(root: root)
        let model = CatalogModel(catalog: source)
        let clock = ContinuousClock()
        let start = clock.now
        model.setVisible(true)
        model.activate()
        let deadline = start.advanced(by: .seconds(30))
        while model.summaries.count < 10, clock.now < deadline, model.state != .unavailable {
          try await Task.sleep(for: .milliseconds(1))
        }
        let elapsed = start.duration(to: clock.now)
        let milliseconds =
          Double(elapsed.components.seconds) * 1_000
          + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        #expect(model.summaries.count >= 10)
        let result: [String: Any] = [
          "corpus": "metadata-model", "entries": count, "repeat": repeatIndex,
          "session": "fresh-model-in-same-process", "millisecondsToFirstBatch": milliseconds,
          "rowsInFirstBatch": model.summaries.count, "counters": source.metrics.snapshot,
          "provider": "local-test-directory",
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("CATALOG_BENCHMARK " + (try #require(String(data: data, encoding: .utf8))))
        model.stop()
      }
    }
  }
}

@MainActor
private final class BenchmarkLocalCatalog: AssetCatalogPort {
  var onEvent: (@MainActor (CatalogEvent) -> Void)?
  let metrics = CatalogPerformanceProbe()
  private let root: URL
  private var worker: FileCatalogWorker?

  init(root: URL) { self.root = root }

  func begin() async -> CatalogStart {
    var registry = CatalogAssetRegistry()
    registry.register(BenchmarkMetadataHandler())
    let session = CatalogSessionID()
    let cursor = CatalogCursor(session: session, token: UUID())
    worker = FileCatalogWorker(
      session: session, cursor: cursor, registry: registry, metrics: metrics)
    return .ready(session, cursor)
  }

  func page(_ cursor: CatalogCursor) async throws -> CatalogPage {
    guard let worker else { throw CatalogIssue.unavailable }
    return try await worker.page(cursor, root: root)
  }

  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail {
    guard let worker else { throw CatalogIssue.unavailable }
    return try await worker.detail(handle, root: root)
  }

  func end() { worker = nil }
}

// swiftlint:enable trailing_comma
