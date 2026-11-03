import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
final class MemoryDiaryDeletion: DiaryDeletionPort {
  var calls: [CatalogItemHandle] = []
  var issue: DiaryDeletionIssue?
  var hold = false
  var continuation: CheckedContinuation<Void, Never>?

  func delete(_ handle: CatalogItemHandle) async throws {
    calls.append(handle)
    if hold { await withCheckedContinuation { continuation = $0 } }
    if let issue { throw issue }
  }
}

@MainActor
struct DiaryDeletionTests {
  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw DiaryDeletionIssue.busy }
      await Task.yield()
    }
  }

  @Test func confirmationCancelAndInvalidationNeverDelete() async throws {
    let fixture = try await model()
    defer { fixture.edits.deactivate() }
    let actions = fixture.actions
    await actions.confirmDeletion(fixture.handle)
    actions.requestDeletion(fixture.handle)
    #expect(actions.deletionConfirmation == fixture.handle)
    actions.cancelDeletion()
    await actions.confirmDeletion(fixture.handle)
    actions.requestDeletion(fixture.handle)
    actions.hideDetail(fixture.handle)
    await actions.confirmDeletion(fixture.handle)
    actions.showDetail(fixture.handle)
    actions.requestDeletion(fixture.handle)
    actions.invalidateVisibleActions()
    await actions.confirmDeletion(fixture.handle)
    #expect(fixture.deletion.calls.isEmpty)
    #expect(actions.deletionConfirmation == nil)
  }

  @Test func confirmedDeletionSettlesReplayAndRejectsDuplicateOrEditWork() async throws {
    let fixture = try await model()
    defer { fixture.edits.deactivate() }
    fixture.replay.activate()
    fixture.replay.play(fixture.handle)
    try await waitUntil { fixture.replay.state == .playing }
    fixture.deletion.hold = true
    fixture.actions.requestDeletion(fixture.handle)
    let work = Task { await fixture.actions.confirmDeletion(fixture.handle) }
    try await waitUntil { fixture.deletion.continuation != nil }
    #expect(!fixture.replay.hasActiveWork)
    #expect(fixture.edits.hasActiveWork)
    #expect(!fixture.edits.beginDeletion())
    await #expect(throws: DiaryEditIssue.busy) { try await fixture.edits.open(fixture.handle) }
    await fixture.actions.confirmDeletion(fixture.handle)
    fixture.actions.requestDeletion(fixture.handle)
    #expect(fixture.actions.deletionConfirmation == nil)
    fixture.deletion.continuation?.resume()
    await work.value
    #expect(fixture.deletion.calls == [fixture.handle])
    #expect(!fixture.actions.isDeleting)
    #expect(!fixture.edits.hasActiveWork)
  }

  @Test func failureIsInlineAndNeedsFreshConfirmation() async throws {
    let fixture = try await model()
    defer { fixture.edits.deactivate() }
    fixture.deletion.issue = .changed
    fixture.actions.requestDeletion(fixture.handle)
    await fixture.actions.confirmDeletion(fixture.handle)
    #expect(fixture.actions.deletionMessage == DiaryDeletionIssue.changed.message)
    await fixture.actions.confirmDeletion(fixture.handle)
    #expect(fixture.deletion.calls.count == 1)
  }

  @Test func retainedEditsAndUnreviewedInventoryBlockDeletion() async throws {
    let fixture = try await model()
    defer { fixture.edits.deactivate() }
    let session = try await fixture.edits.open(fixture.handle)
    _ = await fixture.edits.submit(
      DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body("Retained edit.")),
      session: session)
    try await waitUntil { !fixture.edits.hasActiveWork }
    fixture.actions.requestDeletion(fixture.handle)
    await fixture.actions.confirmDeletion(fixture.handle)
    #expect(fixture.deletion.calls.isEmpty)
    #expect(fixture.actions.deletionMessage == DiaryDeletionIssue.busy.message)
    let isolated = try await model(isolated: 1)
    defer { isolated.edits.deactivate() }
    isolated.actions.requestDeletion(isolated.handle)
    await isolated.actions.confirmDeletion(isolated.handle)
    #expect(isolated.deletion.calls.isEmpty)
  }

  private struct ModelFixture {
    let actions: DiaryActionsModel
    let edits: DiaryEditCoordinator
    let replay: DiaryReplayCoordinator
    let deletion: MemoryDiaryDeletion
    let handle: CatalogItemHandle
  }

  private func model(isolated: Int = 0) async throws -> ModelFixture {
    let store = MemoryDiaryEditStore()
    store.isolatedCount = isolated
    let edits = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: EditTitleModel(), languageDetector: EditLanguageDetector()))
    let actions = DiaryActionsModel()
    let replay = DiaryReplayCoordinator(player: TestReplayPlayer())
    let deletion = MemoryDiaryDeletion()
    let handle = CatalogItemHandle(
      session: CatalogSessionID(), resource: UUID(), version: UUID(),
      kind: DiarySnippetSupportPolicy.kind)
    actions.configure(edits: edits, replay: replay, changed: {})
    actions.configureDeletion(deletion, didDelete: {})
    actions.showDetail(handle)
    edits.activate()
    try await waitUntil { !edits.hasActiveWork }
    return ModelFixture(
      actions: actions, edits: edits, replay: replay, deletion: deletion, handle: handle)
  }
}
