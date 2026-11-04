import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable trailing_comma file_length

@MainActor
private final class MemoryDiaryDraftStore: DiaryDraftStore {
  var snippet: DiarySnippetV1?
  var publicationCount = 0
  var failSource = false
  var inspectionOverride: DiaryDraftInspection?

  // swiftlint:disable opening_brace
  func publish(_ snippet: DiarySnippetV1, candidate _: TranscriptionPayload, job _: QueueJob)
    throws
  {
    if failSource { throw TranscriptionCandidateFailure.invalidSource }
    self.snippet = snippet
    publicationCount += 1
  }
  // swiftlint:enable opening_brace

  func inspect(job _: QueueJob) throws -> DiaryDraftInspection {
    if let inspectionOverride { return inspectionOverride }
    return snippet == nil ? DiaryDraftInspection.missing : .verified
  }

  func readVerified(job _: QueueJob) throws -> VerifiedDiaryDraft {
    guard let snippet else { throw QueueStoreFailure.corrupt }
    return VerifiedDiaryDraft(
      snippet: snippet, sourceDigest: "digest", markdownDigest: "markdown",
      markdownByteCount: 1)
  }
}

@MainActor
private struct DraftAdoptionFixture {
  let job: QueueJob
  let receipt: QueueReceipt
  let queue: MemoryQueueStore
  let candidates: MemoryCandidateStore
  let drafts: MemoryDiaryDraftStore
  let adopter: DiaryDraftAdoptionCoordinator
  let processing: ProcessingQueueCoordinator
}

@MainActor
private final class FixedDraftFingerprint: CaptureAudioFingerprintSource {
  var value: String
  init(value: String) { self.value = value }
  func fingerprint(for _: QueueJob) throws -> String { value }
}

private struct TestDraftProtectionPolicy: DraftFileProtectionPolicy {
  func applyAndVerify(to _: URL) throws {}
  func verify(_: URL) throws {}
}

private final class FaultingDraftWorkspace: PrivateWorkspacePort {
  let base: any PrivateWorkspacePort
  var failWriteRole: PrivateArtifactRole?
  var failReadRole: PrivateArtifactRole?

  init(base: any PrivateWorkspacePort) { self.base = base }

  func allocate(id: WorkspaceID) throws -> WorkspaceHandle { try base.allocate(id: id) }
  func reopen(id: WorkspaceID) throws -> WorkspaceHandle { try base.reopen(id: id) }
  // swiftlint:disable opening_brace
  func artifact(_ role: PrivateArtifactRole, in workspace: WorkspaceHandle) throws
    -> ArtifactHandle
  { try base.artifact(role, in: workspace) }
  // swiftlint:enable opening_brace

  func read(_ artifact: ArtifactHandle) throws -> Data {
    if artifact.role == failReadRole { throw QueueStoreFailure.unavailable }
    return try base.read(artifact)
  }

  func replace(_ artifact: ArtifactHandle, with data: Data) throws {
    if artifact.role == failWriteRole { throw QueueStoreFailure.unavailable }
    try base.replace(artifact, with: data)
  }

  func remove(_ artifact: ArtifactHandle) throws { try base.remove(artifact) }
  func remove(_ workspace: WorkspaceHandle) throws { try base.remove(workspace) }
}

@MainActor
private struct FixedEnglishTitleDetector: DiaryTitleLanguageDetector {
  func assess(_: String) -> TitleLanguageAssessment? {
    TitleLanguageAssessment(language: "en", confidence: 1)
  }
}

@MainActor
private final class SuspendedAdoptionTitleModel: DiaryTitleModelPort {
  let isAvailable = true
  var modelIdentifier: String? { nil }
  var pending: CheckedContinuation<TitleModelReply, Never>?

  // swiftlint:disable opening_brace
  func chunks(for text: String, maximumTokens _: Int, maximumChunks _: Int) async throws
    -> [String]?
  { [text] }

  func summarize(_ text: String, language _: String, maximumOutputTokens _: Int) async throws
    -> TitleModelReply
  { await withCheckedContinuation { pending = $0 } }
  // swiftlint:enable opening_brace
}

@MainActor
private final class UnavailableTitleModel: DiaryTitleModelPort {
  let isAvailable = false
  var modelIdentifier: String? { nil }

  // swiftlint:disable opening_brace
  func chunks(for _: String, maximumTokens _: Int, maximumChunks _: Int) async throws
    -> [String]?
  { nil }

  func summarize(_ text: String, language _: String, maximumOutputTokens _: Int) async throws
    -> TitleModelReply
  { TitleModelReply(text: text, outputTokens: 0) }
  // swiftlint:enable opening_brace
}

extension DiaryDraftAdoptionTests {
  @Test func maintenanceKeepsCancelledTitleBusyUntilSettlementAndThenResumes() async throws {
    let fixture = try makeFixture()
    let model = SuspendedAdoptionTitleModel()
    let adopter = DiaryDraftAdoptionCoordinator(
      queue: fixture.queue, receipts: MemoryReceiptSource([fixture.receipt]),
      candidates: fixture.candidates, drafts: fixture.drafts,
      titles: DiaryTitlePolicy(
        model: model, languageDetector: FixedEnglishTitleDetector()))
    adopter.activate()
    for _ in 0..<100 where model.pending == nil { await Task.yield() }
    let first = try #require(model.pending)
    #expect(adopter.hasActiveWork)
    adopter.suspendForMaintenance()
    adopter.activate()
    adopter.prerequisiteChanged()
    #expect(adopter.hasActiveWork)
    #expect(fixture.drafts.publicationCount == 0)
    model.pending = nil
    first.resume(returning: TitleModelReply(text: "A good day at home", outputTokens: 5))
    for _ in 0..<100 where adopter.hasActiveWork { await Task.yield() }
    #expect(!adopter.hasActiveWork)
    #expect(fixture.queue.values[fixture.job.id]?.state == .resultReady)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    #expect(fixture.drafts.publicationCount == 0)
    adopter.endMaintenance()
    adopter.activate()
    for _ in 0..<100 where model.pending == nil { await Task.yield() }
    let second = try #require(model.pending)
    second.resume(returning: TitleModelReply(text: "A good day at home", outputTokens: 5))
    for _ in 0..<100 where adopter.hasActiveWork { await Task.yield() }
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.drafts.publicationCount == 1)
  }

  @Test func timedOutTitleRemainsBusyUntilNoncooperativeModelRelinquishesWork() async throws {
    let fixture = try makeFixture()
    let model = SuspendedAdoptionTitleModel()
    let titles = DiaryTitlePolicy(
      model: model, languageDetector: FixedEnglishTitleDetector(), timeout: .milliseconds(100))
    let adopter = DiaryDraftAdoptionCoordinator(
      queue: fixture.queue, receipts: MemoryReceiptSource([fixture.receipt]),
      candidates: fixture.candidates, drafts: fixture.drafts,
      titles: titles)
    adopter.activate()
    for _ in 0..<100 where model.pending == nil { await Task.yield() }
    let pending = try #require(model.pending)
    for _ in 0..<100 where fixture.queue.values[fixture.job.id]?.state != .readyToSave {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.drafts.publicationCount == 1)
    #expect(adopter.hasActiveWork)
    #expect(
      titles.workSnapshot?.owner
        == .recording(
          jobID: fixture.job.id, attemptID: fixture.job.attemptID,
          attemptGeneration: fixture.job.attemptGeneration,
          destinationRevision: fixture.job.destinationRevision,
          bodyRevision: fixture.job.bodyRevision))
    #expect(titles.workSnapshot?.phase == .settling)
    adopter.suspendForMaintenance()
    #expect(adopter.hasActiveWork)
    pending.resume(returning: TitleModelReply(text: "A good day at home", outputTokens: 5))
    for _ in 0..<100 where adopter.hasActiveWork { await Task.yield() }
    #expect(!adopter.hasActiveWork)
    #expect(titles.workSnapshot == nil)
    #expect(fixture.drafts.publicationCount == 1)
  }

}

@MainActor
struct DiaryDraftAdoptionTests {
  @Test func oldQueueRecordDecodesWithoutDraftIdentity() throws {
    let fixture = try makeFixture()
    let data = try JSONEncoder().encode(fixture.job)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "draftAssetID")
    let oldData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(QueueJob.self, from: oldData)
    #expect(decoded.draftAssetID == nil)
    #expect(decoded.id == fixture.job.id)
    #expect(decoded.state == .resultReady)
  }

  @Test func candidateBecomesOneDraftWithRecordingHintAndAudioEvidence() async throws {
    let fixture = try makeFixture()
    fixture.adopter.activate()
    for _ in 0..<50 where fixture.queue.values[fixture.job.id]?.state != .readyToSave {
      await Task.yield()
    }
    let saved = try #require(fixture.queue.values[fixture.job.id])
    let snippet = try #require(fixture.drafts.snippet)
    #expect(saved.state == .readyToSave)
    #expect(saved.draftAssetID == snippet.id.description)
    #expect(snippet.body.text == "I wrote a diary entry. Another sentence.")
    #expect(snippet.language == "en-US")
    #expect(snippet.transcription.languageHint == "en-US")
    #expect(snippet.audioSampleRateHertz == 44_100)
    #expect(snippet.audioBitrateBPS == 64_000)
    #expect(snippet.favorite == false)
    #expect(fixture.drafts.publicationCount == 1)
    #expect(fixture.candidates.published[fixture.job.id] == nil)
  }

  @Test func queueStoreFailureLeavesCandidateForRecovery() async throws {
    let fixture = try makeFixture()
    fixture.queue.failReplace = true
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.adopter.pausedReason == nil { await Task.yield() }
    #expect(fixture.adopter.pausedReason == ProcessingQueueCoordinator.pausedReason)
    #expect(fixture.queue.values[fixture.job.id]?.state == .resultReady)
    #expect(fixture.drafts.snippet == nil)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
  }

  @Test func assetIDAllocationFailureLeavesCandidateForRecovery() async throws {
    let fixture = try makeFixture()
    let adopter = DiaryDraftAdoptionCoordinator(
      queue: fixture.queue, receipts: MemoryReceiptSource([fixture.receipt]),
      candidates: fixture.candidates, drafts: fixture.drafts,
      titles: DiaryTitlePolicy(
        model: UnavailableTitleModel(), languageDetector: FixedEnglishTitleDetector()),
      makeAssetID: { throw QueueStoreFailure.unavailable })
    adopter.activate()
    for _ in 0..<100 where adopter.pausedReason == nil { await Task.yield() }
    #expect(adopter.pausedReason == ProcessingQueueCoordinator.pausedReason)
    #expect(fixture.queue.values[fixture.job.id]?.draftAssetID == nil)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    #expect(fixture.drafts.publicationCount == 0)
  }

  @Test func candidateReadFailureDefersWithoutLosingAudioOrText() async throws {
    let fixture = try makeFixture()
    fixture.candidates.failRead = true
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.adopter.pausedReason == nil { await Task.yield() }
    #expect(fixture.queue.values[fixture.job.id]?.state == .resultReady)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    #expect(fixture.drafts.publicationCount == 0)
    fixture.candidates.failRead = false
    fixture.adopter.prerequisiteChanged()
    for _ in 0..<100 where fixture.queue.values[fixture.job.id]?.state != .readyToSave {
      await Task.yield()
    }
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.drafts.publicationCount == 1)
  }

  @Test func lockedDraftStorageDefersCandidateAdoption() async throws {
    let fixture = try makeFixture()
    fixture.drafts.inspectionOverride = .protectedDataUnavailable
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.adopter.pausedReason == nil { await Task.yield() }
    let reason = fixture.adopter.pausedReason
    #expect(reason == TranscriptionWaitReason.protectedDataUnavailable.message)
    #expect(fixture.queue.values[fixture.job.id]?.state == .resultReady)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    #expect(fixture.drafts.publicationCount == 0)
    fixture.drafts.inspectionOverride = nil
    fixture.adopter.prerequisiteChanged()
    for _ in 0..<100 where fixture.queue.values[fixture.job.id]?.state != .readyToSave {
      await Task.yield()
    }
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
  }

  @Test func changedSourceFailsWithAudioReasonAndRetainsCandidate() async throws {
    let fixture = try makeFixture()
    fixture.drafts.failSource = true
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.queue.values[fixture.job.id]?.state != .failed {
      await Task.yield()
    }
    #expect(fixture.queue.values[fixture.job.id]?.state == .failed)
    let reason = fixture.queue.values[fixture.job.id]?.reason
    #expect(reason == TranscriptionFailure.audioUnreadable.message)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    #expect(fixture.drafts.publicationCount == 0)
  }

  @Test func failedQueueTransitionReconcilesVerifiedDraft() async throws {
    let fixture = try makeFixture()
    fixture.queue.failReplaceState = .readyToSave
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.adopter.pausedReason == nil { await Task.yield() }
    #expect(fixture.queue.values[fixture.job.id]?.state == .resultReady)
    #expect(fixture.drafts.publicationCount == 1)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    fixture.queue.failReplaceState = nil
    fixture.processing.reconcile()
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    fixture.adopter.prerequisiteChanged()
    #expect(fixture.candidates.published[fixture.job.id] == nil)
    #expect(fixture.drafts.publicationCount == 1)
  }

  @Test func discardFailureKeepsDraftAndRetriesExactCandidate() async throws {
    let fixture = try makeFixture()
    fixture.candidates.failDiscard = true
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.adopter.pausedReason == nil { await Task.yield() }
    #expect(fixture.queue.values[fixture.job.id]?.state == .readyToSave)
    #expect(fixture.drafts.publicationCount == 1)
    #expect(fixture.candidates.published[fixture.job.id] != nil)
    fixture.candidates.failDiscard = false
    fixture.adopter.prerequisiteChanged()
    #expect(fixture.candidates.published[fixture.job.id] == nil)
    #expect(fixture.drafts.publicationCount == 1)
  }

  @Test func cleanupPreservesCandidateUntilDraftIsVerified() async throws {
    let fixture = try makeFixture()
    var job = fixture.job
    job.draftAssetID = try AssetID.random().description
    let snippet = try sampleSnippet(job: job, receipt: fixture.receipt)
    job.state = .readyToSave
    fixture.queue.values[job.id] = job

    fixture.adopter.activate()
    #expect(fixture.candidates.published[job.id] != nil)

    fixture.drafts.snippet = snippet
    fixture.drafts.inspectionOverride = .invalid
    fixture.adopter.prerequisiteChanged()
    #expect(fixture.candidates.published[job.id] != nil)

    fixture.drafts.inspectionOverride = .protectedDataUnavailable
    fixture.adopter.prerequisiteChanged()
    #expect(fixture.candidates.published[job.id] != nil)

    fixture.drafts.inspectionOverride = nil
    fixture.drafts.snippet = nil
    fixture.processing.reconcile()
    #expect(fixture.queue.values[job.id]?.state == .resultReady)
    fixture.adopter.prerequisiteChanged()
    for _ in 0..<100 where fixture.queue.values[job.id]?.state != .readyToSave {
      await Task.yield()
    }
    #expect(fixture.queue.values[job.id]?.state == .readyToSave)
    #expect(fixture.drafts.snippet?.id == snippet.id)
    #expect(fixture.candidates.published[job.id] == nil)
  }

  @Test func removalTombstoneFencesLateTitleResult() async throws {
    let fixture = try makeFixture()
    let model = SuspendedAdoptionTitleModel()
    let adopter = DiaryDraftAdoptionCoordinator(
      queue: fixture.queue, receipts: MemoryReceiptSource([fixture.receipt]),
      candidates: fixture.candidates, drafts: fixture.drafts,
      titles: DiaryTitlePolicy(
        model: model, languageDetector: FixedEnglishTitleDetector()))
    adopter.activate()
    for _ in 0..<100 where model.pending == nil { await Task.yield() }
    let pending = try #require(model.pending)
    var removed = try #require(fixture.queue.values[fixture.job.id])
    removed.attemptGeneration += 1
    removed.state = .removing
    fixture.queue.values[fixture.job.id] = removed
    pending.resume(returning: TitleModelReply(text: "A good day at home", outputTokens: 5))
    for _ in 0..<100 { await Task.yield() }
    #expect(fixture.drafts.publicationCount == 0)
    #expect(fixture.queue.values[fixture.job.id]?.state == .removing)
  }

  @Test func verifiedDraftCanAdvanceAfterCandidateWasDiscarded() throws {
    let fixture = try makeFixture()
    var job = fixture.job
    job.draftAssetID = try AssetID.random().description
    fixture.queue.values[job.id] = job
    fixture.drafts.snippet = try sampleSnippet(job: job, receipt: fixture.receipt)
    fixture.candidates.published.removeAll()
    fixture.processing.reconcile()
    #expect(fixture.queue.values[job.id]?.state == .readyToSave)
    #expect(fixture.drafts.publicationCount == 0)
  }

  @Test func restoredInstallationCannotAdoptAnExistingDraft() throws {
    let fixture = try makeFixture()
    var job = fixture.job
    job.draftAssetID = try AssetID.random().description
    job.installationBinding = "older-installation"
    fixture.queue.values[job.id] = job
    fixture.drafts.snippet = try sampleSnippet(job: job, receipt: fixture.receipt)
    fixture.processing.reconcile()
    #expect(fixture.queue.values[job.id]?.state == .reviewRequired)
    #expect(fixture.drafts.publicationCount == 0)
  }

  @Test func cohereDraftKeepsRecordingHintWhenBodyIsKorean() throws {
    let fixture = try makeFixture()
    var job = cohereJob(from: fixture.job)
    let descriptor = CohereTrustedModel.production
    job.draftAssetID = try AssetID.random().description
    let rawID = try #require(job.draftAssetID)
    let korean = "오늘은 집에서 하루를 보내고 일기를 썼다."
    let candidate = TranscriptionPayload(
      text: korean, sourceDigest: "digest", resolvedLocale: "en-US",
      runtime: CohereRuntimeProvenance.identity,
      conversion: CohereAudioConversion.identity, operatingSystemVersion: "27.0")
    let snippet = try DiaryDraftFactory().make(
      job: job, receipt: fixture.receipt, candidate: candidate,
      assetID: AssetID(rawID), updatedAt: Date(),
      title: DiaryTitlePolicy.fallback(korean))
    #expect(snippet.body.text == korean)
    #expect(snippet.language == "en-US")
    #expect(snippet.transcription.languageHint == "en-US")
    #expect(snippet.transcription.modelID == descriptor.modelID)
    #expect(snippet.transcription.modelVersion == descriptor.repositoryRevision)
  }

  @Test func cohereCandidateUsesTheSameDraftAdoptionPath() async throws {
    let fixture = try makeFixture()
    let job = cohereJob(from: fixture.job)
    fixture.queue.values[job.id] = job
    fixture.candidates.published[job.id] = TranscriptionPayload(
      text: "오늘은 집에서 하루를 보내고 일기를 썼다.", sourceDigest: "digest",
      resolvedLocale: "en-US", runtime: CohereRuntimeProvenance.identity,
      conversion: CohereAudioConversion.identity, operatingSystemVersion: "27.0")
    fixture.adopter.activate()
    for _ in 0..<100 where fixture.queue.values[job.id]?.state != .readyToSave {
      await Task.yield()
    }
    let snippet = try #require(fixture.drafts.snippet)
    #expect(fixture.queue.values[job.id]?.state == .readyToSave)
    #expect(snippet.body.text == "오늘은 집에서 하루를 보내고 일기를 썼다.")
    #expect(snippet.language == "en-US")
    #expect(snippet.transcription.languageHint == "en-US")
    #expect(snippet.transcription.methodID.description == TranscriptionMethodIdentifiers.cohere)
    #expect(fixture.candidates.published[job.id] == nil)
  }

}

extension DiaryDraftAdoptionTests {
  // swiftlint:disable:next function_body_length
  @Test func privateDraftRequiresMatchingBindingAndBackupExclusion() throws {
    let fixture = try makeFixture()
    var job = fixture.job
    job.draftAssetID = try AssetID.random().description
    let snippet = try sampleSnippet(job: job, receipt: fixture.receipt)
    let digest = String(repeating: "a", count: 64)
    let candidate = TranscriptionPayload(
      text: snippet.body.text, sourceDigest: digest, resolvedLocale: "en-US",
      runtime: "apple-speech-analyzer",
      conversion: "ndm.apple-speech.av-audio-file-v1", operatingSystemVersion: "27.0")
    let root = FileManager.default.temporaryDirectory.appending(
      path: "diary-draft-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = try LocalPrivateWorkspace(
      root: root, protectionPolicy: TestDraftProtectionPolicy())
    _ = try workspace.allocate(id: WorkspaceID(job.id))
    let source = FixedDraftFingerprint(value: digest)
    let store = try FileDiaryDraftStore(
      root: root, audio: source,
      protection: TestDraftProtectionPolicy(),
      protectedDataAvailable: { true })
    try store.publish(snippet, candidate: candidate, job: job)
    #expect(try store.inspect(job: job) == .verified)
    var boundSnippet = snippet
    boundSnippet.audioSHA256 = digest
    #expect(try store.readVerified(job: job).snippet == boundSnippet)
    source.value = String(repeating: "c", count: 64)
    #expect(try store.inspect(job: job) == .invalid)
    #expect(throws: TranscriptionCandidateFailure.invalidSource) {
      try store.publish(snippet, candidate: candidate, job: job)
    }
    source.value = digest
    var retargeted = job
    retargeted.destinationRevision += 1
    #expect(try store.inspect(job: retargeted) == .invalid)
    var edited = job
    edited.bodyRevision += 1
    #expect(try store.inspect(job: edited) == .invalid)
    var retried = job
    retried.attemptGeneration += 1
    #expect(try store.inspect(job: retried) == .invalid)
    let folder = root.appending(path: job.id, directoryHint: .isDirectory)
    let markdown = folder.appending(path: PrivateArtifactRole.markdownDraft.ownedFilename)
    let binding = folder.appending(path: PrivateArtifactRole.draftBinding.ownedFilename)
    for url in [markdown, binding] {
      let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      #expect(values.isExcludedFromBackup == true)
    }
    let bytes = try Data(contentsOf: markdown)
    let bodyOffset = try #require(bytes.range(of: Data(snippet.body.text.utf8))?.lowerBound)
    let writer = try FileHandle(forWritingTo: markdown)
    try writer.seek(toOffset: UInt64(bodyOffset))
    try writer.write(contentsOf: Data("X".utf8))
    try writer.close()
    #expect(try store.inspect(job: job) == .invalid)
    let restore = try FileHandle(forWritingTo: markdown)
    try restore.seek(toOffset: UInt64(bodyOffset))
    try restore.write(contentsOf: Data("I".utf8))
    try restore.close()
    #expect(try store.inspect(job: job) == .verified)
    let bindingWriter = try FileHandle(forWritingTo: binding)
    try bindingWriter.seek(toOffset: 0)
    try bindingWriter.write(contentsOf: Data("[".utf8))
    try bindingWriter.close()
    #expect(try store.inspect(job: job) == .invalid)
  }

  @Test func draftAndBindingWriteFaultsRecoverWithSameAssetID() throws {
    for failedRole in [PrivateArtifactRole.markdownDraft, .draftBinding] {
      let fixture = try makeFixture()
      var job = fixture.job
      job.draftAssetID = try AssetID.random().description
      let snippet = try sampleSnippet(job: job, receipt: fixture.receipt)
      let digest = String(repeating: "b", count: 64)
      let candidate = TranscriptionPayload(
        text: snippet.body.text, sourceDigest: digest, resolvedLocale: "en-US",
        runtime: "apple-speech-analyzer",
        conversion: "ndm.apple-speech.av-audio-file-v1", operatingSystemVersion: "27.0")
      let root = FileManager.default.temporaryDirectory.appending(
        path: "diary-draft-fault-\(UUID().uuidString)", directoryHint: .isDirectory)
      defer { try? FileManager.default.removeItem(at: root) }
      let base = try LocalPrivateWorkspace(
        root: root, protectionPolicy: TestDraftProtectionPolicy())
      _ = try base.allocate(id: WorkspaceID(job.id))
      let faulting = FaultingDraftWorkspace(base: base)
      let store = try FileDiaryDraftStore(
        root: root, audio: FixedDraftFingerprint(value: digest),
        protection: TestDraftProtectionPolicy(), workspaceOverride: faulting,
        protectedDataAvailable: { true })
      faulting.failWriteRole = failedRole
      #expect(throws: QueueStoreFailure.unavailable) {
        try store.publish(snippet, candidate: candidate, job: job)
      }
      #expect(try store.inspect(job: job) == .missing)
      faulting.failWriteRole = nil
      faulting.failReadRole = .draftBinding
      #expect(throws: QueueStoreFailure.unavailable) {
        try store.publish(snippet, candidate: candidate, job: job)
      }
      #expect(throws: QueueStoreFailure.unavailable) {
        try store.inspect(job: job)
      }
      faulting.failReadRole = nil
      #expect(try store.inspect(job: job) == .verified)
      #expect(try store.readVerified(job: job).snippet.id.description == job.draftAssetID)
    }
  }

}

extension DiaryDraftAdoptionTests {
  fileprivate func cohereJob(from initial: QueueJob) -> QueueJob {
    var job = initial
    let descriptor = CohereTrustedModel.production
    job.selectedMethodID = TranscriptionMethodIdentifiers.cohere
    job.modelIdentity = descriptor.installationIdentity
    job.conversionIdentity = CohereAudioConversion.identity
    job.effectiveSettings = [
      "settingsRevision": "1", "requestedLocale": "en-US", "resolvedLocale": "en-US",
      "languageHint": "en", "backend": "metal", "runtime": CohereRuntimeProvenance.identity,
      "runtimeCommit": CohereRuntimeProvenance.commit,
      "modelID": descriptor.modelID, "modelRevision": descriptor.repositoryRevision,
      "quantization": descriptor.quantization,
      "chunkingRevision": CohereChunkPlanner.identity,
      "installedIdentity": descriptor.installationIdentity,
      "operatingSystemVersion": "27.0",
    ]
    return job
  }

  fileprivate func makeFixture() throws -> DraftAdoptionFixture {
    let inspection = CaptureInspection(
      byteCount: 128_000, duration: 16, isMonoAAC: true, isPlayable: true,
      sampleRate: 44_100, channelCount: 1, codecIdentifier: nil,
      approximateBitRate: 64_000)
    let receipt = QueueReceipt(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 1_762_000_000),
      language: .english, destinationReference: UUID(),
      installationBinding: "current", inspection: inspection)
    var job = QueueJob(receipt: receipt, state: .resultReady)
    job.attemptID = UUID()
    job.attemptGeneration = 1
    job.selectedMethodID = TranscriptionMethodIdentifiers.apple
    job.effectiveSettings = [
      "settingsRevision": "1", "requestedLocale": "en-US", "resolvedLocale": "en-US",
      "runtime": "apple-speech-analyzer", "preset": "transcription",
      "resultPolicy": "final-only",
    ]
    job.conversionIdentity = "ndm.apple-speech.av-audio-file-v1"
    let queue = MemoryQueueStore()
    queue.values[job.id] = job
    let candidates = MemoryCandidateStore()
    candidates.published[job.id] = TranscriptionPayload(
      text: "I wrote a diary entry. Another sentence.", sourceDigest: "digest",
      resolvedLocale: "en-US", runtime: "apple-speech-analyzer",
      conversion: "ndm.apple-speech.av-audio-file-v1", operatingSystemVersion: "27.0")
    let drafts = MemoryDiaryDraftStore()
    let receipts = MemoryReceiptSource([receipt])
    let registry = TranscriptionMethodRegistry()
    let processing = ProcessingQueueCoordinator(
      store: queue, receipts: receipts, identity: FakeInstallationIdentity(),
      settings: FakeTranscriptionSettings(), registry: registry,
      candidates: candidates, drafts: drafts)
    let adopter = DiaryDraftAdoptionCoordinator(
      queue: queue, receipts: receipts, candidates: candidates, drafts: drafts,
      titles: DiaryTitlePolicy(
        model: UnavailableTitleModel(), languageDetector: NaturalLanguageTitleDetector()))
    return DraftAdoptionFixture(
      job: job, receipt: receipt, queue: queue, candidates: candidates,
      drafts: drafts, adopter: adopter, processing: processing)
  }

  fileprivate func sampleSnippet(job: QueueJob, receipt: QueueReceipt) throws -> DiarySnippetV1 {
    guard let rawID = job.draftAssetID else { throw QueueStoreFailure.corrupt }
    let candidate = TranscriptionPayload(
      text: "I wrote a diary entry. Another sentence.", sourceDigest: "digest",
      resolvedLocale: "en-US", runtime: "apple-speech-analyzer",
      conversion: "ndm.apple-speech.av-audio-file-v1", operatingSystemVersion: "27.0")
    var snippet = try DiaryDraftFactory().make(
      job: job, receipt: receipt, candidate: candidate,
      assetID: AssetID(rawID), updatedAt: Date(),
      title: DiaryTitlePolicy.fallback(candidate.text))
    snippet.audioSHA256 = nil
    return snippet
  }
}

// swiftlint:enable trailing_comma file_length
