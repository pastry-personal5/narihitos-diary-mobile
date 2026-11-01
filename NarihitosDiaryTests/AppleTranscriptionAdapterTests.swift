import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct AppleTranscriptionAdapterTests {
  @Test func descriptorAndPreflightUseOnlyTheExplicitLanguage() async {
    let root = FileManager.default.temporaryDirectory.appending(path: "apple-adapter-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = AdapterReadinessSource()
    let adapter = AppleTranscriptionAdapter(
      store: MemoryQueueStore(),
      audio: VerifiedCaptureAudioSource(files: CapturePrivateFiles(root: root)),
      readinessSource: source)
    #expect(adapter.descriptor.id == "ndm.transcription.apple")
    #expect(adapter.descriptor.supportedLanguages == [.english, .korean])
    #expect(adapter.descriptor.requiresMonoAAC)
    let result = await adapter.preflight(for: .korean)
    #expect(source.requests == [.korean])
    #expect(result.readiness == .ready)
    #expect(result.effectiveValues["resolvedLocale"] == "ko-KR")
    #expect(result.effectiveValues["operatingSystemVersion"]?.isEmpty == false)
    source.state = .downloading
    let unavailable = await adapter.preflight(for: .english)
    #expect(unavailable.readiness == .waiting(.appleNotReady))
    #expect(unavailable.effectiveValues.isEmpty)
  }
}

@MainActor
private final class AdapterReadinessSource: AppleTranscriptionReadinessSource {
  var state: AppleTranscriptionAssetState = .ready(resolvedLocale: "ko-KR")
  var requests: [CaptureLanguage] = []
  func status(for language: CaptureLanguage) async -> AppleTranscriptionAssetState {
    requests.append(language)
    return state
  }
}
