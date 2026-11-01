import Foundation

/// One instance owns one analyzer, its input, result stream, and audio lease.
@MainActor
final class AppleSpeechAttempt: TranscriptionWork {
  private let request: TranscriptionRequest
  private let job: QueueJob
  private let audio: any AppleSpeechAudioSource
  private let readiness: any AppleTranscriptionReadinessSource
  private let sessions: any AppleSpeechSessionFactory
  private let completion: @MainActor (TranscriptionResult) -> Void
  private var task: Task<Void, Never>?
  private var resultTask: Task<String, Error>?
  private var cancellationTask: Task<Void, Never>?
  private var session: (any AppleSpeechSession)?
  private var teardown: AppleAnalyzerTeardown?
  private var audioLease: (any AppleSpeechAudioLease)?
  private var cancelled = false
  private var started = false

  init(
    request: TranscriptionRequest, job: QueueJob, audio: any AppleSpeechAudioSource,
    readiness: any AppleTranscriptionReadinessSource,
    sessions: any AppleSpeechSessionFactory = SystemAppleSpeechSessionFactory(),
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) {
    self.request = request
    self.job = job
    self.audio = audio
    self.readiness = readiness
    self.sessions = sessions
    self.completion = completion
  }

  func start() {
    guard !started else { return }
    started = true
    task = Task { [self] in
      let result = await run()
      await relinquish()
      completion(cancelled ? .failure(.cancelled) : result)
      task = nil
    }
    if cancelled { task?.cancel() }
  }

  func cancel() {
    guard !cancelled else { return }
    cancelled = true
    task?.cancel()
    resultTask?.cancel()
    cancelAnalyzer()
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private func run() async -> TranscriptionResult {
    do {
      try Task.checkCancellation()
      guard case .ready(let resolved) = await readiness.status(for: request.language),
        request.settings.values["resolvedLocale"] == resolved,
        let operatingSystemVersion = request.settings.values["operatingSystemVersion"]
      else { return .waiting(.appleNotReady) }
      try Task.checkCancellation()
      let lease = try audio.openForSpeech(job: job)
      audioLease = lease
      try lease.verifyUnchanged()
      let session = sessions.make(locale: resolved)
      self.session = session
      let teardown = AppleAnalyzerTeardown(session: session)
      self.teardown = teardown
      try Task.checkCancellation()
      let results = Task { () throws -> String in
        do {
          return try await session.results()
        } catch {
          await teardown.stop()
          throw error
        }
      }
      resultTask = results
      guard let lastSample = try await session.analyze(lease) else {
        return .failure(.unusableText)
      }
      try await session.finalize(through: lastSample)
      let text = try await results.value
      try Task.checkCancellation()
      try lease.verifyUnchanged()
      return .success(
        TranscriptionPayload(
          text: text, sourceDigest: lease.digest, resolvedLocale: resolved,
          runtime: "apple-speech-analyzer", conversion: "ndm.apple-speech.av-audio-file-v1",
          operatingSystemVersion: operatingSystemVersion))
    } catch AudioFingerprintFailure.protectedDataUnavailable {
      return .waiting(.protectedDataUnavailable)
    } catch AudioFingerprintFailure.invalidAudio {
      return .failure(.audioUnreadable)
    } catch TranscriptionText.Failure.unusable {
      return .failure(.unusableText)
    } catch TranscriptionText.Failure.tooLarge {
      return .failure(.outputTooLarge)
    } catch {
      cancelAnalyzer()
      resultTask?.cancel()
      await cancellationTask?.value
      if let resultTask {
        do {
          _ = try await resultTask.value
        } catch TranscriptionText.Failure.tooLarge {
          return .failure(.outputTooLarge)
        } catch TranscriptionText.Failure.unusable {
          return .failure(.unusableText)
        } catch {
          // Input and stream failures have the same sanitized outcome.
        }
      }
      return .failure(cancelled ? .cancelled : .inference)
    }
  }

  private func cancelAnalyzer() {
    guard cancellationTask == nil, let teardown else { return }
    cancellationTask = Task { await teardown.stop() }
  }

  private func relinquish() async {
    // Calling cancel after a completed finalization is harmless and guarantees a
    // failed input or stream does not leave the analyzer holding the worker.
    cancelAnalyzer()
    resultTask?.cancel()
    await cancellationTask?.value
    _ = try? await resultTask?.value
    resultTask = nil
    session = nil
    teardown = nil
    try? audioLease?.close()
    audioLease = nil
  }
}

@MainActor
private final class AppleAnalyzerTeardown {
  private let session: any AppleSpeechSession
  private var task: Task<Void, Never>?

  init(session: any AppleSpeechSession) { self.session = session }

  func stop() async {
    if let task {
      await task.value
      return
    }
    let session = session
    let task = Task { await session.cancelAndFinish() }
    self.task = task
    await task.value
  }
}
