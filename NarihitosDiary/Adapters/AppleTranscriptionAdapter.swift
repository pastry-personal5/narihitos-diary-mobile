import Foundation

// swiftlint:disable trailing_comma

@MainActor
final class AppleTranscriptionAdapter: AsynchronousTranscriptionReadiness {
  let descriptor = TranscriptionDescriptor(
    id: TranscriptionMethodIdentifiers.apple, supportedLanguages: [.english, .korean],
    requiresMonoAAC: true)
  private let store: any QueueStorePort
  private let audio: any AppleSpeechAudioSource
  private let readinessSource: any AppleTranscriptionReadinessSource
  private let sessions: any AppleSpeechSessionFactory

  init(
    store: any QueueStorePort, audio: any AppleSpeechAudioSource,
    readinessSource: any AppleTranscriptionReadinessSource,
    sessions: any AppleSpeechSessionFactory = SystemAppleSpeechSessionFactory()
  ) {
    self.store = store
    self.audio = audio
    self.readinessSource = readinessSource
    self.sessions = sessions
  }

  func readiness(for _: CaptureLanguage) -> TranscriptionReadiness {
    .waiting(.appleNotReady)
  }

  func preflight(for language: CaptureLanguage) async -> TranscriptionPreflight {
    guard case .ready(let locale) = await readinessSource.status(for: language) else {
      return TranscriptionPreflight(readiness: .waiting(.appleNotReady), effectiveValues: [:])
    }
    return TranscriptionPreflight(
      readiness: .ready,
      effectiveValues: [
        "resolvedLocale": locale,
        "operatingSystemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
  }

  func start(
    _ request: TranscriptionRequest,
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) -> any TranscriptionWork {
    guard let job = try? store.jobs().first(where: { $0.id == request.jobID }),
      job.state == .transcribing, job.attemptID == request.attemptID,
      job.attemptGeneration == request.generation, job.selectedMethodID == descriptor.id
    else {
      completion(.failure(.inference))
      return FinishedTranscriptionWork()
    }
    let attempt = AppleSpeechAttempt(
      request: request, job: job, audio: audio, readiness: readinessSource,
      sessions: sessions,
      completion: completion)
    attempt.start()
    return attempt
  }
}

@MainActor
private final class FinishedTranscriptionWork: TranscriptionWork {
  func cancel() {}
}

// swiftlint:enable trailing_comma
