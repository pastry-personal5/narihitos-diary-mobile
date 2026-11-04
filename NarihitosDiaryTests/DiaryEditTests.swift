import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct DiaryEditTests {
  private func coordinator(
    _ store: MemoryDiaryEditStore, model: EditTitleModel = EditTitleModel()
  ) async -> DiaryEditCoordinator {
    let coordinator = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: model, languageDetector: EditLanguageDetector()),
      now: { Date(timeIntervalSince1970: 0) })
    coordinator.activate()
    await settle(coordinator)
    return coordinator
  }

  private func settle(_ coordinator: DiaryEditCoordinator) async {
    for _ in 0..<1_000 {
      if !coordinator.hasActiveWork { return }
      await Task.yield()
    }
  }

  @Test func bodyRevisionPreservesRecordingAndUnknownScalars() throws {
    let source = try DiaryEditFixture.snippet()
    let revision = try DiaryEditRevision.make(
      source: source, change: .body("새로운 하루입니다."), now: .distantPast)
    #expect(revision.body.text == "새로운 하루입니다.")
    #expect(revision.titleProvenance.originID.description == "first-sentence")
    #expect(revision.titleProvenance.promptRevision == nil)
    #expect(revision.updatedAt.description == "2026-11-01T12:34:57Z")
    var restored = revision
    restored.body = source.body
    restored.title = source.title
    restored.titleProvenance = source.titleProvenance
    restored.updatedAt = source.updatedAt
    #expect(restored == source)
    #expect(try DiarySnippetMarkdownCodec().encode(revision).count > 0)
  }

  @Test func favoriteNoOpAndEmptyBodyHaveDistinctPolicies() throws {
    let source = try DiaryEditFixture.snippet()
    #expect(
      try DiaryEditRevision.make(source: source, change: .favorite(false), now: Date()) == source)
    let favorite = try DiaryEditRevision.make(
      source: source, change: .favorite(true), now: .distantPast)
    #expect(favorite.titleProvenance == source.titleProvenance)
    #expect(favorite.body == source.body)
    #expect(favorite.favorite)
    let empty = try DiaryEditRevision.make(source: source, change: .body(" \n "), now: Date())
    #expect(empty.title == "Untitled")
    #expect(empty.titleProvenance.originID.description == "empty-body")
  }

  @Test func rapidAndRollbackRevisionsAdvanceWithoutChangingOnRetry() throws {
    let source = try DiaryEditFixture.snippet()
    let first = try DiaryEditRevision.make(
      source: source, change: .body("First."), now: .distantPast)
    let second = try DiaryEditRevision.make(
      source: first, change: .body("Second."), now: .distantPast)
    #expect(first.updatedAt.description == "2026-11-01T12:34:57Z")
    #expect(second.updatedAt.description == "2026-11-01T12:34:58Z")
    var limit = source
    limit.updatedAt = try SchemaInstant("9999-12-31T23:59:59Z")
    #expect(throws: DiaryEditIssue.invalidCandidate) {
      try DiaryEditRevision.make(source: limit, change: .body("Changed."), now: Date())
    }
  }

  @Test func durableAcceptancePrecedesTitleAndSurvivesNavigation() async throws {
    let store = MemoryDiaryEditStore()
    let model = EditTitleModel()
    model.hold = true
    let titles = DiaryTitlePolicy(model: model, languageDetector: EditLanguageDetector())
    let editor = DiaryEditCoordinator(store: store, titles: titles)
    editor.activate()
    await settle(editor)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body("Submitted."))
    #expect(await editor.submit(intent, session: session) == .accepted(intent.id))
    for _ in 0..<1_000 where model.continuation == nil { await Task.yield() }
    #expect(store.records[intent.id]?.stage == .accepted)
    #expect(titles.workSnapshot?.owner == .edit(submissionID: intent.id))
    #expect(titles.workSnapshot?.phase == .generating)
    editor.deactivate()
    model.continuation?.resume(
      returning: TitleModelReply(text: "A peaceful afternoon", outputTokens: 5))
    await settle(editor)
    #expect(titles.workSnapshot == nil)
    #expect(store.records[intent.id]?.stage == .ready)
    #expect(store.publishCount == 0)
    editor.activate()
    await settle(editor)
    #expect(store.publishCount == 1)
    #expect(store.records[intent.id]?.issue == .unavailable)
  }

  @Test func duplicateLostReplyAndChangedIdentityCannotCreateAnotherEdit() async throws {
    let store = MemoryDiaryEditStore()
    let editor = await coordinator(store)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(true))
    #expect(await editor.submit(intent, session: session) == .accepted(intent.id))
    await settle(editor)
    let savedTime = store.candidates[intent.id]?.updatedAt
    #expect(await editor.submit(intent, session: session) == .accepted(intent.id))
    #expect(store.acceptCount == 1)
    #expect(store.candidates[intent.id]?.updatedAt == savedTime)
    let forged = DiaryEditSubmission(
      id: intent.id, sessionID: session.id, change: .body("Different."))
    #expect(await editor.submit(forged, session: session) == .rejected(.changed))
    #expect(store.acceptCount == 1)
  }

  @Test func partialUploadNeverCleansAndRetryDoesNotRegenerateTitle() async throws {
    let store = MemoryDiaryEditStore()
    store.publication = .verified(DiaryEditFixture.version)
    store.uploadedMarkdown = true
    let model = EditTitleModel()
    let editor = await coordinator(store, model: model)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body("Submitted."))
    #expect(await editor.submit(intent, session: session) == .accepted(intent.id))
    await settle(editor)
    #expect(store.records[intent.id]?.issue == .upload)
    #expect(store.cleanupCount == 0)
    #expect(model.calls == 1)
    store.uploadedAudio = true
    editor.prerequisiteChanged()
    await settle(editor)
    #expect(store.cleanupCount == 1)
    #expect(store.records.isEmpty)
    #expect(model.calls == 1)
  }

  @Test func cleanupFailureRestartsWithoutAnotherPublication() async throws {
    let store = MemoryDiaryEditStore()
    store.publication = .verified(DiaryEditFixture.version)
    store.uploadedMarkdown = true
    store.uploadedAudio = true
    store.failCleanup = true
    let editor = await coordinator(store)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(true))
    _ = await editor.submit(intent, session: session)
    await settle(editor)
    #expect(store.records[intent.id]?.stage == .completed)
    #expect(store.publishCount == 1)
    store.failCleanup = false
    let restarted = await coordinator(store)
    await settle(restarted)
    #expect(store.publishCount == 1)
    #expect(store.records.isEmpty)
  }

  @Test func failedAcceptanceAndOversizeBodyNeverStartTitleOrPublication() async throws {
    let store = MemoryDiaryEditStore()
    store.failAcceptance = true
    let model = EditTitleModel()
    let editor = await coordinator(store, model: model)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body("Submitted."))
    #expect(await editor.submit(intent, session: session) == .rejected(.storage))
    let oversized = DiaryEditSubmission(
      id: UUID(), sessionID: session.id, change: .body(String(repeating: "x", count: 1_048_577)))
    #expect(await editor.submit(oversized, session: session) == .rejected(.invalidCandidate))
    #expect(model.calls == 0)
    #expect(store.records.isEmpty)
    #expect(store.publishCount == 0)
  }

  @Test func lostAcceptanceReplyReconcilesTheDurableRecordBeforeRetry() async throws {
    let store = MemoryDiaryEditStore()
    store.failAfterAcceptance = true
    let editor = await coordinator(store)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(true))
    #expect(await editor.submit(intent, session: session) == .accepted(intent.id))
    await settle(editor)
    #expect(editor.pending.map(\.id) == [intent.id])
    #expect(store.acceptCount == 1)
    #expect(await editor.submit(intent, session: session) == .accepted(intent.id))
    #expect(store.acceptCount == 1)
  }

  @Test func failedPublicationCheckpointRediscoveriesDoNotTreatMemoryAsAuthority() async throws {
    let store = MemoryDiaryEditStore()
    store.publication = .verified(DiaryEditFixture.version)
    store.uploadedMarkdown = true
    store.uploadedAudio = true
    store.failCheckpoint = true
    let model = EditTitleModel()
    let editor = await coordinator(store, model: model)
    let session = try DiaryEditFixture.session()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body("Submitted."))
    _ = await editor.submit(intent, session: session)
    await settle(editor)
    #expect(store.records[intent.id]?.stage == .ready)
    #expect(store.cleanupCount == 0)
    store.failCheckpoint = false
    editor.prerequisiteChanged()
    await settle(editor)
    #expect(store.records.isEmpty)
    #expect(store.cleanupCount == 1)
    #expect(model.calls == 1)
  }
}
