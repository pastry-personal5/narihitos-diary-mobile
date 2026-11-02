import Foundation

/// The owner-supplied pre-v1 samples establish this grammar; fixtures use synthetic content.
struct LegacyDiaryValue: Sendable {
  let id: String
  let createdAt: Date
  let body: String
  let language: String?
  let location: CatalogLocation?
  let weather: CatalogWeather?
}

enum LegacyDiaryReader {
  static func stemDate(_ stem: String) -> Date? {
    guard stem.utf8.count == 23 else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
    formatter.isLenient = false
    guard let date = formatter.date(from: stem), formatter.string(from: date) == stem else {
      return nil
    }
    return date
  }

  static func decode(_ bytes: Data, stem: String) throws -> LegacyDiaryValue {
    guard
      bytes.count <= DiaryBody.maximumBytes + DiarySnippetMarkdownCodec.maximumFrontMatterBytes
        + 10,
      let text = String(data: bytes, encoding: .utf8), !text.contains("\r"),
      text.hasPrefix("---\n"),
      let end = text.range(
        of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex)
    else { throw CatalogIssue.malformed }
    let header = String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])
    guard header.utf8.count + 4 <= DiarySnippetMarkdownCodec.maximumFrontMatterBytes else {
      throw CatalogIssue.malformed
    }
    let fields = try scalars(header)
    guard fields["schema_version"] == nil, fields["kind"] == nil else {
      throw CatalogIssue.malformed
    }
    guard let id = try string(fields["id"]), id == stem, let expected = stemDate(stem),
      let created = try instant(fields["created_at"]),
      abs(created.timeIntervalSince(expected)) < 0.000_1,
      try instant(fields["updated_at"]) != nil
    else { throw CatalogIssue.malformed }
    var body = String(text[end.upperBound...])
    if body.hasPrefix("\n") { body.removeFirst() }
    guard body.utf8.count <= DiaryBody.maximumBytes else { throw CatalogIssue.malformed }
    return LegacyDiaryValue(
      id: id, createdAt: created, body: body,
      language: try string(fields["language"]),
      location: location(fields), weather: weather(fields))
  }

  private static func scalars(_ header: String) throws -> [String: String] {
    var fields: [String: String] = [:]
    var awaitingEmptyTags = false
    for line in header.split(separator: "\n", omittingEmptySubsequences: false) {
      if awaitingEmptyTags {
        guard line == "  []" else { throw CatalogIssue.malformed }
        awaitingEmptyTags = false
        continue
      }
      guard let colon = line.firstIndex(of: ":") else { throw CatalogIssue.malformed }
      let key = String(line[..<colon])
      guard !key.isEmpty,
        key.utf8.allSatisfy({ (97...122).contains($0) || $0 == 95 }),
        fields[key] == nil, fields.count < 64
      else { throw CatalogIssue.malformed }
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      guard value.utf8.count <= 8_192 else { throw CatalogIssue.malformed }
      awaitingEmptyTags = try validateScalar(key: key, value: value)
      fields[key] = value
    }
    guard !awaitingEmptyTags else { throw CatalogIssue.malformed }
    return fields
  }

  private static func validateScalar(key: String, value: String) throws -> Bool {
    if key == "tags", value.isEmpty { return true }
    if key == "tags", value == "[]" { return false }
    if value.hasPrefix("\"") {
      guard (try? JSONDecoder().decode(String.self, from: Data(value.utf8))) != nil else {
        throw CatalogIssue.malformed
      }
    } else {
      let boolean = value == "true" || value == "false"
      let decimal =
        !value.isEmpty && value.utf8.allSatisfy { "0123456789.-+eE".utf8.contains($0) }
        && Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) != nil
      guard boolean || decimal else { throw CatalogIssue.malformed }
    }
    return false
  }

  private static func string(_ raw: String?) throws -> String? {
    guard let raw else { return nil }
    guard let value = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) else {
      throw CatalogIssue.malformed
    }
    return value
  }

  private static func instant(_ raw: String?) throws -> Date? {
    guard let value = try string(raw) else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: value) else { throw CatalogIssue.malformed }
    return date
  }

  private static func location(_ fields: [String: String]) -> CatalogLocation? {
    guard let rawLatitude = fields["location_latitude"],
      let rawLongitude = fields["location_longitude"],
      let latitude = Decimal(string: rawLatitude, locale: Locale(identifier: "en_US_POSIX")),
      let longitude = Decimal(string: rawLongitude, locale: Locale(identifier: "en_US_POSIX")),
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    else { return nil }
    return CatalogLocation(
      latitude: latitude, longitude: longitude,
      placeName: try? string(fields["location_place_name"])
    )
  }

  private static func weather(_ fields: [String: String]) -> CatalogWeather? {
    guard let summary = try? string(fields["weather_summary"]), !summary.isEmpty,
      let raw = fields["weather_temperature_celsius"],
      let temperature = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
      (-100...100).contains(temperature)
    else { return nil }
    return CatalogWeather(summary: summary, temperatureCelsius: temperature)
  }
}
