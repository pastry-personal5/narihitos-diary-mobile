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
  private let models: CohereModelManager
  private let runtime: any CohereRuntimeRunning

  init(
    store: any QueueStorePort, audio: any CohereAudioSource, models: CohereModelManager,
    runtime: any CohereRuntimeRunning = NativeCohereRuntime()
  ) {
    self.store = store
    self.audio = audio
    self.models = models
    self.runtime = runtime
  }

  func readiness(for _: CaptureLanguage) -> TranscriptionReadiness {
    if case .ready = models.readiness { return .ready }
    return .waiting(.cohereNotInstalled)
  }

  func preflight(for language: CaptureLanguage) async -> TranscriptionPreflight {
    guard case .ready(let identity) = await models.refresh(),
      identity == models.descriptor.installationIdentity
    else {
      return TranscriptionPreflight(
        readiness: .waiting(.cohereNotInstalled), effectiveValues: [:])
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
      request.settings.values["installedIdentity"] == models.descriptor.installationIdentity
    else {
      completion(.failure(.inference))
      return FinishedCohereWork()
    }
    let attempt = CohereTranscriptionAttempt(
      request: request, job: job, audio: audio, models: models, runtime: runtime,
      completion: completion)
    attempt.start()
    return attempt
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
    let modelLease: CohereModelLease
    do {
      modelLease = try models.acquireLease()
    } catch CohereModelFailure.protectedDataUnavailable {
      finish(.waiting(.protectedDataUnavailable))
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
    task = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        Self.perform(
          request: request, audioURL: audioURL, sourceDigest: sourceDigest,
          modelLease: modelLease, runtime: runtime, cancellation: cancellation)
      }
      let outcome = await worker.value
      guard let self else { return }
      do { try audioLease.verifyUnchanged() } catch {
        try? audioLease.close()
        self.models.release(modelLease)
        self.finish(.failure(.audioUnreadable))
        return
      }
      try? audioLease.close()
      self.models.release(modelLease)
      switch outcome {
      case .success(let payload): self.finish(.success(payload))
      case .failure(let failure): self.finish(.failure(failure))
      case .waiting: self.finish(.waiting(.protectedDataUnavailable))
      }
    }
  }

  func cancel() { cancellation.cancel() }

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
        request.settings.values["backend"] == "metal",
        request.settings.values["runtime"] == CohereRuntimeProvenance.identity,
        request.settings.values["installedIdentity"] == modelLease.identity
      else { return .failure(.inference) }
      let chunks = try runtime.transcribe(
        modelURL: modelLease.url, samples: samples, plan: plan, languageHint: languageHint,
        cancellation: cancellation)
      let text = try CohereSeamAssembler.assemble(plan: plan, transcripts: chunks)
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
