import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct AppleAssetInstallationTests {
  @Test func downloadableAssetCanBePreparedWithoutByteEstimate() async {
    let installer = AppleAssetInstaller(backend: FakeAppleInstallationBackend())
    #expect(
      await installer.prepare(.english)
        == .downloadable(AppleAssetInstallPlan(language: .english, resolvedLocale: "en-US")))
  }

  @Test func onlyDownloadableAssetsOfferAnInstallPlan() async {
    let backend = FakeAppleInstallationBackend()
    let installer = AppleAssetInstaller(backend: backend)
    backend.state = .ready(resolvedLocale: "en-US")
    #expect(await installer.prepare(.english) == .ready)
    backend.state = .downloading
    #expect(await installer.prepare(.english) == .downloading)
    backend.state = .unsupported
    #expect(await installer.prepare(.english) == .unsupported)
    #expect(backend.reservations.isEmpty)
    #expect(backend.requestCount == 0)
  }

  @Test func nilRequestRequiresActualInstalledStatus() async throws {
    let backend = FakeAppleInstallationBackend()
    backend.requestValue = nil
    let installer = AppleAssetInstaller(backend: backend)
    let plan = try await preparedPlan(installer, language: .korean)
    #expect(await installer.install(plan) == .failed)
    #expect(backend.reservations == ["ko-KR"])
    backend.onRequest = { backend.state = .ready(resolvedLocale: "ko-KR") }
    #expect(await installer.install(plan) == .ready)
  }

  @Test func installedButUnreservedAssetIsSetUpBeforeBecomingReady() async throws {
    let backend = FakeAppleInstallationBackend()
    backend.state = .reservationRequired
    backend.requestValue = nil
    backend.onRequest = { backend.state = .ready(resolvedLocale: "en-US") }
    let installer = AppleAssetInstaller(backend: backend)

    let plan = try await preparedPlan(installer, language: .english)
    #expect(await installer.install(plan) == .ready)
    #expect(backend.reservations == ["en-US"])
    #expect(backend.requestCount == 1)
  }

  @Test func sameLanguageInstallsCoalesceAndRecheckStatus() async throws {
    let backend = FakeAppleInstallationBackend()
    let installer = AppleAssetInstaller(backend: backend)
    let plan = try await preparedPlan(installer, language: .english)
    let first = Task { await installer.install(plan) }
    while backend.requestValue?.pending == nil { await Task.yield() }
    let second = Task { await installer.install(plan) }
    await Task.yield()
    #expect(backend.reservations == ["en-US"])
    #expect(backend.requestCount == 1)
    backend.state = .ready(resolvedLocale: "en-US")
    backend.requestValue?.pending?.resume()
    backend.requestValue?.pending = nil
    #expect(await first.value == .ready)
    #expect(await second.value == .ready)
  }

  @Test func capacityFailureDoesNotRequestOrReleaseAnotherLocale() async throws {
    let backend = FakeAppleInstallationBackend()
    backend.reservationFailure = .reservationCapacity
    let installer = AppleAssetInstaller(backend: backend)
    let plan = try await preparedPlan(installer, language: .english)
    #expect(await installer.install(plan) == .reservationCapacity)
    #expect(backend.requestCount == 0)
    #expect(backend.reservations == ["en-US"])
  }

  @Test func cancellationDoesNotPretendSystemDownloadStopped() async throws {
    let backend = FakeAppleInstallationBackend()
    backend.requestValue?.fractionCompleted = 2
    let installer = AppleAssetInstaller(backend: backend)
    let plan = try await preparedPlan(installer, language: .english)
    let task = Task { await installer.install(plan) }
    while backend.requestValue?.pending == nil || installer.progress[.english] == nil {
      await Task.yield()
    }
    #expect(installer.progress[.english] == 1)
    installer.cancel(.english)
    #expect(backend.requestValue?.pending != nil)
    backend.state = .downloading
    backend.requestValue?.pending?.resume()
    backend.requestValue?.pending = nil
    #expect(await task.value == .downloading)
    #expect(installer.progress[.english] == nil)
  }

  @Test func cancellationAfterReservationDoesNotStartADownload() async throws {
    let backend = FakeAppleInstallationBackend()
    backend.suspendReservation = true
    let installer = AppleAssetInstaller(backend: backend)
    let plan = try await preparedPlan(installer, language: .english)
    let task = Task { await installer.install(plan) }
    while backend.reservationContinuation == nil { await Task.yield() }
    installer.cancel(.english)
    backend.reservationContinuation?.resume()
    backend.reservationContinuation = nil
    #expect(await task.value == .cancelled)
    #expect(backend.reservations == ["en-US"])
    #expect(backend.requestCount == 0)
  }

  private func preparedPlan(
    _ installer: AppleAssetInstaller, language: CaptureLanguage
  ) async throws -> AppleAssetInstallPlan {
    guard case .downloadable(let plan) = await installer.prepare(language) else {
      throw QueueStoreFailure.unavailable
    }
    return plan
  }
}

@MainActor
private final class FakeAppleInstallationBackend: AppleAssetInstallationBackend {
  var state: AppleTranscriptionAssetState = .downloadable
  var reservations: [String] = []
  var requestCount = 0
  var reservationFailure: AppleAssetInstallationFailure?
  var suspendReservation = false
  var reservationContinuation: CheckedContinuation<Void, Never>?
  var onRequest: (() -> Void)?
  var requestValue: FakeAppleInstallationRequest? = FakeAppleInstallationRequest()

  func status(for _: CaptureLanguage) async -> AppleTranscriptionAssetState { state }
  func resolvedLocale(for language: CaptureLanguage) async -> String? { language.rawValue }
  func reserve(locale: String) async throws {
    reservations.append(locale)
    if let reservationFailure { throw reservationFailure }
    if suspendReservation { await withCheckedContinuation { reservationContinuation = $0 } }
  }
  func request(locale _: String) async throws -> (any AppleAssetInstallationRequest)? {
    requestCount += 1
    onRequest?()
    return requestValue
  }
}

@MainActor
private final class FakeAppleInstallationRequest: AppleAssetInstallationRequest {
  var fractionCompleted: Double? = 0.5
  var pending: CheckedContinuation<Void, Never>?
  func downloadAndInstall() async throws { await withCheckedContinuation { pending = $0 } }
}
