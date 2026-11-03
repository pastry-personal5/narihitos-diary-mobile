import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

@MainActor
struct CohereCandidateHandoffTests {
  @Test(
    arguments: [TranscriptionModelSelection.cohereQ4, .cohereQ5],
    [CaptureLanguage.english, .korean])
  func productionSettingsPublishAndReopenWithoutPausing(
    selection: TranscriptionModelSelection, language: CaptureLanguage
  ) async throws {
    let fixture = try CohereHandoffFixture(selection: selection, language: language)
    defer { fixture.clean() }
    let coordinator = fixture.coordinator()
    coordinator.activate()
    let request = try await fixture.request(at: 0)
    #expect(request.settings.values.count == 13)
    #expect(request.settings.values["settingsRevision"] == "2")
    #expect(request.settings.values["languageHint"] == (language == .english ? "en" : "ko"))
    let payload = fixture.payload(for: request)

    fixture.adapter.finish(.success(payload))

    #expect(coordinator.pausedReason == nil)
    #expect(!coordinator.hasActiveWork)
    let job = try #require(fixture.store.jobs().first)
    #expect(job.state == .resultReady)
    #expect(try fixture.candidates.inspect(job: job) == .verified)
    #expect(try fixture.candidates.readVerified(job: job) == payload)
    let snippet = try fixture.draft(for: job, payload: payload)
    #expect(snippet.language == language.rawValue)
    #expect(snippet.transcription.languageHint == language.rawValue)
    #expect(snippet.transcription.settingsRevision == 2)
    let codec = DiarySnippetMarkdownCodec()
    #expect(try codec.decode(codec.encode(snippet)) == .supported(snippet))

    // Reconstruct the durable store/coordinator as after a fresh process launch.
    coordinator.deactivate()
    let reopenedStore = FileQueueStore(root: fixture.queueRoot)
    let reopened = fixture.coordinator(store: reopenedStore)
    reopened.activate()
    #expect(reopened.pausedReason == nil)
    #expect(try reopenedStore.jobs().first?.state == .resultReady)
    #expect(fixture.adapter.requests.count == 1)
    #expect(fixture.receipts.removed.isEmpty)
  }

  @Test func interruptedQ4ClaimCanRetryAndTheNextRecordingProgresses() async throws {
    let fixture = try CohereHandoffFixture(selection: .cohereQ4, language: .english, count: 2)
    defer { fixture.clean() }
    // A publication rejection left the old attempt transcribing without a candidate.
    var interrupted = QueueJob(receipt: fixture.items[0], state: .transcribing)
    interrupted.attemptGeneration = 1
    interrupted.attemptID = UUID()
    _ = try fixture.store.createIfAbsent(interrupted)
    let coordinator = fixture.coordinator()
    coordinator.activate()
    #expect(try fixture.store.jobs().first(where: { $0.id == interrupted.id })?.state == .failed)
    let next = try await fixture.request(at: 0)
    #expect(next.jobID == fixture.items[1].id.description)
    fixture.adapter.finish(.success(fixture.payload(for: next)))
    #expect(coordinator.pausedReason == nil)

    coordinator.manualRetry(jobID: interrupted.id)
    let retried = try await fixture.request(at: 1)
    #expect(retried.jobID == interrupted.id)
    #expect(retried.generation > interrupted.attemptGeneration)
    #expect(retried.settings.modelIdentity == CohereTrustedModel.productionQ4.installationIdentity)
    fixture.adapter.finish(.success(fixture.payload(for: retried)))

    #expect(coordinator.pausedReason == nil)
    #expect(try fixture.store.jobs().allSatisfy { $0.state == .resultReady })
    #expect(fixture.receipts.removed.isEmpty)
  }

  @Test func diaryCodecRejectsUnsupportedMethodRevisions() async throws {
    let fixture = try CohereHandoffFixture(selection: .cohereQ4, language: .english)
    defer { fixture.clean() }
    let coordinator = fixture.coordinator()
    coordinator.activate()
    let request = try await fixture.request(at: 0)
    let payload = fixture.payload(for: request)
    fixture.adapter.finish(.success(payload))
    let job = try #require(fixture.store.jobs().first)
    let snippet = try fixture.draft(for: job, payload: payload)
    let codec = DiarySnippetMarkdownCodec()
    let source = try #require(String(data: codec.encode(snippet), encoding: .utf8))
    for revision in ["0", "-1", "3", "9223372036854775807"] {
      let changed = source.replacingOccurrences(
        of: "transcription_settings_revision: 2",
        with: "transcription_settings_revision: \(revision)")
      #expect(codec.decode(Data(changed.utf8)) == .malformed(.invalidField))
    }
    let apple = source.replacingOccurrences(
      of: TranscriptionMethodIdentifiers.cohere, with: TranscriptionMethodIdentifiers.apple)
    #expect(codec.decode(Data(apple.utf8)) == .malformed(.invalidField))
  }

  @Test func revisionTwoStillRejectsMissingExtraAndCrossedProvenance() async throws {
    let fixture = try CohereHandoffFixture(selection: .cohereQ4, language: .korean)
    defer { fixture.clean() }
    let coordinator = fixture.coordinator()
    coordinator.activate()
    let request = try await fixture.request(at: 0)
    let original = try #require(fixture.store.jobs().first)
    let payload = fixture.payload(for: request)
    for key in request.settings.values.keys {
      var job = original
      job.effectiveSettings?.removeValue(forKey: key)
      let changedRequest = fixture.request(matching: job)
      #expect(throws: QueueStoreFailure.corrupt) {
        try fixture.candidates.publish(payload, request: changedRequest, job: job)
      }
    }
    let substitutions = [
      "unapprovedField": "value", "backend": "cpu", "languageHint": "en",
      "quantization": "Q5_K_M",
      "installedIdentity": CohereTrustedModel.productionQ5.installationIdentity,
      "runtime": "unapproved-runtime", "settingsRevision": "3",
    ]
    for (key, value) in substitutions {
      var job = original
      job.effectiveSettings?[key] = value
      let changedRequest = fixture.request(matching: job)
      #expect(throws: QueueStoreFailure.corrupt) {
        try fixture.candidates.publish(payload, request: changedRequest, job: job)
      }
    }
    #expect(try fixture.candidates.inspect(job: original) == .missing)
    // The original production snapshot remains acceptable after the rejected writes.
    fixture.adapter.finish(.success(payload))
    #expect(coordinator.pausedReason == nil)
    #expect(try fixture.store.jobs().first?.state == .resultReady)
  }
}

@MainActor
private final class CohereHandoffFixture {
  let root: URL
  let queueRoot: URL
  let store: FileQueueStore
  let settings: ProductionTranscriptionSettings
  let items: [QueueReceipt]
  let receipts: MemoryReceiptSource
  let candidates: FileTranscriptionCandidateStore
  let adapter: ReadyCohereHandoffAdapter
  let registry = TranscriptionMethodRegistry()

  init(
    selection: TranscriptionModelSelection, language: CaptureLanguage, count: Int = 1
  ) throws {
    root = FileManager.default.temporaryDirectory.appending(path: "cohere-handoff-\(UUID())")
    queueRoot = root.appending(path: "queue")
    store = FileQueueStore(root: queueRoot)
    let repository = PrivateSettingsRepository(root: root.appending(path: "settings"))
    try repository.selectTranscriptionModel(selection)
    settings = ProductionTranscriptionSettings(repository: repository)
    let captureRoot = root.appending(path: "captures")
    items = try (0..<count).map { index in
      let id = try WorkspaceID(UUID().uuidString.lowercased())
      try FileManager.default.createDirectory(
        at: captureRoot.appending(path: id.description), withIntermediateDirectories: true)
      return QueueReceipt(
        id: id, startedAt: Date(timeIntervalSince1970: Double(index + 1)), language: language,
        destinationReference: UUID(), installationBinding: "current",
        inspection: CaptureInspection(
          byteCount: 1_024, duration: 1, isMonoAAC: true, isPlayable: true,
          sampleRate: 44_100, channelCount: 1, approximateBitRate: 64_000))
    }
    receipts = MemoryReceiptSource(items)
    candidates = FileTranscriptionCandidateStore(
      root: captureRoot, audio: HandoffFingerprint(), protection: HandoffProtection(),
      protectedDataAvailable: { true })
    adapter = ReadyCohereHandoffAdapter(
      descriptor: selection == .cohereQ5 ? .productionQ5 : .productionQ4)
    registry.register(adapter)
  }

  func coordinator(store: FileQueueStore? = nil) -> ProcessingQueueCoordinator {
    ProcessingQueueCoordinator(
      store: store ?? self.store, receipts: receipts, identity: FakeInstallationIdentity(),
      settings: settings, registry: registry, candidates: candidates)
  }

  func request(at index: Int) async throws -> TranscriptionRequest {
    for _ in 0..<1_000 where adapter.requests.count <= index {
      try await Task.sleep(for: .milliseconds(1))
    }
    try #require(adapter.requests.count > index)
    return adapter.requests[index]
  }

  func request(matching job: QueueJob) -> TranscriptionRequest {
    TranscriptionRequest(
      jobID: job.id, attemptID: job.attemptID!, generation: job.attemptGeneration,
      language: job.language,
      settings: EffectiveTranscriptionSettings(
        values: job.effectiveSettings!, modelIdentity: job.modelIdentity,
        conversionIdentity: job.conversionIdentity!),
      destinationRevision: job.destinationRevision, bodyRevision: job.bodyRevision)
  }

  func payload(for request: TranscriptionRequest) -> TranscriptionPayload {
    TranscriptionPayload(
      text: "Synthetic diary.", sourceDigest: String(repeating: "a", count: 64),
      resolvedLocale: request.language.rawValue, runtime: CohereRuntimeProvenance.identity,
      conversion: CohereAudioConversion.identity,
      operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString)
  }

  func draft(for original: QueueJob, payload: TranscriptionPayload) throws -> DiarySnippetV1 {
    var job = original
    let assetID = try AssetID(UUID().uuidString.lowercased())
    job.draftAssetID = assetID.description
    let receipt = try #require(items.first(where: { $0.id.description == job.id }))
    return try DiaryDraftFactory().make(
      job: job, receipt: receipt, candidate: payload, assetID: assetID,
      updatedAt: job.startedAt,
      title: DiaryTitlePolicy.fallback(payload.text))
  }

  func clean() { try? FileManager.default.removeItem(at: root) }
}

/// Models a successful runtime handoff, not installation, Metal inference or Q5 certification.
@MainActor
private final class ReadyCohereHandoffAdapter: AsynchronousTranscriptionReadiness {
  let descriptor = TranscriptionDescriptor(
    id: TranscriptionMethodIdentifiers.cohere, supportedLanguages: [.english, .korean],
    requiresMonoAAC: true)
  let model: CohereTrustedModel
  var requests: [TranscriptionRequest] = []
  private var completion: (@MainActor (TranscriptionResult) -> Void)?

  init(descriptor: CohereTrustedModel) { model = descriptor }

  func readiness(for _: CaptureLanguage) -> TranscriptionReadiness { .ready }

  func preflight(for language: CaptureLanguage) async -> TranscriptionPreflight {
    TranscriptionPreflight(
      readiness: .ready,
      effectiveValues: [
        "installedIdentity": model.installationIdentity, "resolvedLocale": language.rawValue,
        "operatingSystemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
  }

  func start(
    _ request: TranscriptionRequest,
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) -> any TranscriptionWork {
    requests.append(request)
    self.completion = completion
    return FakeWork(onCancel: {})
  }

  func finish(_ result: TranscriptionResult) {
    let callback = completion
    completion = nil
    callback?(result)
  }
}

@MainActor
private struct HandoffFingerprint: CaptureAudioFingerprintSource {
  func fingerprint(for _: QueueJob) throws -> String { String(repeating: "a", count: 64) }
}

private struct HandoffProtection: CandidateProtectionPolicy {
  func apply(to _: URL, manager _: FileManager) throws {}
  func verify(to _: URL, manager _: FileManager) throws {}
}

// swiftlint:enable trailing_comma
