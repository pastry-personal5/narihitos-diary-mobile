import Foundation

// swiftlint:disable trailing_comma

@MainActor
protocol CohereAudioLease: AnyObject {
  var url: URL { get }
  var digest: String { get }
  func verifyUnchanged() throws
  func close() throws
}

@MainActor
protocol CohereAudioSource: AnyObject {
  func openForCohere(job: QueueJob) throws -> any CohereAudioLease
}

@MainActor
final class CohereTranscriptionAdapter: AsynchronousTranscriptionReadiness {
  let descriptor = TranscriptionDescriptor(
    id: TranscriptionMethodIdentifiers.cohere, supportedLanguages: [.english, .korean],
    requiresMonoAAC: true)
  private let store: any QueueStorePort
  private let audio: any CohereAudioSource
  private let q4Models: CohereModelManager
  private let q5Models: CohereModelManager
  private let selectedModel: @MainActor () -> TranscriptionModelSelection
  private let runtime: any CohereRuntimeRunning
  private let q5RuntimeCertified: @Sendable () -> Bool

  init(
    store: any QueueStorePort, audio: any CohereAudioSource, models: CohereModelManager,
    q5Models: CohereModelManager? = nil,
    selectedModel: @escaping @MainActor () -> TranscriptionModelSelection = { .cohereQ4 },
    runtime: any CohereRuntimeRunning = NativeCohereRuntime(),
    q5RuntimeCertified: @escaping @Sendable () -> Bool = { false }
  ) {
    self.store = store
    self.audio = audio
    self.q4Models = models
    self.q5Models = q5Models ?? models
    self.selectedModel = selectedModel
    self.runtime = runtime
    self.q5RuntimeCertified = q5RuntimeCertified
  }

  func readiness(for _: CaptureLanguage) -> TranscriptionReadiness {
    if case .ready = currentModels().readiness { return .ready }
    return .waiting(.cohereNotInstalled)
  }

  func preflight(for language: CaptureLanguage) async -> TranscriptionPreflight {
    let models = currentModels()
    guard case .ready(let identity) = await models.refresh(),
      identity == models.descriptor.installationIdentity
    else {
      return TranscriptionPreflight(
        readiness: .waiting(.cohereNotInstalled), effectiveValues: [:])
    }
    // iOS killed the production Q5 Metal load at its per-process limit even when
    // os_proc_available_memory() reported more than the trial-derived floor. The
    // kill cannot be caught, so fail closed until this exact production path has
    // separate target-device evidence. Installation remains independently valid.
    guard models.descriptor.quantization != "Q5_K_M" || q5RuntimeCertified() else {
      return TranscriptionPreflight(
        readiness: .waiting(.cohereQ5MemoryUnsupported), effectiveValues: [:])
    }
    return TranscriptionPreflight(
      readiness: .ready,
      effectiveValues: [
        "installedIdentity": identity,
        "resolvedLocale": language.rawValue,
        "operatingSystemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
  }

  func start(
    _ request: TranscriptionRequest,
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) -> any TranscriptionWork {
    guard let job = try? store.jobs().first(where: { $0.id == request.jobID }),
      job.state == .transcribing, job.attemptID == request.attemptID,
      job.attemptGeneration == request.generation, job.selectedMethodID == descriptor.id,
      request.settings.values["installedIdentity"] == q4Models.descriptor.installationIdentity
        || request.settings.values["installedIdentity"] == q5Models.descriptor.installationIdentity
    else {
      completion(.failure(.inference))
      return FinishedCohereWork()
    }
    let attempt = CohereTranscriptionAttempt(
      request: request, job: job, audio: audio,
      models: models(for: request.settings.values["installedIdentity"]), runtime: runtime,
      completion: completion)
    attempt.start()
    return attempt
  }

  private func currentModels() -> CohereModelManager {
    selectedModel() == .cohereQ5 ? q5Models : q4Models
  }

  private func models(for identity: String?) -> CohereModelManager {
    identity == q5Models.descriptor.installationIdentity ? q5Models : q4Models
  }
}

private enum CohereAttemptOutcome: Sendable {
  case success(TranscriptionPayload)
  case failure(TranscriptionFailure)
  case waiting
}

@MainActor
final class CohereTranscriptionAttempt: TranscriptionWork {
  private let request: TranscriptionRequest
  private let job: QueueJob
  private let audio: any CohereAudioSource
  private let models: CohereModelManager
  private let runtime: any CohereRuntimeRunning
  private let completion: @MainActor (TranscriptionResult) -> Void
  private let cancellation = CohereCancellationFlag()
  private var task: Task<Void, Never>?
  private var finished = false

  init(
    request: TranscriptionRequest, job: QueueJob, audio: any CohereAudioSource,
    models: CohereModelManager, runtime: any CohereRuntimeRunning,
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) {
    self.request = request
    self.job = job
    self.audio = audio
    self.models = models
    self.runtime = runtime
    self.completion = completion
  }

  func start() {
    guard task == nil else { return }
    task = Task { [weak self] in
      await self?.performAttempt()
    }
  }

  private func performAttempt() async {
    let modelLease: CohereModelLease
    do {
      modelLease = try await models.acquireLease()
    } catch CohereModelFailure.protectedDataUnavailable {
      finish(.waiting(.protectedDataUnavailable))
      return
    } catch is CancellationError {
      finish(.failure(.cancelled))
      return
    } catch {
      finish(.waiting(.cohereNotInstalled))
      return
    }
    let audioLease: any CohereAudioLease
    do {
      audioLease = try audio.openForCohere(job: job)
    } catch AudioFingerprintFailure.protectedDataUnavailable {
      models.release(modelLease)
      finish(.waiting(.protectedDataUnavailable))
      return
    } catch {
      models.release(modelLease)
      finish(.failure(.audioUnreadable))
      return
    }
    let runtime = self.runtime
    let request = self.request
    let cancellation = self.cancellation
    let audioURL = audioLease.url
    let sourceDigest = audioLease.digest
    let worker = Task.detached(priority: .userInitiated) {
      Self.perform(
        request: request, audioURL: audioURL, sourceDigest: sourceDigest,
        modelLease: modelLease, runtime: runtime, cancellation: cancellation)
    }
    let outcome = await worker.value
    do { try audioLease.verifyUnchanged() } catch {
      try? audioLease.close()
      models.release(modelLease)
      finish(.failure(.audioUnreadable))
      return
    }
    try? audioLease.close()
    models.release(modelLease)
    switch outcome {
    case .success(let payload): finish(.success(payload))
    case .failure(let failure): finish(.failure(failure))
    case .waiting: finish(.waiting(.protectedDataUnavailable))
    }
  }

  func cancel() {
    cancellation.cancel()
    task?.cancel()
  }

  private func finish(_ result: TranscriptionResult) {
    guard !finished else { return }
    finished = true
    completion(result)
  }

  // swiftlint:disable:next function_parameter_count
  nonisolated private static func perform(
    request: TranscriptionRequest, audioURL: URL, sourceDigest: String,
    modelLease: CohereModelLease, runtime: any CohereRuntimeRunning,
    cancellation: CohereCancellationFlag
  ) -> CohereAttemptOutcome {
    do {
      let samples = try CohereAudioConversion.convert(
        url: audioURL, cancelled: cancellation.isCancelled)
      let plan = try CohereChunkPlanner.plan(samples: samples)
      guard let languageHint = request.settings.values["languageHint"],
        languageHint == (request.language == .english ? "en" : "ko"),
        request.settings.values["settingsRevision"] == "2",
        request.settings.values["resolvedLocale"] == request.language.rawValue,
        request.settings.values["backend"] == "metal",
        request.settings.values["runtime"] == CohereRuntimeProvenance.identity,
        request.settings.values["installedIdentity"] == modelLease.identity,
        let quantization = request.settings.values["quantization"],
        modelLease.identity
          == (quantization == "Q5_K_M"
            ? CohereTrustedModel.productionQ5.installationIdentity
            : CohereTrustedModel.productionQ4.installationIdentity)
      else { return .failure(.inference) }
      let chunks = try runtime.transcribe(
        modelURL: modelLease.url, samples: samples, plan: plan, languageHint: languageHint,
        cancellation: cancellation)
      let text = try CohereSeamAssembler.assemble(plan: plan, transcripts: chunks)
      guard !cancellation.isCancelled() else { return .failure(.cancelled) }
      guard let locale = request.settings.values["resolvedLocale"],
        let operatingSystem = request.settings.values["operatingSystemVersion"]
      else { return .failure(.inference) }
      return .success(
        TranscriptionPayload(
          text: text, sourceDigest: sourceDigest, resolvedLocale: locale,
          runtime: CohereRuntimeProvenance.identity, conversion: CohereAudioConversion.identity,
          operatingSystemVersion: operatingSystem))
    } catch CohereAudioConversion.Failure.cancelled, CohereRuntimeFailure.cancelled {
      return .failure(.cancelled)
    } catch CohereAudioConversion.Failure.invalidInput {
      return .failure(.audioUnreadable)
    } catch CohereSeamAssembler.Failure.tooLarge {
      return .failure(.outputTooLarge)
    } catch CohereSeamAssembler.Failure.unusable, CohereChunkPlanner.Failure.empty {
      return .failure(.unusableText)
    } catch {
      return .failure(.inference)
    }
  }
}

@MainActor
private final class FinishedCohereWork: TranscriptionWork {
  func cancel() {}
}

// swiftlint:enable trailing_comma
