import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable file_length

@MainActor
private final class FakeSaveWork: QueueSaveWork {
  var working = true
  func isWorking(jobID _: String) -> Bool { working }
}

@MainActor
struct ProcessingQueueTests {
  @Test func saveRemovalWaitsForProviderToRelinquish() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    store.values[item.id.description] = QueueJob(receipt: item, state: .readyToSave)
    let source = MemoryReceiptSource([item])
    let coordinator = makeCoordinator(store: store, source: source)
    let save = FakeSaveWork()
    coordinator.saveWork = save

    coordinator.remove(jobID: item.id.description)
    coordinator.reconcile()
    #expect(store.values[item.id.description]?.state == .cancelling)
    #expect(source.removed.isEmpty)
    save.working = false
    coordinator.saveAttemptSettled(jobID: item.id.description)
    #expect(store.values[item.id.description] == nil)
    #expect(source.removed == [item.id.description])
  }

  @Test func existingJobFromAnotherInstallationRequiresReview() throws {
    let item = try receipt(start: 1, binding: "former")
    let store = MemoryQueueStore()
    store.values[item.id.description] = QueueJob(receipt: item, state: .ready)
    let coordinator = makeCoordinator(store: store, source: MemoryReceiptSource([item]))

    coordinator.activate()

    #expect(store.values[item.id.description]?.state == .reviewRequired)
  }

  @Test func failedRemovalTombstonePreservesCapture() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let coordinator = makeCoordinator(store: store, source: source)
    coordinator.activate()
    store.failReplace = true

    coordinator.remove(jobID: item.id.description)

    #expect(source.removed.isEmpty)
    #expect(store.values[item.id.description] != nil)
    #expect(coordinator.pausedReason != nil)
  }

  @Test func adoptionIsIdempotentAndRestoredWorkIsQuarantined() throws {
    let current = try receipt(start: 1, binding: "current")
    let restored = try receipt(start: 2, binding: "former")
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([current, restored])
    let coordinator = makeCoordinator(store: store, source: source)

    coordinator.activate()
    coordinator.activate()

    #expect(store.values.count == 2)
    #expect(store.values[current.id.description]?.state == .waiting)
    #expect(store.values[restored.id.description]?.state == .reviewRequired)
    #expect(store.createCalls == 2)
    #expect(source.removed.isEmpty)
  }

  @Test func waitingOldestAndFailedMiddleDoNotBlockReadyNewest() throws {
    let first = try receipt(start: 1)
    let second = try receipt(start: 2, language: .korean)
    let third = try receipt(start: 3, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([first, second, third])
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "waiting"
    settings.methods[.korean] = "ready"
    let registry = TranscriptionMethodRegistry()
    let waiting = FakeTranscriber(id: "waiting", readiness: .waiting(.methodUnavailable))
    let ready = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(waiting)
    registry.register(ready)
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)

    coordinator.activate()
    #expect(store.values[first.id.description]?.state == .waiting)
    #expect(ready.requests.map(\.jobID) == [second.id.description])

    ready.finish(.failure(.unusableText))
    #expect(ready.requests.map(\.jobID) == [second.id.description, third.id.description])
    #expect(store.values[second.id.description]?.state == .failed)
    #expect(
      store.values[first.id.description]?.reason
        == "The selected transcription method isn’t ready.")
  }

  @Test func timeoutInvalidatesAttemptAndWaitsForRelinquishment() async throws {
    let first = try receipt(start: 1, language: .korean)
    let second = try receipt(start: 2, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([first, second])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.korean] = "ready"
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry,
      timeout: .milliseconds(10))

    coordinator.activate()
    try await Task.sleep(for: .milliseconds(30))
    #expect(adapter.cancelCalls == 1)
    #expect(adapter.requests.count == 1)
    #expect(store.values[first.id.description]?.state == .failed)
    #expect(store.values[first.id.description]?.reason == ProcessingQueueCoordinator.timeoutReason)

    adapter.finish(.success(payload))
    #expect(adapter.requests.map(\.jobID) == [first.id.description, second.id.description])
    #expect(store.values[first.id.description]?.state == .failed)
  }

  @Test func retryTakesFreshMethodAndSettingsWithoutAttemptOverlap() throws {
    let item = try receipt(start: 1, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let first = FakeTranscriber(id: "first", readiness: .ready)
    let second = FakeTranscriber(id: "second", readiness: .ready)
    registry.register(first)
    registry.register(second)
    let settings = FakeTranscriptionSettings()
    settings.methods[.korean] = "first"
    settings.revision = "one"
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)

    coordinator.activate()
    first.finish(.failure(.unusableText))
    settings.methods[.korean] = "second"
    settings.revision = "two"
    coordinator.manualRetry(jobID: item.id.description)

    #expect(second.requests.count == 1)
    #expect(second.requests[0].settings.values["revision"] == "two")
    #expect(store.values[item.id.description]?.selectedMethodID == "second")
    #expect(store.values[item.id.description]?.attemptGeneration == 3)
  }

  @Test func removalShowsCancellingUntilAdapterRelinquishesThenCleansOwnedCapture() throws {
    let item = try receipt(start: 1, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.korean] = "ready"
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)
    coordinator.activate()

    coordinator.remove(jobID: item.id.description)
    coordinator.activate()
    #expect(store.values[item.id.description]?.state == .cancelling)
    #expect(source.removed.isEmpty)
    #expect(adapter.cancelCalls == 1)

    adapter.finish(.failure(.cancelled))
    #expect(store.values[item.id.description] == nil)
    #expect(source.removed == [item.id.description])
  }

  @Test func storeWriteFailurePausesQueueBeforeAdapterStarts() throws {
    let item = try receipt(start: 1, language: .korean)
    let store = MemoryQueueStore()
    store.failReplace = true
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.korean] = "ready"
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)

    coordinator.activate()
    #expect(adapter.requests.isEmpty)
    #expect(coordinator.pausedReason == ProcessingQueueCoordinator.pausedReason)
  }

  @Test func inactiveQueueAdoptsButDoesNotStartAnAttempt() throws {
    let item = try receipt(start: 1, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.korean] = "ready"
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)

    coordinator.reconcile()

    #expect(store.values[item.id.description]?.state == .ready)
    #expect(adapter.requests.isEmpty)
  }

}

extension ProcessingQueueTests {
  @Test func unavailableInstallationIdentityPausesWithoutClassifyingReceipts() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let identity = FakeInstallationIdentity()
    identity.result = .temporarilyUnavailable
    let coordinator = makeCoordinator(
      store: store, source: MemoryReceiptSource([item]), identity: identity)

    coordinator.activate()

    #expect(store.values.isEmpty)
    #expect(coordinator.pausedReason == ProcessingQueueCoordinator.pausedReason)
  }

  @Test func restoredResumeUsesCurrentInstallationAndSettings() throws {
    let item = try receipt(start: 1, binding: nil, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.korean] = "ready"
    settings.revision = "current"
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)

    coordinator.activate()
    #expect(adapter.requests.isEmpty)
    coordinator.resumeRestored(jobID: item.id.description)

    #expect(adapter.requests.first?.settings.values["revision"] == "current")
    #expect(store.values[item.id.description]?.installationBinding == "current")
  }

  @Test func fileStorePersistsOnceWithBackupExclusion() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "queue-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileQueueStore(root: root)
    let item = try receipt(start: 1)
    let job = QueueJob(receipt: item, state: .ready)

    _ = try store.createIfAbsent(job)
    _ = try store.createIfAbsent(job)

    #expect(try store.jobs() == [job])
    let record = root.appending(path: "\(job.id).json")
    let values = try record.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test func successIsPublishedBeforeQueueBecomesResultReady() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    candidates.onPublish = { #expect(store.values[item.id.description]?.state == .transcribing) }
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry,
      candidates: candidates)
    coordinator.activate()
    adapter.finish(.success(payload))
    #expect(candidates.published[item.id.description] == payload)
    #expect(store.values[item.id.description]?.state == .resultReady)
    #expect(store.values[item.id.description]?.attemptID != nil)
  }

  @Test func slowReadinessDoesNotBlockAnotherReadyMethod() async throws {
    let slowItem = try receipt(start: 1, language: .english)
    let readyItem = try receipt(start: 2, language: .korean)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([slowItem, readyItem])
    let registry = TranscriptionMethodRegistry()
    let slow = SuspendedPreflightTranscriber()
    let ready = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(slow)
    registry.register(ready)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = slow.descriptor.id
    settings.methods[.korean] = ready.descriptor.id
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)
    coordinator.activate()
    #expect(ready.requests.map(\.jobID) == [readyItem.id.description])
    while slow.pending == nil { await Task.yield() }
    coordinator.deactivate()
    slow.resolve(.ready)
    await Task.yield()
    #expect(slow.requests.isEmpty)
  }

  @Test func selectionChangeFencesAnOlderPreflight() async throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let slow = SuspendedPreflightTranscriber()
    let ready = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(slow)
    registry.register(ready)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = slow.descriptor.id
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)
    coordinator.activate()
    while slow.pending == nil { await Task.yield() }
    settings.methods[.english] = "ready"
    coordinator.prerequisiteChanged()
    slow.resolve(.ready)
    await Task.yield()
    #expect(slow.requests.isEmpty)
    #expect(ready.requests.map(\.jobID) == [item.id.description])
  }

  @Test func preflightSnapshotsEffectiveValuesAndWaitsWhenAssetDisappears() async throws {
    let item = try receipt(start: 1, language: .english)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([item])
    let registry = TranscriptionMethodRegistry()
    let adapter = SuspendedPreflightTranscriber()
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = adapter.descriptor.id
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)
    coordinator.activate()
    while adapter.pending == nil { await Task.yield() }
    adapter.resolve(.waiting(.appleNotReady))
    while store.values[item.id.description]?.state == .ready { await Task.yield() }
    #expect(store.values[item.id.description]?.state == .waiting)
    #expect(
      store.values[item.id.description]?.reason == "Apple transcription isn’t ready for English.")
    #expect(adapter.requests.isEmpty)
    coordinator.prerequisiteChanged()
    while adapter.pending == nil { await Task.yield() }
    adapter.resolve(.ready, values: ["resolvedLocale": "en-US"])
    while adapter.requests.isEmpty { await Task.yield() }
    #expect(adapter.requests[0].settings.values["resolvedLocale"] == "en-US")
    #expect(store.values[item.id.description]?.effectiveSettings?["resolvedLocale"] == "en-US")
  }

  @Test func sixPendingJobsShareOneMethodPreflight() async throws {
    let items = try (1...6).map { try receipt(start: Double($0)) }
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource(items)
    let registry = TranscriptionMethodRegistry()
    let adapter = SuspendedPreflightTranscriber()
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = adapter.descriptor.id
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry)

    coordinator.activate()
    while adapter.pending == nil { await Task.yield() }
    await Task.yield()

    #expect(adapter.preflightCalls == 1)
    adapter.resolve(.waiting(.appleNotReady))
    for item in items {
      while store.values[item.id.description]?.state == .ready { await Task.yield() }
    }
    #expect(store.values.values.filter { $0.state == .waiting }.count == 6)
  }

  @Test func sixReadyJobsClaimSeriallyAndRecheckReadinessForEveryAttempt() async throws {
    let items = try (1...6).map { try receipt(start: Double($0)) }
    let store = MemoryQueueStore()
    let registry = TranscriptionMethodRegistry()
    let adapter = SuspendedPreflightTranscriber()
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = adapter.descriptor.id
    let coordinator = makeCoordinator(
      store: store, source: MemoryReceiptSource(items), settings: settings, registry: registry)
    coordinator.activate()
    for (index, item) in items.enumerated() {
      for _ in 0..<100 where adapter.pending == nil { await Task.yield() }
      #expect(adapter.preflightCalls == index + 1)
      adapter.resolve(.ready)
      for _ in 0..<100 where adapter.requests.count <= index { await Task.yield() }
      #expect(adapter.requests.map(\.jobID) == items.prefix(index + 1).map { $0.id.description })
      #expect(store.values.values.filter { $0.state == .transcribing }.count == 1)
      #expect(store.values[item.id.description]?.state == .transcribing)
      adapter.finish(.failure(.inference))
    }
    #expect(store.values.values.filter { $0.state == .failed }.count == 6)
  }

  @Test func removedPreflightOwnerCannotBlockTheNextRecording() async throws {
    let items = try (1...2).map { try receipt(start: Double($0)) }
    let store = MemoryQueueStore()
    let registry = TranscriptionMethodRegistry()
    let adapter = SuspendedPreflightTranscriber()
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = adapter.descriptor.id
    let coordinator = makeCoordinator(
      store: store, source: MemoryReceiptSource(items), settings: settings, registry: registry)
    coordinator.activate()
    for _ in 0..<100 where adapter.pending == nil { await Task.yield() }
    coordinator.remove(jobID: items[0].id.description)
    adapter.resolve(.ready)
    for _ in 0..<100 where adapter.pending == nil { await Task.yield() }
    #expect(adapter.preflightCalls == 2)
    adapter.resolve(.ready)
    for _ in 0..<100 where adapter.requests.isEmpty { await Task.yield() }
    #expect(adapter.requests.map(\.jobID) == [items[1].id.description])
    adapter.finish(.failure(.inference))
  }

  @Test func candidateFailurePausesWithoutClaimingSuccess() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    candidates.failPublish = true
    let coordinator = makeCoordinator(
      store: store, source: MemoryReceiptSource([item]), settings: settings,
      registry: registry, candidates: candidates)
    coordinator.activate()
    adapter.finish(.success(payload))
    #expect(store.values[item.id.description]?.state == .transcribing)
    #expect(coordinator.pausedReason == ProcessingQueueCoordinator.pausedReason)
  }

  @Test func substitutedAudioFailsOnlyItsJobAndDoesNotPauseTheQueue() throws {
    let first = try receipt(start: 1)
    let second = try receipt(start: 2)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([first, second])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    candidates.publishFailure = .invalidSource
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry, candidates: candidates)
    coordinator.activate()
    adapter.finish(.success(payload))
    #expect(store.values[first.id.description]?.state == .failed)
    #expect(store.values[first.id.description]?.reason == "This recording can’t be read.")
    #expect(coordinator.pausedReason == nil)
    #expect(source.removed.isEmpty)
    #expect(adapter.requests.map(\.jobID) == [first.id.description, second.id.description])
  }

  @Test func failedRemovalWriteStillInvalidatesInFlightResult() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    let coordinator = makeCoordinator(
      store: store, source: MemoryReceiptSource([item]), settings: settings,
      registry: registry, candidates: candidates)
    coordinator.activate()
    store.failReplace = true
    coordinator.remove(jobID: item.id.description)
    #expect(adapter.cancelCalls == 1)
    adapter.finish(.success(payload))
    #expect(candidates.published.isEmpty)
    #expect(coordinator.pausedReason == ProcessingQueueCoordinator.pausedReason)
  }

  @Test func publishedResultSurvivesQueueTransitionFailure() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    let source = MemoryReceiptSource([item])
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry,
      candidates: candidates)
    coordinator.activate()
    candidates.onPublish = { store.failReplace = true }
    adapter.finish(.success(payload))
    #expect(store.values[item.id.description]?.state == .transcribing)
    #expect(coordinator.pausedReason != nil)
    store.failReplace = false
    let reopened = makeCoordinator(store: store, source: source, candidates: candidates)
    reopened.reconcile()
    #expect(store.values[item.id.description]?.state == .resultReady)
  }

  @Test func duplicateAndStaleResultsCannotPublishToAnotherAttempt() throws {
    let first = try receipt(start: 1)
    let second = try receipt(start: 2)
    let store = MemoryQueueStore()
    let source = MemoryReceiptSource([first, second])
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    let coordinator = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry, candidates: candidates)
    coordinator.activate()
    adapter.finish(.success(payload))
    #expect(adapter.requests.map(\.jobID) == [first.id.description, second.id.description])
    adapter.replayCallback(at: 0, result: .success(payload))
    #expect(candidates.published.keys.count == 1)
    #expect(store.values[second.id.description]?.state == .transcribing)
    store.values[second.id.description]?.bodyRevision += 1
    adapter.finish(.success(payload))
    #expect(candidates.published[second.id.description] == nil)
    #expect(store.values[second.id.description]?.state != .resultReady)
  }

  @Test func reconciliationPromotesOnlyAClaimWithVerifiedCandidate() throws {
    let item = try receipt(start: 1)
    let store = MemoryQueueStore()
    let registry = TranscriptionMethodRegistry()
    let adapter = FakeTranscriber(id: "ready", readiness: .ready)
    registry.register(adapter)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = "ready"
    let candidates = MemoryCandidateStore()
    let source = MemoryReceiptSource([item])
    let first = makeCoordinator(
      store: store, source: source, settings: settings, registry: registry,
      candidates: candidates)
    first.activate()
    let claim = try #require(store.values[item.id.description])
    let request = try #require(adapter.requests.first)
    try candidates.publish(payload, request: request, job: claim)
    let reopened = makeCoordinator(store: store, source: source, candidates: candidates)
    reopened.reconcile()
    #expect(store.values[item.id.description]?.state == .resultReady)
  }

  @Test func restoredCandidateIsQuarantinedBeforeInspection() throws {
    let item = try receipt(start: 1, binding: "former")
    let store = MemoryQueueStore()
    var restored = QueueJob(receipt: item, state: .resultReady)
    restored.attemptID = UUID()
    restored.attemptGeneration = 1
    store.values[item.id.description] = restored
    let candidates = MemoryCandidateStore()
    candidates.published[item.id.description] = payload
    let coordinator = makeCoordinator(
      store: store, source: MemoryReceiptSource([item]), candidates: candidates)
    coordinator.reconcile()
    #expect(store.values[item.id.description]?.state == .reviewRequired)
    #expect(candidates.inspected.isEmpty)
    #expect(candidates.published[item.id.description] != nil)
  }

  private var payload: TranscriptionPayload {
    TranscriptionPayload(
      text: "A diary entry", sourceDigest: String(repeating: "0", count: 64),
      resolvedLocale: "en-US", runtime: "test", conversion: "test",
      operatingSystemVersion: "test")
  }

  private func makeCoordinator(
    store: MemoryQueueStore, source: MemoryReceiptSource,
    identity: FakeInstallationIdentity = FakeInstallationIdentity(),
    settings: FakeTranscriptionSettings = FakeTranscriptionSettings(),
    registry: TranscriptionMethodRegistry = TranscriptionMethodRegistry(),
    candidates: MemoryCandidateStore = MemoryCandidateStore(),
    timeout: Duration = .seconds(600)
  ) -> ProcessingQueueCoordinator {
    ProcessingQueueCoordinator(
      store: store, receipts: source, identity: identity,
      settings: settings, registry: registry, candidates: candidates, timeout: timeout)
  }

  private func receipt(
    start: TimeInterval, binding: String? = "current",
    language: CaptureLanguage = .english
  ) throws -> QueueReceipt {
    let id = try WorkspaceID(
      String(format: "00000000-0000-4000-8000-%012d", Int(start)))
    return QueueReceipt(
      id: id, startedAt: Date(timeIntervalSince1970: start), language: language,
      destinationReference: UUID(), installationBinding: binding,
      inspection: CaptureInspection(
        byteCount: 1_024, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1))
  }
}
