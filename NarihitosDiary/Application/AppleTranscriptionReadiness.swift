import Foundation

enum AppleTranscriptionAssetState: Equatable, Sendable {
  case unavailable
  case unsupported
  case downloadable
  case reservationRequired
  case downloading
  case ready(resolvedLocale: String)
  case temporarilyUnavailable
}

@MainActor
protocol AppleTranscriptionReadinessSource {
  func status(for language: CaptureLanguage) async -> AppleTranscriptionAssetState
}

/// A refresh is advisory; callers must check again before claiming a recording.
@MainActor
final class AppleTranscriptionReadiness {
  private let source: any AppleTranscriptionReadinessSource
  private var generations: [CaptureLanguage: UInt64] = [:]
  private(set) var states: [CaptureLanguage: AppleTranscriptionAssetState] = [:]

  init(source: any AppleTranscriptionReadinessSource) {
    self.source = source
  }

  @discardableResult
  func refresh(_ language: CaptureLanguage) async -> AppleTranscriptionAssetState? {
    let generation = (generations[language] ?? 0) &+ 1
    generations[language] = generation
    let state = await source.status(for: language)
    guard generations[language] == generation, !Task.isCancelled else { return nil }
    states[language] = state
    return state
  }

  func invalidate() {
    for language in [CaptureLanguage.english, .korean] {
      generations[language] = (generations[language] ?? 0) &+ 1
    }
    states.removeAll()
  }
}
