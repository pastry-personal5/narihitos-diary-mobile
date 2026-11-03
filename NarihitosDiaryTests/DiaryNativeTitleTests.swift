import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
@Suite(.serialized)
struct DiaryNativeTitleTests {
  @Test func systemTitlePolicyUsesEditedBodyAndPreservesRecordingProvenance() async throws {
    let model = AppleDiaryTitleModel()
    let detector = NaturalLanguageTitleDetector()
    let policy = DiaryTitlePolicy(model: model, languageDetector: detector)
    let samples = [
      ("en", "I walked through the park this afternoon and watched the autumn leaves fall."),
      ("ko", "오늘 오후에는 공원을 산책하며 가을 나뭇잎이 떨어지는 모습을 바라보았다."),
      ("empty", ""),
      // swiftlint:disable:next trailing_comma
      ("empty", " \n\t "),
    ]
    for (language, body) in samples {
      if language != "empty" { #expect(detector.assess(body)?.language == language) }
      let source = try DiaryEditFixture.snippet()
      var revision = try DiaryEditRevision.make(
        source: source, change: .body(body), now: .distantPast)
      let generated = await policy.title(for: revision.body)
      #expect(!generated.text.isEmpty)
      #expect(generated.text.count <= 30)
      if language == "empty" {
        #expect(generated.text == "Untitled")
        #expect(generated.provenance.originID.description == "empty-body")
      }
      if generated.provenance.originID.description == "apple-ai" {
        #expect(generated.provenance.promptRevision == DiaryTitlePolicy.promptRevision)
      }
      revision.title = generated.text
      revision.titleProvenance = generated.provenance
      let encoded = try DiarySnippetMarkdownCodec().encode(revision)
      guard case .supported(let decoded) = DiarySnippetMarkdownCodec().decode(encoded) else {
        Issue.record("Native title revision must remain a supported diary")
        return
      }
      // sourceOrder is a decoded header position, not a persisted scalar value;
      // title provenance can add/remove known keys before preserved scalars.
      #expect(decoded.title == generated.text)
      #expect(decoded.titleProvenance == generated.provenance)
      #expect(decoded.body == revision.body)
      #expect(decoded.id == source.id)
      #expect(decoded.createdAt == source.createdAt)
      #expect(decoded.language == source.language)
      #expect(decoded.transcription == source.transcription)
      #expect(decoded.preservedScalars.map(\.key) == source.preservedScalars.map(\.key))
      #expect(decoded.preservedScalars.map(\.rawValue) == source.preservedScalars.map(\.rawValue))
      print(
        "M16 native title: ready=\(model.isAvailable), language=\(language), "
          + "origin=\(generated.provenance.originID), graphemes=\(generated.text.count)")
    }
  }
}
