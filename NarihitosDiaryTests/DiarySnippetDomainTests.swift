import Foundation
import Testing

@testable import NarihitosDiary

// swift-format's canonical multiline collections conflict with SwiftLint's trailing-comma rule.
// swiftlint:disable trailing_comma

struct DiarySnippetDomainTests {
  @Test func assetIdentityAcceptsOnlyCanonicalVersionFourUUID() throws {
    let value = "123e4567-e89b-42d3-a456-426614174000"
    #expect(try AssetID(value).description == value)
    #expect(throws: AssetValueError.invalidAssetID) { try AssetID(value.uppercased()) }
    #expect(throws: AssetValueError.invalidAssetID) {
      try AssetID("123e4567-e89b-12d3-a456-426614174000")
    }
    #expect(throws: AssetValueError.invalidAssetID) { try AssetID("../outside") }
  }

  @Test func schemaInstantRequiresWholeSecondCanonicalUTC() throws {
    #expect(try SchemaInstant("2026-11-01T12:34:56Z").description == "2026-11-01T12:34:56Z")
    for invalid in [
      "2026-11-01T12:34:56.000Z", "2026-11-01T12:34:56+00:00",
      "2026-02-29T12:34:56Z", "2026-11-01t12:34:56z",
    ] {
      #expect(throws: AssetValueError.invalidInstant) { try SchemaInstant(invalid) }
    }
  }

  @Test func layoutIsCanonicalUTCAndReferenceIsConfined() throws {
    let id = try AssetID("123e4567-e89b-42d3-a456-426614174000")
    let instant = try SchemaInstant("2026-11-01T00:05:06Z")
    let layout = DiarySnippetLayout(id: id, createdAt: instant)
    #expect(layout.directoryComponents == ["2026", "11", "01"])
    #expect(layout.markdownFilename == "2026-11-01_00-05-06-\(id).md")
    #expect(layout.assetsDirectoryName == "2026-11-01_00-05-06-\(id).assets")
    #expect(layout.audioFilename == "\(id).m4a")
    #expect(layout.validates(audioReference: "\(id).m4a"))
    for unsafe in ["../\(id).m4a", "/tmp/\(id).m4a", "file://\(id).m4a", "%2e%2e.m4a"] {
      #expect(!layout.validates(audioReference: unsafe))
    }
  }
}

// swiftlint:enable trailing_comma
