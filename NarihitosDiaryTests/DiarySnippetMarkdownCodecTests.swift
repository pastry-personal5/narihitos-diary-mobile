import Foundation
import Testing

@testable import NarihitosDiary

// The contract suite intentionally keeps shared golden/boundary fixture builders in one type.
// swift-format's canonical multiline collections conflict with SwiftLint's trailing-comma rule.
// swiftlint:disable trailing_comma type_body_length

struct DiarySnippetMarkdownCodecTests {
  private struct SupportMutation {
    let original: String
    let replacement: String
    let reason: DiarySnippetUnsupportedReason
  }

  private let codec = DiarySnippetMarkdownCodec()

  @Test func minimalGoldenDocumentRoundTripsDeterministically() throws {
    let snippet = try Self.snippet(body: "Today was calm.")
    let encoded = try codec.encode(snippet)
    let expected = """
      ---
      schema_version: 1
      kind: "ndm.diary-snippet"
      id: "123e4567-e89b-42d3-a456-426614174000"
      created_at: "2026-11-01T12:34:56Z"
      updated_at: "2026-11-01T12:34:56Z"
      title: "A calm day"
      title_origin: "first-sentence"
      favorite: false
      language: "en"
      audio_filename: "123e4567-e89b-42d3-a456-426614174000.m4a"
      recording_duration_ms: 301000
      audio_codec: "aac"
      audio_sample_rate_hz: 44100
      audio_channels: 1
      audio_bitrate_bps: 64000
      transcription_method_id: "ndm.transcription.apple"
      transcription_language_hint: "en-US"
      transcription_settings_revision: 1
      ---

      Today was calm.
      """
    #expect(try #require(String(data: encoded, encoding: .utf8)) == expected)
    guard case .supported(let decoded) = codec.decode(encoded) else {
      Issue.record("golden document did not decode")
      return
    }
    #expect(decoded == snippet)
    #expect(try codec.encode(decoded) == encoded)
  }

  @Test func audioDigestBindsNewPairAndLegacyDocumentStaysReadable() throws {
    let legacy = try Self.snippet(body: "A day")
    let legacyBytes = try codec.encode(legacy)
    guard case .supported(let older) = codec.decode(legacyBytes) else {
      Issue.record("Legacy document should stay readable")
      return
    }
    #expect(older.audioSHA256 == nil)

    var bound = legacy
    let digest = String(repeating: "a", count: 64)
    bound.audioSHA256 = digest
    let encoded = try codec.encode(bound)
    let encodedText = try #require(String(bytes: encoded, encoding: .utf8))
    #expect(encodedText.contains("audio_sha256: \"\(digest)\""))
    #expect(codec.decode(encoded) == .supported(bound))
    let invalid = encodedText.replacingOccurrences(
      of: String(repeating: "a", count: 64), with: String(repeating: "A", count: 64))
    #expect(codec.decode(Data(invalid.utf8)) == .malformed(.invalidField))
  }

  @Test func allFieldsAndUnknownScalarsSurviveAnUnrelatedChange() throws {
    var snippet = try Self.snippet(body: "한글 🌙\n---\nbody delimiter stays body")
    snippet = DiarySnippetV1(
      id: snippet.id, createdAt: snippet.createdAt, updatedAt: snippet.updatedAt,
      title: "Escaped \"title\"",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("apple-ai"), promptRevision: "title-v1", osVersion: "27.0.1",
        modelID: "apple.model"),
      favorite: true, language: "ko", audioFilename: snippet.audioFilename,
      recordingDurationMilliseconds: 1, audioCodec: snippet.audioCodec,
      audioSampleRateHertz: snippet.audioSampleRateHertz, audioChannels: snippet.audioChannels,
      audioBitrateBPS: snippet.audioBitrateBPS,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID("ndm.transcription.cohere"), languageHint: "ko-KR",
        settingsRevision: 1, modelID: "cohere", modelVersion: "03-2026", runtimeID: "runtime",
        conversionID: "conversion"),
      location: LocationContext(
        latitude: 37.5, longitude: 127.0, sampledAt: snippet.createdAt,
        horizontalAccuracyMeters: 5.25, placeName: "Seoul"),
      weather: WeatherContext(
        observedAt: snippet.createdAt, summary: "Clear sky", temperatureCelsius: 12.5),
      body: snippet.body,
      preservedScalars: [
        PreservedScalar(key: "future_integer", rawValue: "42", sourceOrder: 100),
        PreservedScalar(key: "future_string", rawValue: "\"a\\nline\"", sourceOrder: 101),
      ])
    let encoded = try codec.encode(snippet)
    guard case .supported(var decoded) = codec.decode(encoded) else {
      Issue.record("all-fields document did not decode")
      return
    }
    decoded.favorite = false
    let rewritten = try #require(String(data: codec.encode(decoded), encoding: .utf8))
    #expect(rewritten.contains("future_integer: 42\nfuture_string: \"a\\nline\""))
    #expect(decoded.location == snippet.location)
    #expect(decoded.weather == snippet.weather)
  }

  @Test func malformedOptionalGroupIsPreservedButNotInterpreted() throws {
    let encoded = try #require(String(data: codec.encode(Self.snippet()), encoding: .utf8))
    let source = encoded.replacingOccurrences(
      of: "\n---\n\n",
      with: "\nlocation_latitude: 37.5\nlocation_place_name: \"Somewhere\"\n---\n\n")
    guard case .supported(let decoded) = codec.decode(Data(source.utf8)) else {
      Issue.record("document did not decode")
      return
    }
    #expect(decoded.location == nil)
    #expect(decoded.preservedScalars.map(\.key) == ["location_latitude", "location_place_name"])
  }

  @Test func unknownStableValuesAreUnsupportedAndUntouched() throws {
    let source = try #require(String(data: codec.encode(Self.snippet()), encoding: .utf8))
    let mutations = [
      SupportMutation(
        original: "schema_version: 1", replacement: "schema_version: 3", reason: .schemaVersion),
      SupportMutation(
        original: "kind: \"ndm.diary-snippet\"", replacement: "kind: \"future.kind\"", reason: .kind
      ),
      SupportMutation(
        original: "transcription_method_id: \"ndm.transcription.apple\"",
        replacement: "transcription_method_id: \"future.method\"", reason: .transcriptionMethod),
      SupportMutation(
        original: "title_origin: \"first-sentence\"",
        replacement: "title_origin: \"future-origin\"",
        reason: .titleOrigin),
    ]
    for mutation in mutations {
      let data = Data(
        source.replacingOccurrences(of: mutation.original, with: mutation.replacement).utf8)
      #expect(codec.decode(data) == .unsupported(reason: mutation.reason, original: data))
    }
  }

  @Test func hostileSyntaxAndUnsafeReferencesAreMalformed() throws {
    let source = try #require(String(data: codec.encode(Self.snippet()), encoding: .utf8))
    let mutations: [(String, DiarySnippetMalformedCode)] = [
      (
        source.replacingOccurrences(of: "favorite: false", with: "favorite: &anchor false"),
        .forbiddenSyntax
      ),
      (
        source.replacingOccurrences(
          of: "favorite: false", with: "favorite: false\nfavorite: false"), .duplicateKey
      ),
      (source.replacingOccurrences(of: ".m4a\"", with: "/../x.m4a\""), .unsafeAudioReference),
      (
        source.replacingOccurrences(
          of: "recording_duration_ms: 301000", with: "recording_duration_ms: 301001"), .invalidField
      ),
      (source.replacingOccurrences(of: "\n", with: "\r\n"), .invalidLineEnding),
    ]
    for (text, expected) in mutations {
      #expect(codec.decode(Data(text.utf8)) == .malformed(expected))
    }
    #expect(codec.decode(Data([0xFF, 0xFE])) == .malformed(.malformedUTF8))
  }

  @Test func forbiddenGrammarMissingFieldsAndNumericOverflowAreMalformed() throws {
    let source = try #require(String(data: codec.encode(Self.snippet()), encoding: .utf8))
    let cases: [(String, DiarySnippetMalformedCode)] = [
      (
        source.replacingOccurrences(of: "title: \"A calm day\"", with: "title: !tag value"),
        .forbiddenSyntax
      ),
      (
        source.replacingOccurrences(of: "title: \"A calm day\"", with: "title: *alias"),
        .forbiddenSyntax
      ),
      (
        source.replacingOccurrences(of: "title: \"A calm day\"", with: "title: [value]"),
        .forbiddenSyntax
      ),
      (
        source.replacingOccurrences(of: "title: \"A calm day\"", with: "title: {value}"),
        .forbiddenSyntax
      ),
      (
        source.replacingOccurrences(of: "title: \"A calm day\"", with: "title: |"), .forbiddenSyntax
      ),
      (source.replacingOccurrences(of: "title: \"A calm day\"\n", with: ""), .missingRequiredField),
      (source.replacingOccurrences(of: "title:", with: "Invalid-Key:"), .invalidKey),
      (
        source.replacingOccurrences(
          of: "recording_duration_ms: 301000",
          with: "recording_duration_ms: 9223372036854775808"),
        .invalidField
      ),
      (
        source.replacingOccurrences(
          of: "created_at: \"2026-11-01T12:34:56Z\"",
          with: "created_at: \"2026-11-01T12:34:56.0Z\""),
        .invalidField
      ),
      (
        source.replacingOccurrences(
          of: "\n---\n\n",
          with: "\nfuture_decimal: 9999999999999999999999999999999999999999.0\n---\n\n"),
        .invalidField
      ),
    ]
    for (text, expected) in cases {
      #expect(codec.decode(Data(text.utf8)) == .malformed(expected))
    }
  }

  @Test func unescapedQuotesAndRawControlBytesAreMalformed() throws {
    let source = try #require(String(data: codec.encode(Self.snippet()), encoding: .utf8))
    for invalidTitle in ["title: \"unescaped \" quote\"", "title: \"raw\u{0000}control\""] {
      let document = source.replacingOccurrences(of: "title: \"A calm day\"", with: invalidTitle)
      #expect(codec.decode(Data(document.utf8)) == .malformed(.invalidField))
    }
  }

  @Test func bodyBoundsCoverExactAndLimitPlusOne() throws {
    let exact = try Self.snippet(body: String(repeating: "a", count: DiaryBody.maximumBytes))
    let exactData = try codec.encode(exact)
    guard case .supported = codec.decode(exactData) else {
      Issue.record("exact body limit rejected")
      return
    }
    #expect(codec.decode(exactData + Data("a".utf8)) == .malformed(.bodyTooLarge))
    #expect(throws: AssetValueError.invalidBody) {
      try DiaryBody(String(repeating: "a", count: DiaryBody.maximumBytes + 1))
    }
  }

  @Test func encodingRejectsScalarKeyAndTitleLimitOverruns() throws {
    var titleOverrun = try Self.snippet()
    titleOverrun.title = String(repeating: "a", count: 31)
    #expect(throws: DiarySnippetMalformedCode.invalidField) { try codec.encode(titleOverrun) }

    var scalarAtLimit = try Self.snippet()
    scalarAtLimit = Self.replacingPreservedScalars(
      in: scalarAtLimit,
      with: [
        PreservedScalar(
          key: "future", rawValue: "\"\(String(repeating: "a", count: 8_190))\"",
          sourceOrder: 100)
      ])
    guard case .supported = codec.decode(try codec.encode(scalarAtLimit)) else {
      Issue.record("exact scalar limit rejected")
      return
    }

    var scalarOverrun = try Self.snippet()
    scalarOverrun = Self.replacingPreservedScalars(
      in: scalarOverrun,
      with: [
        PreservedScalar(
          key: "future", rawValue: "\"\(String(repeating: "a", count: 8_192))\"",
          sourceOrder: 100)
      ])
    #expect(throws: DiarySnippetMalformedCode.invalidField) { try codec.encode(scalarOverrun) }

    var keysAtLimit = try Self.snippet()
    keysAtLimit = Self.replacingPreservedScalars(
      in: keysAtLimit,
      with: (0..<46).map {
        PreservedScalar(key: "future_\($0)", rawValue: "true", sourceOrder: 100 + $0)
      })
    guard case .supported = codec.decode(try codec.encode(keysAtLimit)) else {
      Issue.record("exact key limit rejected")
      return
    }

    var keyOverrun = try Self.snippet()
    keyOverrun = Self.replacingPreservedScalars(
      in: keyOverrun,
      with: (0..<47).map {
        PreservedScalar(key: "future_\($0)", rawValue: "true", sourceOrder: 200 + $0)
      })
    #expect(throws: DiarySnippetMalformedCode.tooManyKeys) { try codec.encode(keyOverrun) }
  }

  @Test func frontMatterBoundsCoverExactAndLimitPlusOne() throws {
    let exact = try Self.document(
      frontMatterBytes: DiarySnippetMarkdownCodec.maximumFrontMatterBytes)
    guard case .supported = codec.decode(exact) else {
      Issue.record("exact front-matter limit rejected")
      return
    }
    let overrun = try Self.document(
      frontMatterBytes: DiarySnippetMarkdownCodec.maximumFrontMatterBytes + 1)
    #expect(codec.decode(overrun) == .malformed(.frontMatterTooLarge))
  }

  @Test func arbitraryInvalidBytesAlwaysSettleAsMalformed() {
    var generator = SystemRandomNumberGenerator()
    for size in 0..<256 {
      let bytes = (0..<size).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
      if case .supported = codec.decode(Data(bytes)) {
        Issue.record("random bytes decoded as supported")
      }
    }
  }

  @Test func randomizedValidDocumentsRoundTripDeterministically() throws {
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<100 {
      let scalarCount = Int.random(in: 0...10, using: &generator)
      var snippet = try Self.snippet(
        body: String(repeating: "日", count: Int.random(in: 0...512, using: &generator)))
      snippet.title = String(repeating: "x", count: Int.random(in: 0...30, using: &generator))
      snippet = Self.replacingPreservedScalars(
        in: snippet,
        with: (0..<scalarCount).map {
          PreservedScalar(
            key: "random_\($0)",
            rawValue: String(Int.random(in: -10_000...10_000, using: &generator)),
            sourceOrder: 100 + $0)
        })
      let encoded = try codec.encode(snippet)
      guard case .supported(let decoded) = codec.decode(encoded) else {
        Issue.record("generated valid document was rejected")
        return
      }
      #expect(try codec.encode(decoded) == encoded)
    }
  }

  private static func snippet(body: String = "") throws -> DiarySnippetV1 {
    let id = try AssetID("123e4567-e89b-42d3-a456-426614174000")
    let instant = try SchemaInstant("2026-11-01T12:34:56Z")
    return DiarySnippetV1(
      id: id, createdAt: instant, updatedAt: instant, title: "A calm day",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil, osVersion: nil,
        modelID: nil),
      favorite: false, language: "en", audioFilename: "\(id).m4a",
      recordingDurationMilliseconds: 301_000, audioCodec: "aac", audioSampleRateHertz: 44_100,
      audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID("ndm.transcription.apple"), languageHint: "en-US",
        settingsRevision: 1, modelID: nil, modelVersion: nil, runtimeID: nil, conversionID: nil),
      location: nil, weather: nil, body: try DiaryBody(body), preservedScalars: [])
  }

  private static func replacingPreservedScalars(
    in snippet: DiarySnippetV1, with preservedScalars: [PreservedScalar]
  ) -> DiarySnippetV1 {
    DiarySnippetV1(
      id: snippet.id, createdAt: snippet.createdAt, updatedAt: snippet.updatedAt,
      title: snippet.title, titleProvenance: snippet.titleProvenance, favorite: snippet.favorite,
      language: snippet.language, audioFilename: snippet.audioFilename,
      recordingDurationMilliseconds: snippet.recordingDurationMilliseconds,
      audioCodec: snippet.audioCodec, audioSampleRateHertz: snippet.audioSampleRateHertz,
      audioChannels: snippet.audioChannels, audioBitrateBPS: snippet.audioBitrateBPS,
      transcription: snippet.transcription, location: snippet.location, weather: snippet.weather,
      body: snippet.body, preservedScalars: preservedScalars)
  }

  private static func document(frontMatterBytes target: Int) throws -> Data {
    let codec = DiarySnippetMarkdownCodec()
    let source = try #require(String(data: codec.encode(snippet()), encoding: .utf8))
    let delimiter = try #require(source.range(of: "\n---\n\n"))
    let prefix = String(source[..<delimiter.lowerBound])
    let currentBytes = prefix.utf8.count - 4
    let keys = (0..<8).map { "padding_\($0)" }
    let overhead = keys.reduce(0) { $0 + 1 + $1.utf8.count + 2 }
    let rawByteBudget = target - currentBytes - overhead
    #expect(rawByteBudget >= keys.count * 2)
    #expect(rawByteBudget <= keys.count * DiarySnippetMarkdownCodec.maximumScalarBytes)
    let quotient = rawByteBudget / keys.count
    let remainder = rawByteBudget % keys.count
    let padding = keys.enumerated().map { index, key in
      let rawBytes = quotient + (index < remainder ? 1 : 0)
      return "\n\(key): \"\(String(repeating: "a", count: rawBytes - 2))\""
    }.joined()
    return Data((prefix + padding + source[delimiter.lowerBound...]).utf8)
  }
}

// swiftlint:enable trailing_comma type_body_length
