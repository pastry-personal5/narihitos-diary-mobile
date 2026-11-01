import Foundation
import Speech

enum AppleSpeechModuleStatus {
  case unsupported
  case downloadable
  case downloading
  case installed
  case unavailable
}

@MainActor
protocol AppleSpeechReadinessPlatform {
  var isAvailable: Bool { get }
  func resolve(_ language: CaptureLanguage) async -> String?
  func status(locale: String) async -> AppleSpeechModuleStatus
}

@MainActor
struct AppleSpeechReadinessSource: AppleTranscriptionReadinessSource {
  private let platform: any AppleSpeechReadinessPlatform

  init(platform: any AppleSpeechReadinessPlatform = SystemAppleSpeechReadinessPlatform()) {
    self.platform = platform
  }

  func status(for language: CaptureLanguage) async -> AppleTranscriptionAssetState {
    guard platform.isAvailable else { return .unavailable }
    guard let locale = await platform.resolve(language) else { return .unsupported }
    switch await platform.status(locale: locale) {
    case .unsupported: return .unsupported
    case .downloadable: return .downloadable
    case .downloading: return .downloading
    case .installed: return .ready(resolvedLocale: locale)
    case .unavailable: return .temporarilyUnavailable
    }
  }
}

@MainActor
struct SystemAppleSpeechReadinessPlatform: AppleSpeechReadinessPlatform {
  var isAvailable: Bool { SpeechTranscriber.isAvailable }

  func resolve(_ language: CaptureLanguage) async -> String? {
    await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue))?
      .identifier(.bcp47)
  }

  func status(locale: String) async -> AppleSpeechModuleStatus {
    let transcriber = SpeechTranscriber(locale: Locale(identifier: locale), preset: .transcription)
    switch await AssetInventory.status(forModules: [transcriber]) {
    case .unsupported: return .unsupported
    case .supported: return .downloadable
    case .downloading: return .downloading
    case .installed: return .installed
    @unknown default: return .unavailable
    }
  }
}
