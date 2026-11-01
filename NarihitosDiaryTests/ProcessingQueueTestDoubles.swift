import Foundation

@testable import NarihitosDiary

@MainActor
final class SuspendedPreflightTranscriber: AsynchronousTranscriptionReadiness {
  let descriptor = TranscriptionDescriptor(
    id: "slow", supportedLanguages: [.english], requiresMonoAAC: true)
  var pending: CheckedContinuation<TranscriptionPreflight, Never>?
  var requests: [TranscriptionRequest] = []

  func readiness(for _: CaptureLanguage) -> TranscriptionReadiness { .waiting(.appleNotReady) }

  func preflight(for _: CaptureLanguage) async -> TranscriptionPreflight {
    await withCheckedContinuation { pending = $0 }
  }

  func resolve(_ result: TranscriptionReadiness, values: [String: String] = [:]) {
    let continuation = pending
    pending = nil
    continuation?.resume(
      returning: TranscriptionPreflight(readiness: result, effectiveValues: values))
  }

  func start(
    _ request: TranscriptionRequest,
    completion _: @escaping @MainActor (TranscriptionResult) -> Void
  ) -> any TranscriptionWork {
    requests.append(request)
    return FakeWork(onCancel: {})
  }
}

@MainActor
final class MemoryCandidateStore: TranscriptionCandidateStore {
  var published: [String: TranscriptionPayload] = [:]
  var failPublish = false
  var publishFailure: TranscriptionCandidateFailure?
  var onPublish: (() -> Void)?
  var inspected: [String] = []

  func publish(
    _ payload: TranscriptionPayload, request: TranscriptionRequest, job: QueueJob
  ) throws {
    onPublish?()
    if failPublish { throw QueueStoreFailure.unavailable }
    if let publishFailure {
      self.publishFailure = nil
      throw publishFailure
    }
    guard job.id == request.jobID, job.attemptID == request.attemptID,
      job.attemptGeneration == request.generation
    else { throw QueueStoreFailure.corrupt }
    published[job.id] = payload
  }

  func inspect(job: QueueJob) throws -> CandidateInspection {
    inspected.append(job.id)
    return published[job.id] == nil ? .missing : .verified
  }

  func discard(job: QueueJob) throws { published.removeValue(forKey: job.id) }

  func readVerified(job: QueueJob) throws -> TranscriptionPayload {
    guard job.state == .resultReady, let value = published[job.id] else {
      throw QueueStoreFailure.corrupt
    }
    return value
  }
}

@MainActor
final class MemoryQueueStore: QueueStorePort {
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
final class MemoryReceiptSource: QueueReceiptSourcePort {
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
final class FakeInstallationIdentity: InstallationIdentityPort {
  var result: InstallationIdentityResult = .available("current")
  func currentOrCreate() -> InstallationIdentityResult { result }
  func current() -> InstallationIdentityResult { result }
}

@MainActor
final class FakeTranscriptionSettings: TranscriptionSettingsPort {
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
final class FakeTranscriber: TranscriptionMethodAdapter {
  let descriptor: TranscriptionDescriptor
  var readinessValue: TranscriptionReadiness
  var requests: [TranscriptionRequest] = []
  var cancelCalls = 0
  private var completion: (@MainActor (TranscriptionResult) -> Void)?
  private var callbacks: [@MainActor (TranscriptionResult) -> Void] = []

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
    callbacks.append(completion)
    return FakeWork { [weak self] in self?.cancelCalls += 1 }
  }

  func finish(_ result: TranscriptionResult) {
    let callback = completion
    completion = nil
    callback?(result)
  }

  func replayCallback(at index: Int, result: TranscriptionResult) {
    callbacks[index](result)
  }
}

@MainActor
final class FakeWork: TranscriptionWork {
  let onCancel: () -> Void
  init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
  func cancel() { onCancel() }
}
