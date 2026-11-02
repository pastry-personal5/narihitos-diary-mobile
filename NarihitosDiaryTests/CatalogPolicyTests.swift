// swiftlint:disable trailing_comma
import Foundation
import Testing

@testable import NarihitosDiary

struct CatalogPolicyTests {
  @Test func duplicateIDsAcrossPagesPreserveBothAndVersionUpdatesReplaceRows() {
    let session = CatalogSessionID()
    let first = summary(session: session, assetID: "shared", date: 10)
    let second = summary(session: session, assetID: "shared", date: 20)
    var collection = CatalogCollection()
    collection.merge(page(session: session, summaries: [first]))
    #expect(collection.ordered == [first])
    collection.merge(page(session: session, summaries: [first, second]))
    #expect(collection.ordered.isEmpty)
    #expect(collection.recovery.count == 2)
    #expect(collection.recovery.values.allSatisfy { $0.issue == .duplicateID })
    let replacement = CatalogSummary(
      handle: CatalogItemHandle(
        session: session, resource: second.id, version: UUID(), kind: "test"),
      assetID: "other", resourceOrder: "replacement", createdAt: second.createdAt,
      title: "New version", favorite: nil)
    collection.merge(page(session: session, summaries: [replacement]))
    #expect(collection.ordered == [replacement, first])
    #expect(collection.recovery.isEmpty)
  }

  @Test func equalTimesUseAscendingStableIDsAndTransientReasonsStayRetryable() {
    let session = CatalogSessionID()
    let laterID = summary(session: session, assetID: "z", date: 10)
    let earlierID = summary(session: session, assetID: "a", date: 10)
    var collection = CatalogCollection()
    collection.merge(page(session: session, summaries: [laterID, earlierID]))
    #expect(collection.ordered == [earlierID, laterID])
    #expect(CatalogIssue.unavailable.retryable)
    #expect(CatalogIssue.changed.retryable)
    #expect(!CatalogIssue.malformed.retryable)
    #expect(CatalogIssue.conflict.destination == .conflicts)
    #expect(CatalogIssue.duplicateID.destination == .incomplete)
  }

  @Test func anonymousEqualTimeEntriesUseOpaqueResourceOrderInsteadOfRandomHandles() {
    let session = CatalogSessionID()
    let date = Date(timeIntervalSince1970: 10)
    let later = CatalogSummary(
      handle: CatalogItemHandle(
        session: session, resource: UUID(), version: UUID(), kind: "test"),
      assetID: nil, resourceOrder: "z-resource", createdAt: date, title: "Later", favorite: nil)
    let earlier = CatalogSummary(
      handle: CatalogItemHandle(
        session: session, resource: UUID(), version: UUID(), kind: "test"),
      assetID: nil, resourceOrder: "a-resource", createdAt: date, title: "Earlier", favorite: nil)
    var collection = CatalogCollection()
    collection.merge(page(session: session, summaries: [later, earlier]))
    #expect(collection.ordered == [earlier, later])
  }

  private func summary(session: CatalogSessionID, assetID: String, date: Double) -> CatalogSummary {
    CatalogSummary(
      handle: CatalogItemHandle(session: session, resource: UUID(), version: UUID(), kind: "test"),
      assetID: assetID, resourceOrder: assetID, createdAt: Date(timeIntervalSince1970: date),
      title: "Synthetic", favorite: nil)
  }

  private func page(session: CatalogSessionID, summaries: [CatalogSummary]) -> CatalogPage {
    CatalogPage(
      session: session, summaries: summaries, recovery: [], continuation: nil,
      examinedCandidates: summaries.count, isDiscovering: false)
  }
}

@MainActor
struct MainNoticeTests {
  @Test func countUpdatesDoNotResetRotationAndRecoveryRoutesDoNotStarve() {
    let model = MainNoticeModel(sleep: { try await Task.sleep(for: .seconds(3_600)) })
    var announcements: [String] = []
    model.announce = { announcements.append($0) }
    model.setEnvironment(visible: true, paused: false)
    let processing = MainNotice(category: .processing, destination: .pending, message: "Processing")
    let queued = MainNotice(category: .queued, destination: .pending, message: "One queued")
    let incomplete = MainNotice(
      category: .recovery, destination: .incomplete, message: "Incomplete")
    let conflicts = MainNotice(category: .recovery, destination: .conflicts, message: "Conflicts")
    model.update([incomplete, queued, processing, conflicts])
    #expect(model.current == processing)
    model.advance()
    #expect(model.current == queued)
    model.update([
      processing, MainNotice(category: .queued, destination: .pending, message: "Two queued"),
      incomplete, conflicts,
    ])
    #expect(model.current?.message == "Two queued")
    #expect(announcements.count == 4)
    model.advance()
    let firstRoute = model.current?.destination
    model.advance()
    model.advance()
    model.advance()
    #expect(model.current?.category == .recovery)
    #expect(model.current?.destination != firstRoute)
    model.setEnvironment(visible: true, paused: true)
    let frozen = model.current
    model.advance()
    #expect(model.current == frozen)
    model.setEnvironment(visible: false, paused: false)
  }

  @Test func foregroundReentryDoesNotReannounceAndRemovedStateCanReturn() {
    let model = MainNoticeModel()
    var announcements = 0
    model.announce = { _ in announcements += 1 }
    let value = MainNotice(category: .queued, destination: .pending, message: "Pending")
    model.update([value])
    model.setEnvironment(visible: true, paused: false)
    model.setEnvironment(visible: false, paused: true)
    model.setEnvironment(visible: true, paused: false)
    model.update([value])
    #expect(announcements == 1)
    model.update([])
    #expect(model.current == nil)
    model.update([value])
    #expect(announcements == 2)
    model.setEnvironment(visible: false, paused: true)
  }

  @Test func duplicateSemanticNoticesAreCoalescedBeforeRotation() {
    let model = MainNoticeModel(sleep: { try await Task.sleep(for: .seconds(3_600)) })
    model.setEnvironment(visible: true, paused: false)
    let processing = MainNotice(
      category: .processing, destination: .pending, message: "Processing")
    let first = MainNotice(
      category: .recovery, destination: .pending, message: "Pending work needs attention.")
    let duplicate = MainNotice(
      category: .recovery, destination: .pending, message: "Another pending source.")
    model.update([processing, first, duplicate])
    #expect(model.current == processing)
    model.advance()
    #expect(model.current == first)
    model.advance()
    #expect(model.current == processing)
    model.setEnvironment(visible: false, paused: true)
  }
}

// swiftlint:enable trailing_comma
