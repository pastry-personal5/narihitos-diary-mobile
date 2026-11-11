import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
final class FakeCatalog: AssetCatalogPort {
  var onEvent: (@MainActor (CatalogEvent) -> Void)?
  let session = CatalogSessionID()
  var pages = 0
  var begins = 0
  var ends = 0
  var holdPage = false
  var waiting: CheckedContinuation<CatalogPage, Error>?
  var queuedPages: [CatalogPage] = []
  var pageFailures: [CatalogIssue] = []
  var detailPayload: (any CatalogDetailPayload)?
  var holdDetail = false
  var detailCalls = 0
  var waitingDetail: CheckedContinuation<CatalogDetail, Error>?
  func begin() async -> CatalogStart {
    begins += 1
    return .ready(session, CatalogCursor(session: session, token: UUID()))
  }
  func page(_ cursor: CatalogCursor) async throws -> CatalogPage {
    pages += 1
    if holdPage {
      return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    if !pageFailures.isEmpty { throw pageFailures.removeFirst() }
    if !queuedPages.isEmpty { return queuedPages.removeFirst() }
    return CatalogPage(
      session: session, summaries: [], recovery: [], continuation: nil, examinedCandidates: 0,
      isDiscovering: false)
  }
  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail {
    detailCalls += 1
    if holdDetail {
      return try await withCheckedThrowingContinuation { waitingDetail = $0 }
    }
    if let detailPayload { return CatalogDetail(handle: handle, payload: detailPayload) }
    throw CatalogIssue.changed
  }
  func end() { ends += 1 }
}

@MainActor
struct CatalogModelTests {
  @Test func navigationDismissalCancelsDetailAndFencesItsLateResult() async throws {
    let fake = FakeCatalog()
    fake.holdDetail = true
    let model = CatalogModel(catalog: fake)
    let handle = CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: "test")
    model.open(handle)
    for _ in 0..<100 where fake.waitingDetail == nil { await Task.yield() }
    let waiting = try #require(fake.waitingDetail)
    let operation = try #require(model.detailOperation)

    // SwiftUI writes nil to the destination binding when Back dismisses the route.
    model.selection = nil
    #expect(operation.isCancelled)
    #expect(model.detailOperation == nil)
    waiting.resume(
      returning: CatalogDetail(handle: handle, payload: ReconciliationFixturePayload(text: "Old")))
    await operation.value
    #expect(model.selection == nil)
    #expect(model.detail == nil)
    #expect(model.detailIssue == nil)
  }

  @Test func dismissedDetailCannotOverwriteAReopenedSnippet() async throws {
    let fake = FakeCatalog()
    fake.holdDetail = true
    let model = CatalogModel(catalog: fake)
    let handle = CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: "test")
    model.open(handle)
    for _ in 0..<100 where fake.waitingDetail == nil { await Task.yield() }
    let waiting = try #require(fake.waitingDetail)
    let previous = try #require(model.detailOperation)
    model.selection = nil
    fake.holdDetail = false
    fake.detailPayload = ReconciliationFixturePayload(text: "Fresh")
    model.open(handle)
    await model.detailOperation?.value
    waiting.resume(throwing: CatalogIssue.unavailable)
    await previous.value
    #expect(model.selection == .current(handle))
    #expect((model.detail?.payload as? ReconciliationFixturePayload)?.text == "Fresh")
    #expect(model.detailIssue == nil)
    model.stop()
  }

  @Test func changedPageRestartsFreshTraversalInsteadOfReportingFolderUnavailable() async {
    let fake = FakeCatalog()
    fake.pageFailures = [.changed]
    let model = CatalogModel(catalog: fake)

    model.setVisible(true)
    model.activate()
    await wait(for: .end, model: model)

    #expect(model.state == .end)
    #expect(fake.begins == 2)
    #expect(fake.pages == 2)
    model.stop()
  }

  @Test func repeatedChangedPagesExhaustBoundedRestarts() async {
    let fake = FakeCatalog()
    fake.pageFailures = Array(repeating: .changed, count: 10)
    let model = CatalogModel(catalog: fake)

    model.setVisible(true)
    model.activate()
    await wait(for: .unavailable, model: model)

    let expectedAttempts = CatalogModel.maximumAutomaticChangedPageRestarts + 1
    #expect(model.state == .unavailable)
    #expect(fake.begins == expectedAttempts)
    #expect(fake.pages == expectedAttempts)
    model.stop()
  }

  @Test func unavailablePageDoesNotUseChangedPageRetryBudget() async {
    let fake = FakeCatalog()
    fake.pageFailures = [.unavailable]
    let model = CatalogModel(catalog: fake)

    model.setVisible(true)
    model.activate()
    await wait(for: .unavailable, model: model)

    #expect(fake.begins == 1)
    #expect(fake.pages == 1)
    model.stop()
  }

  @Test func stoppingDuringChangedPageDelayCannotRestartCatalog() async {
    let fake = FakeCatalog()
    fake.pageFailures = [.changed]
    let model = CatalogModel(catalog: fake)

    model.setVisible(true)
    model.activate()
    for _ in 0..<100 where fake.pages == 0 { await Task.yield() }
    #expect(fake.pages == 1)

    model.stop()
    try? await Task.sleep(for: .milliseconds(150))

    #expect(model.state == .idle)
    #expect(fake.begins == 1)
    #expect(fake.pages == 1)
  }

  @Test func latePageAfterStopCannotRepopulateCollection() async throws {
    let fake = FakeCatalog()
    fake.holdPage = true
    let model = CatalogModel(catalog: fake)
    model.setVisible(true)
    model.activate()
    for _ in 0..<100 where fake.waiting == nil { await Task.yield() }
    let waiting = try #require(fake.waiting)
    let handle = CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: "test")
    model.stop()
    waiting.resume(
      returning: CatalogPage(
        session: fake.session,
        summaries: [
          CatalogSummary(
            handle: handle, assetID: "test", resourceOrder: "test", createdAt: .now,
            title: "Synthetic", favorite: nil)
        ],
        recovery: [], continuation: nil, examinedCandidates: 1, isDiscovering: false))
    for _ in 0..<10 { await Task.yield() }
    #expect(model.summaries.isEmpty)
    #expect(model.state == .idle)
    #expect(model.selectedItem == nil)
  }

  @Test func changedDetailClosesItsOldRouteAndRefreshes() async throws {
    let fake = FakeCatalog()
    let model = CatalogModel(catalog: fake)
    model.setVisible(true)
    model.activate()
    for _ in 0..<100 where model.state != .end { await Task.yield() }
    let handle = CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: "test")
    model.open(handle)
    for _ in 0..<100 where model.selectedItem != nil { await Task.yield() }
    #expect(model.selectedItem == nil)
    #expect(model.detail == nil)
    model.stop()
  }

  @Test func hiddenCollectionDoesNotPrefetchAndExhaustedEmptyPageBecomesEnd() async throws {
    let fake = FakeCatalog()
    let model = CatalogModel(catalog: fake)
    model.activate()
    model.loadMore()
    #expect(fake.pages == 0)
    model.setVisible(true)
    for _ in 0..<100 where model.state != .end { await Task.yield() }
    #expect(model.state == .end)
    #expect(fake.pages == 1)
    model.loadMore()
    #expect(fake.pages == 1)
    model.stop()
  }

  @Test func leavingMainDuringPagingPreservesObservedRecoveryUntilFreshTraversal() async throws {
    let fake = FakeCatalog()
    let recoveryHandle = CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: "test")
    let summaryHandle = CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: "test")
    fake.queuedPages = [
      CatalogPage(
        session: fake.session,
        summaries: [
          CatalogSummary(
            handle: summaryHandle, assetID: "synthetic", resourceOrder: "synthetic",
            createdAt: .now, title: "Synthetic", favorite: nil)
        ],
        recovery: [
          CatalogRecovery(
            handle: recoveryHandle, issue: .missingAudio, hasText: true, hasAudio: false)
        ],
        continuation: CatalogCursor(session: fake.session, token: UUID()),
        examinedCandidates: 2, isDiscovering: false)
    ]
    let model = CatalogModel(catalog: fake)
    model.setVisible(true)
    model.activate()
    for _ in 0..<100 where model.recovery.isEmpty { await Task.yield() }
    #expect(model.recovery.count == 1)

    fake.holdPage = true
    model.loadMore()
    for _ in 0..<100 where fake.waiting == nil { await Task.yield() }
    let waiting = try #require(fake.waiting)
    model.setVisible(false)
    #expect(model.recovery.count == 1)
    #expect(model.knownRecoveryDestinations == [.incomplete])

    fake.holdPage = false
    waiting.resume(
      returning: CatalogPage(
        session: fake.session, summaries: [], recovery: [], continuation: nil,
        examinedCandidates: 0, isDiscovering: false))
    for _ in 0..<10 { await Task.yield() }
    #expect(model.recovery.count == 1)

    model.setVisible(true)
    for _ in 0..<100 where model.state != .end { await Task.yield() }
    #expect(model.recovery.isEmpty)
    model.stop()
  }

  private func wait(for state: CatalogModel.State, model: CatalogModel) async {
    for _ in 0..<200 {
      if model.state == state { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}

@MainActor
struct CatalogDateSectionTests {
  @Test func timezoneChangesRegroupOriginalInstantsWithoutChangingSummaries() throws {
    let session = CatalogSessionID()
    let date = try #require(ISO8601DateFormatter().date(from: "2026-01-02T00:30:00Z"))
    let entry = CatalogSummary(
      handle: CatalogItemHandle(session: session, resource: UUID(), version: UUID(), kind: "test"),
      assetID: "synthetic", resourceOrder: "synthetic", createdAt: date, title: "Synthetic",
      favorite: nil)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    var west = utc
    west.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let utcSections = CatalogDateSections.group([entry], calendar: utc)
    let westSections = CatalogDateSections.group([entry], calendar: west)
    #expect(utc.component(.day, from: try #require(utcSections.first?.date)) == 2)
    #expect(west.component(.day, from: try #require(westSections.first?.date)) == 1)
    #expect(utcSections.first?.entries == westSections.first?.entries)
  }
}
