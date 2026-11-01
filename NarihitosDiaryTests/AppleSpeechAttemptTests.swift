import AVFAudio
import CoreMedia
import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
struct AppleSpeechAttemptTests {
  @Test func cancellationWaitsForReadinessToRelinquish() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "speech-attempt-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try AttemptFixture()
    let readiness = SuspendedAppleReadiness()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job,
      audio: VerifiedCaptureAudioSource(files: CapturePrivateFiles(root: root)),
      readiness: readiness, completion: { results.values.append($0) })
    work.start()
    while readiness.pending == nil { await Task.yield() }
    work.cancel()
    #expect(results.values.isEmpty)
    readiness.pending?.resume(returning: .ready(resolvedLocale: "en-US"))
    readiness.pending = nil
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.failure(.cancelled)])
  }

  @Test func missingAssetWaitsWithoutOpeningAudio() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "speech-attempt-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try AttemptFixture()
    let readiness = SuspendedAppleReadiness()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job,
      audio: VerifiedCaptureAudioSource(files: CapturePrivateFiles(root: root)),
      readiness: readiness, completion: { results.values.append($0) })
    work.start()
    while readiness.pending == nil { await Task.yield() }
    readiness.pending?.resume(returning: .downloadable)
    readiness.pending = nil
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.waiting(.appleNotReady)])
  }

  @Test func unreadableAudioFailsWithoutStartingARecognizer() async throws {
    let fixture = try AttemptFixture()
    let session = ControlledSpeechSession()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job, audio: UnreadableSpeechAudio(),
      readiness: ImmediateAppleReadiness(), sessions: ControlledSessionFactory(session: session),
      completion: { results.values.append($0) })
    work.start()
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.failure(.audioUnreadable)])
    #expect(session.input == nil)
    #expect(session.output == nil)
  }

  @Test func protectedAudioWaitsWithoutStartingARecognizer() async throws {
    let fixture = try AttemptFixture()
    let session = ControlledSpeechSession()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job, audio: ProtectedSpeechAudio(),
      readiness: ImmediateAppleReadiness(), sessions: ControlledSessionFactory(session: session),
      completion: { results.values.append($0) })
    work.start()
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.waiting(.protectedDataUnavailable)])
    #expect(session.input == nil)
    #expect(session.output == nil)
  }

  @Test func finalizesThroughLastSampleAndWaitsForTeardownBeforeSuccess() async throws {
    let fixture = try AttemptFixture()
    let session = ControlledSpeechSession()
    let audio = ControlledSpeechAudio()
    let readiness = ImmediateAppleReadiness()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job, audio: audio, readiness: readiness,
      sessions: ControlledSessionFactory(session: session),
      completion: { results.values.append($0) })
    work.start()
    while session.input == nil || session.output == nil { await Task.yield() }
    let lastSample = CMTime(value: 123, timescale: 44_100)
    session.input?.resume(returning: lastSample)
    session.input = nil
    while session.finalization == nil { await Task.yield() }
    #expect(CMTimeCompare(try #require(session.finalizedThrough), lastSample) == 0)
    session.finalization?.resume()
    session.finalization = nil
    session.output?.resume(returning: "A diary entry.")
    session.output = nil
    while session.stop == nil { await Task.yield() }
    #expect(results.values.isEmpty)
    #expect(!audio.lease.closed)
    session.allowStop()
    while results.values.isEmpty { await Task.yield() }
    #expect(audio.lease.closed)
    guard case .success(let payload) = try #require(results.values.first) else {
      Issue.record("Expected a successful payload")
      return
    }
    #expect(payload.text == "A diary entry.")
    #expect(payload.sourceDigest == audio.lease.digest)
    #expect(payload.resolvedLocale == "en-US")
    #expect(payload.runtime == "apple-speech-analyzer")
    #expect(payload.conversion == "ndm.apple-speech.av-audio-file-v1")
    #expect(payload.operatingSystemVersion == "27.0")
    work.start()
    await Task.yield()
    #expect(results.values.count == 1)
  }

  @Test func cancellationDuringFinalizationWaitsForAllWorkAndClosesAudio() async throws {
    let fixture = try AttemptFixture()
    let session = ControlledSpeechSession()
    let audio = ControlledSpeechAudio()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job, audio: audio,
      readiness: ImmediateAppleReadiness(),
      sessions: ControlledSessionFactory(session: session),
      completion: { results.values.append($0) })
    work.start()
    while session.input == nil || session.output == nil { await Task.yield() }
    session.input?.resume(returning: CMTime(value: 1, timescale: 1))
    session.input = nil
    while session.finalization == nil { await Task.yield() }
    work.cancel()
    while session.stop == nil { await Task.yield() }
    #expect(results.values.isEmpty)
    #expect(!audio.lease.closed)
    session.allowStop()
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.failure(.cancelled)])
    #expect(audio.lease.closed)
    #expect(session.stopCount == 1)
  }

  @Test func oversizedResultCancelsInputAndReportsBoundedFailure() async throws {
    let fixture = try AttemptFixture()
    let session = ControlledSpeechSession()
    let audio = ControlledSpeechAudio()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job, audio: audio,
      readiness: ImmediateAppleReadiness(),
      sessions: ControlledSessionFactory(session: session),
      completion: { results.values.append($0) })
    work.start()
    while session.input == nil || session.output == nil { await Task.yield() }
    session.output?.resume(throwing: TranscriptionText.Failure.tooLarge)
    session.output = nil
    while session.stop == nil { await Task.yield() }
    #expect(results.values.isEmpty)
    session.allowStop()
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.failure(.outputTooLarge)])
    #expect(audio.lease.closed)
    #expect(session.stopCount == 1)
  }

  @Test func resultStreamFailureIsSanitizedAfterTeardown() async throws {
    let fixture = try AttemptFixture()
    let session = ControlledSpeechSession()
    let audio = ControlledSpeechAudio()
    let results = AttemptResults()
    let work = AppleSpeechAttempt(
      request: fixture.request, job: fixture.job, audio: audio,
      readiness: ImmediateAppleReadiness(),
      sessions: ControlledSessionFactory(session: session),
      completion: { results.values.append($0) })
    work.start()
    while session.input == nil || session.output == nil { await Task.yield() }
    session.output?.resume(throwing: ControlledSessionFailure.failed)
    session.output = nil
    while session.stop == nil { await Task.yield() }
    #expect(results.values.isEmpty)
    session.allowStop()
    while results.values.isEmpty { await Task.yield() }
    #expect(results.values == [.failure(.inference)])
    #expect(audio.lease.closed)
  }

  @Test func inputFailureAndUnusableTextRetainTypedOutcomes() async throws {
    for inputFails in [true, false] {
      let fixture = try AttemptFixture()
      let session = ControlledSpeechSession()
      let audio = ControlledSpeechAudio()
      let results = AttemptResults()
      let work = AppleSpeechAttempt(
        request: fixture.request, job: fixture.job, audio: audio,
        readiness: ImmediateAppleReadiness(), sessions: ControlledSessionFactory(session: session),
        completion: { results.values.append($0) })
      work.start()
      while session.input == nil || session.output == nil { await Task.yield() }
      if inputFails {
        session.input?.resume(throwing: ControlledSessionFailure.failed)
        session.input = nil
      } else {
        session.output?.resume(throwing: TranscriptionText.Failure.unusable)
        session.output = nil
      }
      while session.stop == nil { await Task.yield() }
      #expect(results.values.isEmpty)
      session.allowStop()
      while results.values.isEmpty { await Task.yield() }
      #expect(results.values == [.failure(inputFails ? .inference : .unusableText)])
      #expect(audio.lease.closed)
    }
  }

  @Test func queueTimeoutKeepsWorkerUntilAppleSessionRelinquishes() async throws {
    let first = try makeReceipt(start: 1, language: .english)
    let second = try makeReceipt(start: 2, language: .korean)
    let store = MemoryQueueStore()
    let receipts = MemoryReceiptSource([first])
    let session = ControlledSpeechSession()
    let audio = ControlledSpeechAudio()
    let registry = TranscriptionMethodRegistry()
    let apple = AppleTranscriptionAdapter(
      store: store, audio: audio, readinessSource: ImmediateAppleReadiness(),
      sessions: ControlledSessionFactory(session: session))
    let next = FakeTranscriber(id: "next", readiness: .ready)
    registry.register(apple)
    registry.register(next)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = apple.descriptor.id
    settings.methods[.korean] = next.descriptor.id
    let candidates = MemoryCandidateStore()
    let queue = ProcessingQueueCoordinator(
      store: store, receipts: receipts, identity: FakeInstallationIdentity(), settings: settings,
      registry: registry, candidates: candidates, timeout: .milliseconds(100))
    queue.activate()
    while session.input == nil || session.output == nil { await Task.yield() }
    receipts.values[second.id.description] = second
    queue.captureSettled()
    while session.stop == nil { await Task.yield() }
    #expect(store.values[first.id.description]?.state == .failed)
    #expect(next.requests.isEmpty)
    #expect(!audio.lease.closed)
    session.allowStop()
    while next.requests.isEmpty { await Task.yield() }
    #expect(audio.lease.closed)
    #expect(candidates.published.isEmpty)
    #expect(next.requests.map(\.jobID) == [second.id.description])
    #expect(store.values[first.id.description]?.reason == ProcessingQueueCoordinator.timeoutReason)
  }

  @Test func confirmedRemovalWaitsForAppleSessionBeforeStartingAnotherJob() async throws {
    let first = try makeReceipt(start: 1, language: .english)
    let second = try makeReceipt(start: 2, language: .korean)
    let store = MemoryQueueStore()
    let receipts = MemoryReceiptSource([first])
    let session = ControlledSpeechSession()
    let audio = ControlledSpeechAudio()
    let registry = TranscriptionMethodRegistry()
    let apple = AppleTranscriptionAdapter(
      store: store, audio: audio, readinessSource: ImmediateAppleReadiness(),
      sessions: ControlledSessionFactory(session: session))
    let next = FakeTranscriber(id: "next", readiness: .ready)
    registry.register(apple)
    registry.register(next)
    let settings = FakeTranscriptionSettings()
    settings.methods[.english] = apple.descriptor.id
    settings.methods[.korean] = next.descriptor.id
    let candidates = MemoryCandidateStore()
    let queue = ProcessingQueueCoordinator(
      store: store, receipts: receipts, identity: FakeInstallationIdentity(), settings: settings,
      registry: registry, candidates: candidates)
    queue.activate()
    while session.input == nil || session.output == nil { await Task.yield() }
    receipts.values[second.id.description] = second
    queue.captureSettled()
    queue.remove(jobID: first.id.description)
    while session.stop == nil { await Task.yield() }
    #expect(store.values[first.id.description]?.state == .cancelling)
    #expect(receipts.removed.isEmpty)
    #expect(next.requests.isEmpty)
    session.allowStop()
    while next.requests.isEmpty { await Task.yield() }
    #expect(receipts.removed == [first.id.description])
    #expect(candidates.published.isEmpty)
    #expect(audio.lease.closed)
  }

  private func makeReceipt(start: Int, language: CaptureLanguage) throws -> QueueReceipt {
    QueueReceipt(
      id: try WorkspaceID(String(format: "00000000-0000-4000-8000-%012d", start)),
      startedAt: Date(timeIntervalSince1970: TimeInterval(start)), language: language,
      destinationReference: UUID(), installationBinding: "current",
      inspection: CaptureInspection(
        byteCount: 1_024, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1))
  }
}

private enum ControlledSessionFailure: Error { case failed }

@MainActor
private struct ImmediateAppleReadiness: AppleTranscriptionReadinessSource {
  func status(for _: CaptureLanguage) async -> AppleTranscriptionAssetState {
    .ready(resolvedLocale: "en-US")
  }
}

@MainActor
private struct UnreadableSpeechAudio: AppleSpeechAudioSource {
  func openForSpeech(job _: QueueJob) throws -> any AppleSpeechAudioLease {
    throw AudioFingerprintFailure.invalidAudio
  }
}

@MainActor
private struct ProtectedSpeechAudio: AppleSpeechAudioSource {
  func openForSpeech(job _: QueueJob) throws -> any AppleSpeechAudioLease {
    throw AudioFingerprintFailure.protectedDataUnavailable
  }
}

@MainActor
private final class ControlledSpeechAudio: AppleSpeechAudioSource {
  let lease = ControlledAudioLease()
  func openForSpeech(job _: QueueJob) throws -> any AppleSpeechAudioLease { lease }
}

@MainActor
private final class ControlledAudioLease: AppleSpeechAudioLease {
  let digest = String(repeating: "a", count: 64)
  var closed = false
  func openAudioFile() throws -> AVAudioFile { throw AudioFingerprintFailure.invalidAudio }
  func verifyUnchanged() throws {}
  func close() throws { closed = true }
}

@MainActor
private struct ControlledSessionFactory: AppleSpeechSessionFactory {
  let session: ControlledSpeechSession
  func make(locale _: String) -> any AppleSpeechSession { session }
}

@MainActor
private final class ControlledSpeechSession: AppleSpeechSession {
  var input: CheckedContinuation<CMTime?, Error>?
  var finalization: CheckedContinuation<Void, Error>?
  var output: CheckedContinuation<String, Error>?
  var stop: CheckedContinuation<Void, Never>?
  var finalizedThrough: CMTime?
  var stopCount = 0

  func analyze(_: any AppleSpeechAudioLease) async throws -> CMTime? {
    try await withCheckedThrowingContinuation { input = $0 }
  }

  func finalize(through time: CMTime) async throws {
    finalizedThrough = time
    try await withCheckedThrowingContinuation { finalization = $0 }
  }

  func results() async throws -> String {
    try await withCheckedThrowingContinuation { output = $0 }
  }

  func cancelAndFinish() async {
    stopCount += 1
    await withCheckedContinuation { stop = $0 }
    input?.resume(throwing: CancellationError())
    input = nil
    finalization?.resume(throwing: CancellationError())
    finalization = nil
    output?.resume(throwing: CancellationError())
    output = nil
  }

  func allowStop() {
    stop?.resume()
    stop = nil
  }
}

@MainActor
private final class SuspendedAppleReadiness: AppleTranscriptionReadinessSource {
  var pending: CheckedContinuation<AppleTranscriptionAssetState, Never>?
  func status(for _: CaptureLanguage) async -> AppleTranscriptionAssetState {
    await withCheckedContinuation { pending = $0 }
  }
}

@MainActor
private final class AttemptResults {
  var values: [TranscriptionResult] = []
}

private struct AttemptFixture {
  let job: QueueJob
  let request: TranscriptionRequest

  init() throws {
    let receipt = QueueReceipt(
      id: try WorkspaceID("00000000-0000-4000-8000-000000000001"),
      startedAt: Date(timeIntervalSince1970: 1), language: .english,
      destinationReference: UUID(), installationBinding: "current",
      inspection: CaptureInspection(
        byteCount: 1_024, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1))
    var claim = QueueJob(receipt: receipt, state: .transcribing)
    claim.attemptID = UUID()
    claim.attemptGeneration = 1
    job = claim
    let settings = EffectiveTranscriptionSettings(
      values: ["resolvedLocale": "en-US", "operatingSystemVersion": "27.0"],
      modelIdentity: nil, conversionIdentity: "ndm.apple-speech.av-audio-file-v1")
    request = TranscriptionRequest(
      jobID: claim.id, attemptID: claim.attemptID!, generation: 1, language: .english,
      settings: settings, destinationRevision: 0, bodyRevision: 0)
  }
}
