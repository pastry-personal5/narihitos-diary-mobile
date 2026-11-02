// swiftlint:disable trailing_comma
import Foundation
import Testing

@testable import NarihitosDiary

struct LegacyDiaryReaderTests {
  static let stem = "2026-01-02_03-04-05-678"
  static let fixture = """
    ---
    id: "2026-01-02_03-04-05-678"
    created_at: "2026-01-02T12:04:05.678+09:00"
    updated_at: "2026-01-02T12:04:05.678+09:00"
    tags:
      []
    favorite: false
    weather_summary: "Synthetic clear sky"
    weather_temperature_celsius: 12.5
    location_latitude: 10.25
    location_longitude: 20.5
    location_place_name: "Synthetic place"
    transcription_model: "apple-on-device"
    transcription_prompt: "On-device"
    ---

    A synthetic first sentence. Another sentence.
    """

  @Test func offsetTimestampAgreesWithUTCNamesAndNestedEmptyTagsAreNotGeneralYAML() throws {
    let bytes = Data(Self.fixture.utf8)
    let value = try LegacyDiaryReader.decode(bytes, stem: Self.stem)
    #expect(value.createdAt == LegacyDiaryReader.stemDate(Self.stem))
    #expect(value.body == "A synthetic first sentence. Another sentence.")
    #expect(value.location?.latitude == Decimal(string: "10.25"))
    #expect(value.weather?.temperatureCelsius == Decimal(string: "12.5"))
    #expect(value.language == nil)
    #expect(DiaryTitlePolicy.fallback(value.body).text.count <= 30)
    #expect(bytes == Data(Self.fixture.utf8))
  }

  @Test func rejectsV1DowngradeDuplicateKeysTraversalAndUnprovenNestedSyntax() {
    for changed in [
      Self.fixture.replacingOccurrences(
        of: "favorite: false", with: "favorite: false\nfavorite: true"),
      Self.fixture.replacingOccurrences(of: "  []", with: "  [unsafe]"),
      Self.fixture.replacingOccurrences(of: "  []", with: "  object: !Unsafe {}"),
      Self.fixture.replacingOccurrences(of: "favorite: false", with: "schema_version: 1"),
      Self.fixture.replacingOccurrences(of: "favorite: false", with: "kind: \"ndm.diary-snippet\""),
      Self.fixture.replacingOccurrences(of: "+09:00", with: "+08:00"),
      Self.fixture.replacingOccurrences(of: "favorite: false", with: "favorite: *alias"),
    ] {
      #expect(throws: CatalogIssue.self) {
        try LegacyDiaryReader.decode(Data(changed.utf8), stem: Self.stem)
      }
    }
    #expect(LegacyDiaryReader.stemDate("../unsafe") == nil)
    #expect(LegacyDiaryReader.stemDate("2026-02-30_03-04-05-678") == nil)
  }

  @Test func boundedHeaderAndBodyRejectBeforeReturningContent() {
    let oversized = Self.fixture + String(repeating: "a", count: DiaryBody.maximumBytes)
    #expect(throws: CatalogIssue.self) {
      try LegacyDiaryReader.decode(Data(oversized.utf8), stem: Self.stem)
    }
    let scalar = Self.fixture.replacingOccurrences(
      of: "Synthetic place", with: String(repeating: "x", count: 8_193))
    #expect(throws: CatalogIssue.self) {
      try LegacyDiaryReader.decode(Data(scalar.utf8), stem: Self.stem)
    }
  }
}

// swiftlint:enable trailing_comma
