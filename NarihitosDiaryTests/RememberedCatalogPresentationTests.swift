import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct RememberedCatalogPresentationTests {
  @Test func partialRowsFillToTenThenOneViewportEventRequestsTwenty() async throws {
    let port = RememberedCatalogFixture(count: 3)
    let presentation = RememberedCatalogPresentation(catalog: port)
    presentation.start()
    try await wait { !presentation.isReading }
    #expect(presentation.rows.count == 3)
    #expect(presentation.state == .loaded)
    #expect(!presentation.canLoadMore)
    port.source += (3..<50).map(RememberedCatalogFixture.row)
    port.revision += 1
    presentation.refresh()
    try await wait { !presentation.isReading }
    #expect(presentation.rows.count == 10)
    #expect(port.demands == [10])
    let event = UUID()
    for _ in 0..<100 { presentation.requestMore(event: event) }
    try await wait { !presentation.isReading }
    for _ in 0..<100 { presentation.requestMore(event: event) }
    #expect(port.demands == [10, 20])
    #expect(presentation.rows.count == 20)
    presentation.reset()
  }

  @Test func changedSnapshotRestartsWindowWithoutAppendingSkippedOrDuplicatedRows() async throws {
    let port = RememberedCatalogFixture(count: 35)
    let presentation = RememberedCatalogPresentation(catalog: port)
    presentation.start()
    try await wait { !presentation.isReading }
    port.afterQuery = {
      port.source.insert(RememberedCatalogFixture.row(-1), at: 0)
      port.source.remove(at: 8)
      port.revision += 1
    }
    presentation.requestMore(event: UUID())
    try await wait { !presentation.isReading }
    #expect(presentation.rows.map(\.id) == Array(port.source.prefix(20)).map(\.id))
    #expect(Set(presentation.rows.map(\.id)).count == 20)
    #expect(presentation.state == .loaded)
    presentation.reset()
  }

  @Test func warmRowsStaySilentAndTapGetsOnlyFreshResolvedHandle() async throws {
    let port = RememberedCatalogFixture(count: 20)
    port.holdResolve = true
    let model = CatalogModel(catalog: port)
    model.setVisible(true)
    model.activate()
    try await wait { model.rows.count == 10 && model.remembered?.isReading == false }
    #expect(model.state == .loaded)
    #expect(model.summaries.isEmpty)
    let row = try #require(model.rows.first)
    #expect(row.currentHandle == nil)
    model.open(row)
    try await wait { port.heldResolve != nil }
    #expect(model.selection == .remembered(row.id))
    #expect(model.selectedItem == nil)
    #expect(model.detail == nil)
    port.heldResolve?.resume()
    try await wait { model.detail != nil }
    #expect(port.resolved == [row.id])
    #expect(model.selectedItem == model.detail?.handle)
    #expect((model.detail?.payload as? ReconciliationFixturePayload)?.text == "Fresh")
    port.unavailable = true
    port.onEvent?(.accessChanged)
    #expect(model.rows.isEmpty)
    #expect(model.selection == nil)
    model.stop()
  }

  @Test func stopFencesLateQueryAndLeavingMainStopsIndexedDemand() async throws {
    let port = RememberedCatalogFixture(count: 20)
    port.holdQuery = true
    let model = CatalogModel(catalog: port)
    model.setVisible(true)
    model.activate()
    try await wait { port.heldQuery != nil }
    model.stop()
    port.heldQuery?.resume()
    for _ in 0..<20 { await Task.yield() }
    #expect(model.rows.isEmpty)
    #expect(model.state == .idle)
    model.activate()
    try await wait { model.rows.count == 10 }
    let queries = port.queries
    model.setVisible(false)
    model.requestMore(event: UUID())
    port.onEvent?(.projectionChanged)
    for _ in 0..<20 { await Task.yield() }
    #expect(port.queries == queries)
    #expect(model.remembered?.isActive == false)
    model.stop()
  }

  @Test func partialEmptyAndRememberedToEmptyRequireCurrentExhaustion() async throws {
    let port = RememberedCatalogFixture(count: 0)
    let presentation = RememberedCatalogPresentation(catalog: port)
    presentation.start()
    try await wait { !presentation.isReading }
    #expect(presentation.state == .discovering)
    port.source = (0..<3).map(RememberedCatalogFixture.row)
    port.revision += 1
    presentation.refresh()
    try await wait { !presentation.isReading }
    #expect(presentation.state == .loaded)
    port.source = []
    port.revision += 1
    port.projectionStatus = CatalogProjectionStatus(
      session: port.session, metadataComplete: true, demandSatisfied: false, exhausted: true,
      recovery: [])
    presentation.refresh()
    try await wait { !presentation.isReading }
    #expect(presentation.rows.isEmpty)
    #expect(presentation.state == .end)
    presentation.reset()
  }

  private func wait(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<2_000 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Presentation did not reach its expected state")
  }
}
