import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct ProcessingQueueTests {
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

    adapter.finish(.success)
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

  private func makeCoordinator(
    store: MemoryQueueStore, source: MemoryReceiptSource,
    identity: FakeInstallationIdentity = FakeInstallationIdentity(),
    settings: FakeTranscriptionSettings = FakeTranscriptionSettings(),
    registry: TranscriptionMethodRegistry = TranscriptionMethodRegistry(),
    timeout: Duration = .seconds(600)
  ) -> ProcessingQueueCoordinator {
    ProcessingQueueCoordinator(
      store: store, receipts: source, identity: identity,
      settings: settings, registry: registry, timeout: timeout)
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

@MainActor
private final class MemoryQueueStore: QueueStorePort {
  var values: [String: QueueJob] = [:]
  var createCalls = 0
  var failReplace = false

  func jobs() throws -> [QueueJob] { Array(values.values) }

  func createIfAbsent(_ job: QueueJob) throws -> QueueJob {
    if let existing = values[job.id] { return existing }
    createCalls += 1
    values[job.id] = job
    return job
  }

  func replace(_ job: QueueJob) throws {
    if failReplace { throw QueueStoreFailure.unavailable }
    values[job.id] = job
  }

  func remove(jobID: String) throws { values.removeValue(forKey: jobID) }
}

@MainActor
private final class MemoryReceiptSource: QueueReceiptSourcePort {
  var values: [String: QueueReceipt]
  var removed: [String] = []

  init(_ values: [QueueReceipt]) {
    self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.id.description, $0) })
  }

  func pendingReceipts() -> [QueueReceipt] { Array(values.values) }
  func receipt(jobID: String) -> QueueReceipt? { values[jobID] }

  func removePrivateCapture(jobID: String) throws {
    guard values.removeValue(forKey: jobID) != nil else { throw QueueStoreFailure.corrupt }
    removed.append(jobID)
  }
}

@MainActor
private final class FakeInstallationIdentity: InstallationIdentityPort {
  var result: InstallationIdentityResult = .available("current")
  func currentOrCreate() -> InstallationIdentityResult { result }
  func current() -> InstallationIdentityResult { result }
}

@MainActor
private final class FakeTranscriptionSettings: TranscriptionSettingsPort {
  var methods: [CaptureLanguage: String] = [:]
  var revision = "one"

  func selectedMethodID(for language: CaptureLanguage) -> String? { methods[language] }

  func effectiveSettings(
    methodID: String, language _: CaptureLanguage
  ) -> EffectiveTranscriptionSettings {
    EffectiveTranscriptionSettings(
      values: ["revision": revision], modelIdentity: "\(methodID)-model",
      conversionIdentity: "pcm-v1")
  }
}

@MainActor
private final class FakeTranscriber: TranscriptionMethodAdapter {
  let descriptor: TranscriptionDescriptor
  var readinessValue: TranscriptionReadiness
  var requests: [TranscriptionRequest] = []
  var cancelCalls = 0
  private var completion: (@MainActor (TranscriptionResult) -> Void)?

  init(id: String, readiness: TranscriptionReadiness) {
    descriptor = TranscriptionDescriptor(
      id: id, supportedLanguages: [.english, .korean], requiresMonoAAC: true)
    readinessValue = readiness
  }

  func readiness(for _: CaptureLanguage) -> TranscriptionReadiness { readinessValue }

  func start(
    _ request: TranscriptionRequest,
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) -> any TranscriptionWork {
    requests.append(request)
    self.completion = completion
    return FakeWork { [weak self] in self?.cancelCalls += 1 }
  }

  func finish(_ result: TranscriptionResult) {
    let callback = completion
    completion = nil
    callback?(result)
  }
}

@MainActor
private final class FakeWork: TranscriptionWork {
  let onCancel: () -> Void
  init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
  func cancel() { onCancel() }
}
