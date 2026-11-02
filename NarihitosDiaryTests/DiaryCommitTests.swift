import Foundation
import Testing

// swiftlint:disable file_length

@testable import NarihitosDiary

@MainActor
private final class CommitDraftStore: DiaryDraftStore {
  let value: VerifiedDiaryDraft
  init(_ value: VerifiedDiaryDraft) { self.value = value }
  func publish(_: DiarySnippetV1, candidate _: TranscriptionPayload, job _: QueueJob) throws {}
  func inspect(job _: QueueJob) throws -> DiaryDraftInspection { .verified }
  func readVerified(job _: QueueJob) throws -> VerifiedDiaryDraft { value }
}

@MainActor
private final class CommitPairStore: DiaryPairStorePort {
  var result: DiaryPairResult = .waiting(.destination)
  var observation = DiaryPairUploadObservation(markdown: nil, audio: nil)
  var finalCheck: DiaryFinalPairCheck = .unchanged
  var publications = 0
  var uploadChecks = 0
  var afterPublish: (() -> Void)?

  func ensureAudio(_: DiaryCommitRecord, job _: QueueJob) async -> DiaryFileResult {
    switch result {
    case .verified(let pair):
      .verified(
        DiaryFileVersion(
          identity: pair.audioIdentity, digest: pair.audioDigest, byteCount: 512))
    case .waiting(let reason): .waiting(reason)
    case .recoveryRequired: .recoveryRequired
    }
  }

  func ensureMarkdown(_: DiaryCommitRecord, job _: QueueJob) async -> DiaryFileResult {
    switch result {
    case .verified(let pair):
      .verified(
        DiaryFileVersion(
          identity: pair.markdownIdentity, digest: pair.markdownDigest, byteCount: 512))
    case .waiting(let reason): .waiting(reason)
    case .recoveryRequired: .recoveryRequired
    }
  }

  func verifyPair(_: DiaryCommitRecord, job _: QueueJob) async -> DiaryPairResult {
    publications += 1
    afterPublish?()
    return result
  }

  func observeUploads(
    _: DiaryPairVersion, intent _: DiaryCommitRecord
  ) async -> DiaryPairUploadObservation {
    uploadChecks += 1
    return observation
  }

  func verifyUnchanged(
    _: DiaryPairVersion, intent _: DiaryCommitRecord
  ) async -> DiaryFinalPairCheck {
    finalCheck
  }
}

@MainActor
private final class CommitCleanup: DiaryCommitCleanupPort {
  var calls = 0
  var fail = false
  func removeOwnedStaging(job _: QueueJob) throws {
    calls += 1
    if fail { throw QueueStoreFailure.unavailable }
  }
}

@MainActor
private final class CommitConflictInspector: DiaryConflictInspectionPort {
  var result: DiaryConflictCandidateStatus = .none
  var calls = 0
  var allowChoice = true
  func inspectCaptureConflicts(
    reference _: UUID, id _: AssetID, createdAt _: SchemaInstant
  ) async -> DiaryConflictCandidateStatus {
    calls += 1
    return result
  }
  func validateChoice(
    _: DiaryConflictResolutionClaim, snapshotID _: String, job _: QueueJob
  ) async -> Bool { allowChoice }
}

@MainActor
private final class CommitConflictPairs: DiaryConflictPairStorePort {
  var upload = true
  var cleanupCalls = 0
  var cleanupResult: DiaryConflictCleanupResult = .done

  func ensureAudio(
    _ claim: DiaryConflictResolutionClaim, job _: QueueJob
  ) async -> DiaryFileResult {
    guard let selected = claim.selectedVersion else { return .recoveryRequired }
    return .verified(
      DiaryFileVersion(
        identity: "published-audio", digest: selected.audioDigest, byteCount: 512))
  }

  func ensureMarkdown(
    _ claim: DiaryConflictResolutionClaim, job _: QueueJob
  ) async -> DiaryFileResult {
    guard let selected = claim.selectedVersion else { return .recoveryRequired }
    return .verified(
      DiaryFileVersion(
        identity: "published-markdown", digest: selected.markdownDigest, byteCount: 512))
  }

  func verifyPair(
    _ claim: DiaryConflictResolutionClaim, job _: QueueJob
  ) async -> DiaryPairResult {
    guard let selected = claim.selectedVersion else { return .recoveryRequired }
    return .verified(
      DiaryPairVersion(
        markdownIdentity: "published-markdown", audioIdentity: "published-audio",
        markdownDigest: selected.markdownDigest,
        audioDigest: selected.audioDigest))
  }

  func observeUploads(
    _ version: DiaryPairVersion, claim _: DiaryConflictResolutionClaim,
    job _: QueueJob
  ) async -> DiaryPairUploadObservation {
    DiaryPairUploadObservation(
      markdown: upload
        ? DiaryFileUploadProof(
          identity: version.markdownIdentity, digest: version.markdownDigest) : nil,
      audio: upload
        ? DiaryFileUploadProof(
          identity: version.audioIdentity, digest: version.audioDigest) : nil)
  }

  func verifyUnchanged(
    _: DiaryPairVersion, claim _: DiaryConflictResolutionClaim,
    job _: QueueJob
  ) async -> DiaryFinalPairCheck { .unchanged }

  func removeObsolete(
    _: DiaryConflictResolutionClaim, job _: QueueJob
  ) async -> DiaryConflictCleanupResult {
    cleanupCalls += 1
    return cleanupResult
  }
}

@MainActor
private struct CommitFixture {
  let job: QueueJob
  let queue: MemoryQueueStore
  let pairs: CommitPairStore
  let cleanup: CommitCleanup
  let coordinator: DiaryCommitCoordinator
  let version: DiaryPairVersion
  let draft: VerifiedDiaryDraft
}

@MainActor
// swiftlint:disable:next type_body_length
struct DiaryCommitTests {
  @Test func oldQueueRecordHasNoCommitClaim() throws {
    let fixture = try makeFixture()
    let data = try JSONEncoder().encode(fixture.job)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "commit")
    let oldData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(QueueJob.self, from: oldData)
    #expect(decoded.commit == nil)
    #expect(decoded.state == .readyToSave)
  }

  @Test func olderCommitIntentWithoutCreationMarkersRemainsReadable() async throws {
    let fixture = try makeFixture()
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    let stored = try #require(fixture.queue.values[fixture.job.id])
    let data = try JSONEncoder().encode(stored)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var commit = try #require(object["commit"] as? [String: Any])
    commit.removeValue(forKey: "audioCreationToken")
    commit.removeValue(forKey: "markdownCreationToken")
    object["commit"] = commit
    let oldData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(QueueJob.self, from: oldData)
    #expect(decoded.commit?.audioCreationToken == nil)
    #expect(decoded.commit?.markdownCreationToken == nil)
    #expect(decoded.state == .readyToSave)
  }

  @Test func missingUploadProofRetainsIntentAndSource() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    let waiting = try #require(fixture.queue.values[fixture.job.id])
    #expect(waiting.state == .readyToSave)
    #expect(waiting.reason == DiaryCommitWait.upload.message)
    #expect(waiting.commit != nil)
    #expect(fixture.cleanup.calls == 0)
    fixture.pairs.observation = completeObservation(fixture.version)
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .saved)
    #expect(fixture.queue.values[fixture.job.id]?.commitCleanupDone == true)
    #expect(fixture.pairs.publications == 2)
    #expect(fixture.cleanup.calls == 1)
  }

  // swiftlint:disable:next function_body_length
  @Test func providerConflictRetainsTypedPairSnapshotsForReview() async throws {
    let fixture = try makeFixture()
    let inspector = CommitConflictInspector()
    let times = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 10),
      audio: Date(timeIntervalSince1970: 11))
    let first = DiaryConflictSnapshot(
      id: try WorkspaceID.random(), assetID: fixture.draft.snippet.id.description,
      snippet: fixture.draft.snippet, version: fixture.version, modifiedAt: times)
    let second = DiaryConflictSnapshot(
      id: try WorkspaceID.random(), assetID: fixture.draft.snippet.id.description,
      snippet: fixture.draft.snippet,
      version: DiaryPairVersion(
        markdownIdentity: "other-markdown", audioIdentity: "other-audio",
        markdownDigest: fixture.version.markdownDigest,
        audioDigest: fixture.version.audioDigest),
      modifiedAt: times)
    inspector.result = .candidates(
      DiaryConflictCandidates(
        first: first, second: second,
        currentMarkdown: DiaryFileVersion(
          identity: fixture.version.markdownIdentity,
          digest: fixture.version.markdownDigest, byteCount: 512),
        currentAudio: DiaryFileVersion(
          identity: fixture.version.audioIdentity,
          digest: fixture.version.audioDigest, byteCount: 512),
        currentProviderKeys: nil,
        selection: .userChoice))
    fixture.pairs.result = .recoveryRequired
    let coordinator = DiaryCommitCoordinator(
      queue: fixture.queue, drafts: CommitDraftStore(fixture.draft),
      pairs: fixture.pairs, cleanup: fixture.cleanup, conflicts: inspector)
    await coordinator.attempt(jobID: fixture.job.id)
    #expect(inspector.calls == 1)
    #expect(fixture.queue.values[fixture.job.id]?.conflictResolution?.selectedSnapshotID == nil)
    #expect(
      fixture.queue.values[fixture.job.id]?.conflictResolution?.firstSnapshotID
        == first.id.description)
    #expect(
      fixture.queue.values[fixture.job.id]?.reason
        == "Conflicting diary versions are preserved for review.")
    inspector.allowChoice = false
    #expect(
      await coordinator.chooseConflict(
        jobID: fixture.job.id, snapshotID: first.id.description) == false)
    inspector.allowChoice = true
    #expect(
      await coordinator.chooseConflict(
        jobID: fixture.job.id, snapshotID: first.id.description))
    #expect(
      fixture.queue.values[fixture.job.id]?.conflictResolution?.selectedSnapshotID
        == first.id.description)
    #expect(
      await coordinator.chooseConflict(
        jobID: fixture.job.id, snapshotID: second.id.description) == false)
    let pairs = CommitConflictPairs()
    pairs.upload = false
    let publishing = DiaryCommitCoordinator(
      queue: fixture.queue, drafts: CommitDraftStore(fixture.draft),
      pairs: fixture.pairs, cleanup: fixture.cleanup,
      conflicts: inspector, conflictPairs: pairs)
    await publishing.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.queue.values[fixture.job.id]?.conflictResolution?.pairVerified != true)
    pairs.upload = true
    await publishing.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.conflictResolution?.pairVerified == true)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.cleanup.calls == 0)
    #expect(
      fixture.queue.values[fixture.job.id]?.reason
        == "Waiting for confirmation to remove the other version.")
    #expect(publishing.confirmConflictRemoval(jobID: fixture.job.id))
    await publishing.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .saved)
    #expect(fixture.cleanup.calls == 1)
  }

  @Test func changedJobFencesPublicationCallback() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    fixture.pairs.observation = completeObservation(fixture.version)
    fixture.pairs.afterPublish = {
      guard var job = fixture.queue.values[fixture.job.id] else { return }
      job.destinationRevision += 1
      job.state = .removing
      fixture.queue.values[job.id] = job
    }
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .removing)
    #expect(fixture.pairs.uploadChecks == 0)
    #expect(fixture.cleanup.calls == 0)
  }

  // swiftlint:disable:next function_body_length
  @Test func laterWholeConflictCompletesAndCleansAutomaticallyAfterProof() async throws {
    let fixture = try makeFixture()
    let inspector = CommitConflictInspector()
    let first = DiaryConflictSnapshot(
      id: try WorkspaceID.random(), assetID: fixture.draft.snippet.id.description,
      snippet: fixture.draft.snippet, version: fixture.version,
      modifiedAt: DiaryPairModificationTimes(
        markdown: Date(timeIntervalSince1970: 10),
        audio: Date(timeIntervalSince1970: 11)))
    let second = DiaryConflictSnapshot(
      id: try WorkspaceID.random(), assetID: fixture.draft.snippet.id.description,
      snippet: fixture.draft.snippet,
      version: DiaryPairVersion(
        markdownIdentity: "later-markdown", audioIdentity: "later-audio",
        markdownDigest: fixture.version.markdownDigest,
        audioDigest: fixture.version.audioDigest),
      modifiedAt: DiaryPairModificationTimes(
        markdown: Date(timeIntervalSince1970: 20),
        audio: Date(timeIntervalSince1970: 21)))
    inspector.result = .candidates(
      DiaryConflictCandidates(
        first: first, second: second,
        currentMarkdown: DiaryFileVersion(
          identity: fixture.version.markdownIdentity,
          digest: fixture.version.markdownDigest, byteCount: 512),
        currentAudio: DiaryFileVersion(
          identity: fixture.version.audioIdentity,
          digest: fixture.version.audioDigest, byteCount: 512),
        currentProviderKeys: nil, selection: .second))
    fixture.pairs.result = .recoveryRequired
    let conflictPairs = CommitConflictPairs()
    let coordinator = DiaryCommitCoordinator(
      queue: fixture.queue, drafts: CommitDraftStore(fixture.draft),
      pairs: fixture.pairs, cleanup: fixture.cleanup,
      conflicts: inspector, conflictPairs: conflictPairs)
    await coordinator.attempt(jobID: fixture.job.id)
    let discovered = try #require(fixture.queue.values[fixture.job.id])
    #expect(discovered.conflictResolution?.selectedSnapshotID == second.id.description)
    #expect(discovered.conflictResolution?.removalConfirmed == true)
    #expect(fixture.cleanup.calls == 0)
    conflictPairs.cleanupResult = .waiting
    await coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.queue.values[fixture.job.id]?.conflictResolution?.pairVerified == true)
    #expect(fixture.cleanup.calls == 0)
    conflictPairs.cleanupResult = .done
    fixture.queue.failReplaceState = .saved
    await coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.cleanup.calls == 0)
    fixture.queue.failReplaceState = nil
    await coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .saved)
    #expect(fixture.queue.values[fixture.job.id]?.conflictResolution?.providerCleanupDone == true)
    #expect(fixture.cleanup.calls == 1)
    #expect(conflictPairs.cleanupCalls == 3)
  }

  @Test func changedPairAfterUploadDoesNotComplete() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    fixture.pairs.observation = completeObservation(fixture.version)
    fixture.pairs.finalCheck = .changed
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.cleanup.calls == 0)
    #expect(fixture.queue.values[fixture.job.id]?.reason == "This diary pair needs review.")
  }

  @Test func interruptedCleanupResumesWithoutRepublishing() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    fixture.pairs.observation = completeObservation(fixture.version)
    fixture.cleanup.fail = true
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .saved)
    #expect(fixture.queue.values[fixture.job.id]?.commitCleanupDone != true)
    let publications = fixture.pairs.publications
    fixture.cleanup.fail = false
    fixture.coordinator.resumeCleanup()
    #expect(fixture.queue.values[fixture.job.id]?.commitCleanupDone == true)
    #expect(fixture.pairs.publications == publications)
  }

  @Test func savedNoticeIsDeliveredOnceBeforeCleanup() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    fixture.pairs.observation = completeObservation(fixture.version)
    var notices = 0
    fixture.coordinator.onSaved = { job in
      #expect(job.state == .saved)
      #expect(job.commitCleanupDone != true)
      notices += 1
    }
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    fixture.coordinator.resumeCleanup()
    #expect(notices == 1)
    #expect(fixture.queue.values[fixture.job.id]?.commitNoticeDelivered == true)
  }

  @Test func failedCompletionPersistenceRetainsStagingAndRechecksPair() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    fixture.pairs.observation = completeObservation(fixture.version)
    fixture.queue.failReplaceState = .saved
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.cleanup.calls == 0)
    #expect(fixture.pairs.publications == 1)

    fixture.queue.failReplaceState = nil
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.pairs.publications == 2)
    #expect(fixture.queue.values[fixture.job.id]?.state == .saved)
    #expect(fixture.cleanup.calls == 1)
  }

  @Test func oneFileOrStaleVersionCannotComplete() async throws {
    let fixture = try makeFixture()
    fixture.pairs.result = .verified(fixture.version)
    fixture.pairs.observation = DiaryPairUploadObservation(
      markdown: completeObservation(fixture.version).markdown, audio: nil)
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    fixture.pairs.observation = DiaryPairUploadObservation(
      markdown: completeObservation(fixture.version).markdown,
      audio: DiaryFileUploadProof(identity: "older-audio", digest: fixture.version.audioDigest))
    await fixture.coordinator.attempt(jobID: fixture.job.id)
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.cleanup.calls == 0)
  }

  private func completeObservation(_ version: DiaryPairVersion) -> DiaryPairUploadObservation {
    DiaryPairUploadObservation(
      markdown: DiaryFileUploadProof(
        identity: version.markdownIdentity, digest: version.markdownDigest),
      audio: DiaryFileUploadProof(
        identity: version.audioIdentity, digest: version.audioDigest))
  }

  private func makeFixture() throws -> CommitFixture {
    let id = try AssetID.random()
    let receipt = QueueReceipt(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 1_762_000_000),
      language: .english, destinationReference: UUID(), installationBinding: "installation",
      inspection: CaptureInspection(
        byteCount: 512, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1, codecIdentifier: nil,
        approximateBitRate: 64_000))
    var job = QueueJob(receipt: receipt, state: .readyToSave)
    job.attemptID = UUID()
    job.draftAssetID = id.description
    let created = try SchemaInstant.from(date: receipt.startedAt)
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    let snippet = DiarySnippetV1(
      id: id, createdAt: created, updatedAt: created, title: "A day",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil,
        osVersion: nil, modelID: nil),
      favorite: false, language: "en-US", audioFilename: layout.audioFilename,
      recordingDurationMilliseconds: 1_000, audioCodec: "aac",
      audioSampleRateHertz: 44_100, audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID(TranscriptionMethodIdentifiers.apple),
        languageHint: "en-US", settingsRevision: 1, modelID: nil, modelVersion: nil,
        runtimeID: "apple-speech-analyzer", conversionID: "test"),
      location: nil, weather: nil, body: try DiaryBody("A day"), preservedScalars: [])
    let draft = VerifiedDiaryDraft(
      snippet: snippet, sourceDigest: String(repeating: "a", count: 64),
      markdownDigest: String(repeating: "b", count: 64), markdownByteCount: 512)
    let queue = MemoryQueueStore()
    queue.values[job.id] = job
    let pairs = CommitPairStore()
    let cleanup = CommitCleanup()
    let coordinator = DiaryCommitCoordinator(
      queue: queue, drafts: CommitDraftStore(draft), pairs: pairs, cleanup: cleanup)
    let version = DiaryPairVersion(
      markdownIdentity: "markdown-v1", audioIdentity: "audio-v1",
      markdownDigest: draft.markdownDigest, audioDigest: draft.sourceDigest)
    return CommitFixture(
      job: job, queue: queue, pairs: pairs, cleanup: cleanup,
      coordinator: coordinator, version: version, draft: draft)
  }
}
