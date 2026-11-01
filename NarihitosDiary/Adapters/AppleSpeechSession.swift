import AVFAudio
import CoreMedia
import Foundation
import Speech

@MainActor
protocol AppleSpeechAudioLease: AnyObject {
  var digest: String { get }
  func openAudioFile() throws -> AVAudioFile
  func verifyUnchanged() throws
  func close() throws
}

@MainActor
protocol AppleSpeechAudioSource {
  func openForSpeech(job: QueueJob) throws -> any AppleSpeechAudioLease
}

@MainActor
protocol AppleSpeechSession: AnyObject {
  func analyze(_ lease: any AppleSpeechAudioLease) async throws -> CMTime?
  func finalize(through time: CMTime) async throws
  func results() async throws -> String
  func cancelAndFinish() async
}

@MainActor
protocol AppleSpeechSessionFactory {
  func make(locale: String) -> any AppleSpeechSession
}

@MainActor
struct SystemAppleSpeechSessionFactory: AppleSpeechSessionFactory {
  func make(locale: String) -> any AppleSpeechSession {
    SystemAppleSpeechSession(locale: locale)
  }
}

@MainActor
private final class SystemAppleSpeechSession: AppleSpeechSession {
  private let transcriber: SpeechTranscriber
  private let analyzer: SpeechAnalyzer
  private var file: AVAudioFile?

  init(locale: String) {
    let transcriber = SpeechTranscriber(locale: Locale(identifier: locale), preset: .transcription)
    self.transcriber = transcriber
    analyzer = SpeechAnalyzer(modules: [transcriber])
  }

  func analyze(_ lease: any AppleSpeechAudioLease) async throws -> CMTime? {
    let file = try lease.openAudioFile()
    self.file = file
    try lease.verifyUnchanged()
    return try await analyzer.analyzeSequence(from: file)
  }

  func finalize(through time: CMTime) async throws {
    try await analyzer.finalizeAndFinish(through: time)
  }

  func results() async throws -> String {
    var collector = TranscriptionText()
    for try await result in transcriber.results {
      try Task.checkCancellation()
      try collector.append(String(result.text.characters), isFinal: result.isFinal)
    }
    return try collector.finish()
  }

  func cancelAndFinish() async {
    await analyzer.cancelAndFinishNow()
    file = nil
  }
}
