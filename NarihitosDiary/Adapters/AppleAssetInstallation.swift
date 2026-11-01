import Foundation
import Speech

struct AppleAssetSpaceEstimate: Equatable {
  let downloadBytes: Int64
  let requiredFreeBytes: Int64
  let availableBytes: Int64
}

struct AppleAssetInstallPlan: Equatable {
  let language: CaptureLanguage
  let resolvedLocale: String
  let estimate: AppleAssetSpaceEstimate
}

enum AppleAssetPreparation: Equatable {
  case ready
  case downloading
  case unsupported
  case preflightUnavailable
  case insufficientSpace
  case failed
  case downloadable(AppleAssetInstallPlan)
}

enum AppleAssetInstallationOutcome: Equatable {
  case ready
  case downloading
  case unsupported
  case preflightUnavailable
  case insufficientSpace
  case reservationCapacity
  case cancelled
  case failed
}

enum AppleAssetInstallationFailure: Error {
  case reservationCapacity
  case unavailable
}

@MainActor
protocol AppleAssetInstallationRequest {
  var fractionCompleted: Double? { get }
  func downloadAndInstall() async throws
}

@MainActor
protocol AppleAssetInstallationBackend {
  func status(for language: CaptureLanguage) async -> AppleTranscriptionAssetState
  func resolvedLocale(for language: CaptureLanguage) async -> String?
  func spaceEstimate(for locale: String) async -> AppleAssetSpaceEstimate?
  func reserve(locale: String) async throws
  func request(locale: String) async throws -> (any AppleAssetInstallationRequest)?
}

/// The app may not initiate a system download until the approved preflight is available.
@MainActor
final class AppleAssetInstaller {
  private struct InstallationTask {
    let id: UUID
    let plan: AppleAssetInstallPlan
    let task: Task<AppleAssetInstallationOutcome, Never>
  }

  private let backend: any AppleAssetInstallationBackend
  private var tasks: [CaptureLanguage: InstallationTask] = [:]
  private(set) var progress: [CaptureLanguage: Double] = [:]
  var onChange: (@MainActor () -> Void)?

  init(backend: any AppleAssetInstallationBackend) { self.backend = backend }

  /// Obtain and display the plan's size before offering the download action.
  func prepare(_ language: CaptureLanguage) async -> AppleAssetPreparation {
    switch await backend.status(for: language) {
    case .ready: return .ready
    case .downloading: return .downloading
    case .unsupported, .unavailable: return .unsupported
    case .temporarilyUnavailable: return .failed
    case .downloadable: break
    }
    guard let locale = await backend.resolvedLocale(for: language) else { return .unsupported }
    guard let estimate = await backend.spaceEstimate(for: locale), estimate.downloadBytes > 0,
      estimate.requiredFreeBytes > 0, estimate.availableBytes >= 0
    else { return .preflightUnavailable }
    guard estimate.availableBytes >= estimate.requiredFreeBytes else { return .insufficientSpace }
    return .downloadable(
      AppleAssetInstallPlan(language: language, resolvedLocale: locale, estimate: estimate))
  }

  func install(_ plan: AppleAssetInstallPlan) async -> AppleAssetInstallationOutcome {
    let language = plan.language
    if let existing = tasks[language] {
      guard existing.plan == plan else { return .preflightUnavailable }
      return await existing.task.value
    }
    let id = UUID()
    let task = Task { await perform(plan) }
    tasks[language] = InstallationTask(id: id, plan: plan, task: task)
    let outcome = await task.value
    if tasks[language]?.id == id { tasks[language] = nil }
    return outcome
  }

  func cancel(_ language: CaptureLanguage) {
    tasks[language]?.task.cancel()
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func perform(_ plan: AppleAssetInstallPlan) async -> AppleAssetInstallationOutcome {
    let language = plan.language
    switch await prepare(language) {
    case .ready: return .ready
    case .downloading: return .downloading
    case .unsupported: return .unsupported
    case .preflightUnavailable: return .preflightUnavailable
    case .insufficientSpace: return .insufficientSpace
    case .failed: return .failed
    case .downloadable(let current):
      guard current.resolvedLocale == plan.resolvedLocale,
        current.estimate.downloadBytes == plan.estimate.downloadBytes,
        current.estimate.requiredFreeBytes == plan.estimate.requiredFreeBytes
      else { return .preflightUnavailable }
    }
    do {
      try Task.checkCancellation()
      try await backend.reserve(locale: plan.resolvedLocale)
      try Task.checkCancellation()
      guard let request = try await backend.request(locale: plan.resolvedLocale) else {
        return await finalStatus(language)
      }
      try Task.checkCancellation()
      let observation = Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          if let fraction = request.fractionCompleted, fraction.isFinite {
            self.progress[language] = min(max(fraction, 0), 1)
            self.onChange?()
          }
          try? await Task.sleep(for: .milliseconds(250))
        }
      }
      defer {
        observation.cancel()
        progress[language] = nil
        onChange?()
      }
      try await request.downloadAndInstall()
      return await finalStatus(language)
    } catch AppleAssetInstallationFailure.reservationCapacity {
      return .reservationCapacity
    } catch is CancellationError {
      let status = await finalStatus(language)
      return status == .failed ? .cancelled : status
    } catch {
      return await finalStatus(language)
    }
  }

  private func finalStatus(_ language: CaptureLanguage) async -> AppleAssetInstallationOutcome {
    switch await backend.status(for: language) {
    case .ready: .ready
    case .downloading: .downloading
    default: .failed
    }
  }
}

@MainActor
struct SystemAppleAssetInstallationBackend: AppleAssetInstallationBackend {
  private let readiness = AppleSpeechReadinessSource()

  func status(for language: CaptureLanguage) async -> AppleTranscriptionAssetState {
    await readiness.status(for: language)
  }

  func resolvedLocale(for language: CaptureLanguage) async -> String? {
    await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue))?
      .identifier(.bcp47)
  }

  func spaceEstimate(for _: String) async -> AppleAssetSpaceEstimate? {
    // The public Speech API does not document a pre-download byte count or required space.
    nil
  }

  func reserve(locale: String) async throws {
    let target = Locale(identifier: locale)
    let reserved = await AssetInventory.reservedLocales
    if reserved.contains(where: { $0.identifier(.bcp47) == locale }) { return }
    guard reserved.count < AssetInventory.maximumReservedLocales else {
      throw AppleAssetInstallationFailure.reservationCapacity
    }
    _ = try await AssetInventory.reserve(locale: target)
    let after = await AssetInventory.reservedLocales
    guard after.contains(where: { $0.identifier(.bcp47) == locale }) else {
      throw AppleAssetInstallationFailure.unavailable
    }
  }

  func request(locale: String) async throws -> (any AppleAssetInstallationRequest)? {
    let module = SpeechTranscriber(locale: Locale(identifier: locale), preset: .transcription)
    guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module])
    else { return nil }
    return SystemAppleAssetInstallationRequest(request: request)
  }
}

@MainActor
private struct SystemAppleAssetInstallationRequest: AppleAssetInstallationRequest {
  let request: AssetInstallationRequest

  var fractionCompleted: Double? {
    guard !request.progress.isIndeterminate else { return nil }
    return request.progress.fractionCompleted
  }

  func downloadAndInstall() async throws { try await request.downloadAndInstall() }
}
