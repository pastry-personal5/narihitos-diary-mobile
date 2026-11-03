import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
private final class EditRetryClock {
  var delays: [Duration] = []
  var pending: [CheckedContinuation<Void, Never>] = []

  func sleep(_ delay: Duration) async throws {
    delays.append(delay)
    await withCheckedContinuation { pending.append($0) }
  }

  func advance() { if !pending.isEmpty { pending.removeFirst().resume() } }
  func finish() {
    for waiter in pending { waiter.resume() }
    pending.removeAll()
  }
}

@MainActor
struct DiaryEditRetryTests {
  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw DiaryEditIssue.busy }
      await Task.yield()
    }
  }

  @Test func retirementFailureRediscoversWithoutCheckpointOrRepublishing() async throws {
    let store = MemoryDiaryEditStore()
    store.publication = .verified(DiaryEditFixture.version)
    store.uploadedMarkdown = true
    store.uploadedAudio = true
    store.failCleanup = true
    store.retireBeforeCleanupFailure = true
    let clock = EditRetryClock()
    let coordinator = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: EditTitleModel(), languageDetector: EditLanguageDetector()),
      retrySleep: { try await clock.sleep($0) })
    defer {
      coordinator.deactivate()
      clock.finish()
    }
    coordinator.activate()
    try await waitUntil { !coordinator.hasActiveWork }
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(true))
    #expect(await coordinator.submit(intent, session: session) == .accepted(intent.id))
    try await waitUntil { !clock.pending.isEmpty }
    #expect(store.retiredRecords == [intent.id])
    #expect(store.checkpointsAfterRetirement == 0)
    #expect(store.publishCount == 1)
    clock.advance()
    try await waitUntil { !coordinator.hasActiveWork && coordinator.pending.isEmpty }
    #expect(store.publishCount == 1)
    #expect(store.checkpointsAfterRetirement == 0)
  }

  @Test func uploadWaitingRetriesWithBoundedBackoffAndNoNewTitle() async throws {
    let store = MemoryDiaryEditStore()
    let model = EditTitleModel()
    let clock = EditRetryClock()
    let coordinator = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: model, languageDetector: EditLanguageDetector()),
      retrySleep: { try await clock.sleep($0) })
    defer {
      coordinator.deactivate()
      clock.finish()
    }
    coordinator.activate()
    try await waitUntil { !coordinator.hasActiveWork }
    store.publication = .verified(DiaryEditFixture.version)
    store.uploadedMarkdown = true
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body("Submitted."))
    _ = await coordinator.submit(intent, session: session)
    try await waitUntil { !clock.pending.isEmpty }
    #expect(clock.delays == [.seconds(5)])
    #expect(store.cleanupCount == 0)
    for expected in [Duration.seconds(15), .seconds(30), .seconds(60), .seconds(60)] {
      let count = clock.delays.count
      clock.advance()
      try await waitUntil { clock.delays.count > count }
      #expect(clock.delays.last == expected)
    }
    store.uploadedAudio = true
    clock.advance()
    try await waitUntil { coordinator.pending.isEmpty && !coordinator.hasActiveWork }
    #expect(store.cleanupCount == 1)
    #expect(model.calls == 1)
    #expect(clock.pending.isEmpty)
  }

  @Test func maintenanceFencesUnsettledRetryCallbacks() async throws {
    let store = MemoryDiaryEditStore()
    let clock = EditRetryClock()
    let coordinator = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: EditTitleModel(), languageDetector: EditLanguageDetector()),
      retrySleep: { try await clock.sleep($0) })
    defer {
      coordinator.deactivate()
      clock.finish()
    }
    coordinator.activate()
    try await waitUntil { !coordinator.hasActiveWork }
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(true))
    _ = await coordinator.submit(intent, session: session)
    try await waitUntil { !clock.pending.isEmpty }
    let count = store.publishCount
    coordinator.suspendForMaintenance()
    store.records.removeAll()
    store.candidates.removeAll()
    clock.advance()
    for _ in 0..<50 { await Task.yield() }
    #expect(store.publishCount == count)
    #expect(store.records.isEmpty)
    coordinator.endMaintenance()
    coordinator.activate()
    try await waitUntil { !coordinator.hasActiveWork }
    #expect(coordinator.pending.isEmpty)
  }
}
