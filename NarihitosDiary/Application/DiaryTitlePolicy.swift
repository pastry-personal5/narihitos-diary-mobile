import Foundation
import NaturalLanguage

struct GeneratedDiaryTitle: Equatable, Sendable {
  let text: String
  let provenance: TitleProvenance
}

struct TitleModelReply: Equatable, Sendable {
  let text: String
  let outputTokens: Int
}

struct TitleLanguageAssessment: Equatable, Sendable {
  let language: String
  let confidence: Double
}

@MainActor
protocol DiaryTitleLanguageDetector {
  func assess(_ text: String) -> TitleLanguageAssessment?
}

@MainActor
protocol DiaryTitleModelPort: AnyObject {
  var isAvailable: Bool { get }
  var modelIdentifier: String? { get }
  /// Return nil if exact or conservative token accounting cannot cover every byte.
  func chunks(for text: String, maximumTokens: Int, maximumChunks: Int) async throws
    -> [String]?
  func summarize(_ text: String, language: String, maximumOutputTokens: Int) async throws
    -> TitleModelReply
}

@MainActor
final class DiaryTitlePolicy {
  static let promptRevision = "title-v1"
  private let model: any DiaryTitleModelPort
  private let languageDetector: any DiaryTitleLanguageDetector
  private let clock = ContinuousClock()
  private let timeout: Duration
  private var modelOperationInFlight = false

  /// A deadline can return a fallback before a cancelled model call relinquishes work.
  var hasActiveWork: Bool { modelOperationInFlight }

  init(
    model: any DiaryTitleModelPort, languageDetector: any DiaryTitleLanguageDetector,
    timeout: Duration = .seconds(30)
  ) {
    self.model = model
    self.languageDetector = languageDetector
    self.timeout = timeout
  }

  func title(for body: DiaryBody) async -> GeneratedDiaryTitle {
    let fallback = Self.fallback(body.text)
    guard !modelOperationInFlight else { return fallback }
    modelOperationInFlight = true
    let result = await withCheckedContinuation { continuation in
      let gate = TitleDeadlineGate(continuation)
      gate.inference = Task { [self] in
        let result = await computeTitle(for: body)
        modelOperationInFlight = false
        gate.resolve(result, fromTimeout: false)
      }
      gate.timer = Task { [self] in
        do { try await Task.sleep(for: timeout) } catch { return }
        gate.resolve(nil, fromTimeout: true)
      }
    }
    return result ?? fallback
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func computeTitle(for body: DiaryBody) async -> GeneratedDiaryTitle {
    let fallback = Self.fallback(body.text)
    guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return Self.result("Untitled", origin: "empty-body")
    }
    let deadline = clock.now.advanced(by: timeout)
    guard model.isAvailable, let language = confidentLanguage(body.text) else {
      return fallback
    }
    do {
      guard
        let chunks = try await model.chunks(
          for: body.text, maximumTokens: 2_000, maximumChunks: 8),
        !chunks.isEmpty, chunks.count <= 8, chunks.joined() == body.text,
        clock.now < deadline, !Task.isCancelled
      else { return fallback }
      var finalInput = body.text
      if chunks.count > 1 {
        var summaries: [String] = []
        for chunk in chunks {
          guard clock.now < deadline, !Task.isCancelled else { return fallback }
          let reply = try await model.summarize(
            chunk, language: language, maximumOutputTokens: 128)
          guard reply.outputTokens >= 0, reply.outputTokens <= 128,
            let clean = usable(reply.text, language: language), clean.count <= 80
          else { return fallback }
          summaries.append(clean)
        }
        finalInput = summaries.joined(separator: "\n")
        guard
          try await model.chunks(for: finalInput, maximumTokens: 2_000, maximumChunks: 1)?
            .joined() == finalInput
        else { return fallback }
      }
      guard clock.now < deadline, !Task.isCancelled else { return fallback }
      let reply = try await model.summarize(
        finalInput, language: language, maximumOutputTokens: 64)
      guard clock.now < deadline, !Task.isCancelled,
        (0...64).contains(reply.outputTokens),
        let clean = usable(reply.text, language: language)
      else { return fallback }
      return GeneratedDiaryTitle(
        text: Self.capped(clean),
        provenance: TitleProvenance(
          originID: Self.origin("apple-ai"),
          promptRevision: Self.promptRevision,
          osVersion: Self.currentOSVersion(),
          modelID: model.modelIdentifier))
    } catch {
      return fallback
    }
  }

  nonisolated static func fallback(_ text: String) -> GeneratedDiaryTitle {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return result("Untitled", origin: "empty-body") }
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = trimmed
    var first: String?
    tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
      let candidate = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !candidate.isEmpty {
        first = candidate
        return false
      }
      return true
    }
    let line = oneLine(first ?? trimmed)
    return result(capped(line), origin: "first-sentence")
  }

  private nonisolated static func result(_ text: String, origin: String) -> GeneratedDiaryTitle {
    GeneratedDiaryTitle(
      text: text,
      provenance: TitleProvenance(
        originID: self.origin(origin), promptRevision: nil,
        osVersion: nil, modelID: nil))
  }

  private nonisolated static func origin(_ value: String) -> TitleOriginID {
    // These literals are the approved codec origins and cannot fail validation.
    // swiftlint:disable:next force_try
    try! TitleOriginID(value)
  }

  private static func currentOSVersion() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }

  private nonisolated static func capped(_ text: String) -> String {
    text.count <= 30 ? text : String(text.prefix(29)) + "…"
  }

  private nonisolated static func oneLine(_ text: String) -> String {
    let scalars = text.unicodeScalars.map { scalar -> String in
      CharacterSet.whitespacesAndNewlines.contains(scalar)
        || CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
    }
    return scalars.joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  private func usable(_ text: String, language: String) -> String? {
    let clean = Self.oneLine(text).trimmingCharacters(in: .whitespacesAndNewlines)
    let folded = clean.lowercased()
    guard !clean.isEmpty, clean.utf8.count <= 8_192,
      clean.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }),
      !clean.contains(where: { "\"“”‘’#*\n\r".contains($0) }),
      !folded.hasPrefix("title:"), !folded.hasPrefix("title :"),
      !folded.hasPrefix("제목:"), !folded.hasPrefix("제목 :"),
      !clean.unicodeScalars.contains(where: {
        $0.properties.isEmojiPresentation || $0.value == 0xFE0F
      }),
      !".!?。！？:：;；".contains(clean.last!),
      confidentLanguage(clean) == language
    else { return nil }
    return clean
  }

  private func confidentLanguage(_ text: String) -> String? {
    guard let assessment = languageDetector.assess(text),
      assessment.confidence >= 0.8,
      assessment.language == "en" || assessment.language == "ko"
    else { return nil }
    return assessment.language
  }
}

@MainActor
private final class TitleDeadlineGate {
  private var continuation: CheckedContinuation<GeneratedDiaryTitle?, Never>?
  var inference: Task<Void, Never>?
  var timer: Task<Void, Never>?

  init(_ continuation: CheckedContinuation<GeneratedDiaryTitle?, Never>) {
    self.continuation = continuation
  }

  func resolve(_ result: GeneratedDiaryTitle?, fromTimeout: Bool) {
    guard let continuation else { return }
    self.continuation = nil
    if fromTimeout { inference?.cancel() } else { timer?.cancel() }
    continuation.resume(returning: result)
  }
}
