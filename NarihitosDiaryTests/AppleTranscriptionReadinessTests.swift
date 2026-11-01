import Testing

@testable import NarihitosDiary

@MainActor
struct AppleTranscriptionReadinessTests {
  @Test func platformStatesRemainDistinctAndUseOnlyRequestedLanguage() async {
    let platform = FakeAppleSpeechPlatform()
    let source = AppleSpeechReadinessSource(platform: platform)
    platform.isAvailable = false
    #expect(await source.status(for: .english) == .unavailable)
    #expect(platform.requests.isEmpty)
    platform.isAvailable = true
    platform.locale = nil
    #expect(await source.status(for: .korean) == .unsupported)
    #expect(platform.requests == [.korean])
    platform.locale = "ko-KR"
    platform.module = .downloadable
    #expect(await source.status(for: .korean) == .downloadable)
    platform.module = .downloading
    #expect(await source.status(for: .korean) == .downloading)
    platform.module = .installed
    #expect(await source.status(for: .korean) == .ready(resolvedLocale: "ko-KR"))
    platform.module = .unavailable
    #expect(await source.status(for: .korean) == .temporarilyUnavailable)
    platform.module = .unsupported
    #expect(await source.status(for: .korean) == .unsupported)
  }

  @Test func newerRefreshWinsOverLateCompletion() async {
    let source = SuspendedReadinessSource()
    let readiness = AppleTranscriptionReadiness(source: source)
    let first = Task { await readiness.refresh(.english) }
    while source.pending.count < 1 { await Task.yield() }
    let second = Task { await readiness.refresh(.english) }
    while source.pending.count < 2 { await Task.yield() }
    source.pending[1].resume(returning: .downloadable)
    _ = await second.value
    source.pending[0].resume(returning: .ready(resolvedLocale: "en-US"))
    #expect(await first.value == nil)
    #expect(readiness.states[.english] == .downloadable)
  }

  @Test func lifecycleInvalidationDiscardsInFlightResults() async {
    let source = SuspendedReadinessSource()
    let readiness = AppleTranscriptionReadiness(source: source)
    let refresh = Task { await readiness.refresh(.korean) }
    while source.pending.isEmpty { await Task.yield() }
    readiness.invalidate()
    source.pending[0].resume(returning: .ready(resolvedLocale: "ko-KR"))
    #expect(await refresh.value == nil)
    #expect(readiness.states.isEmpty)
  }
}

@MainActor
private final class FakeAppleSpeechPlatform: AppleSpeechReadinessPlatform {
  var isAvailable = true
  var locale: String? = "en-US"
  var module: AppleSpeechModuleStatus = .downloadable
  var requests: [CaptureLanguage] = []
  func resolve(_ language: CaptureLanguage) async -> String? {
    requests.append(language)
    return locale
  }
  func status(locale _: String) async -> AppleSpeechModuleStatus { module }
}

@MainActor
private final class SuspendedReadinessSource: AppleTranscriptionReadinessSource {
  var pending: [CheckedContinuation<AppleTranscriptionAssetState, Never>] = []

  func status(for _: CaptureLanguage) async -> AppleTranscriptionAssetState {
    await withCheckedContinuation { pending.append($0) }
  }
}
