import Darwin
import Foundation

struct DiaryCatalogHandler: CatalogAssetHandler {
  let kind = DiarySnippetSupportPolicy.kind
  var metrics: CatalogPerformanceProbe?
  var preparedLegacy: CatalogLegacySiblingProof?

  func descends(into components: [String]) -> Bool {
    guard components.count <= 3 else { return false }
    return components.enumerated().allSatisfy { index, value in
      value.utf8.count == (index == 0 ? 4 : 2) && value.utf8.allSatisfy { (48...57).contains($0) }
    }
  }

  func candidate(components: [String], safe: Bool) -> CatalogCandidate? {
    if !safe, !components.isEmpty, descends(into: components) {
      return CatalogCandidate(
        components: components, handler: kind, date: nil, stableID: "", safe: false)
    }
    guard components.count == 4, descends(into: Array(components.dropLast())),
      let filename = components.last,
      filename.hasSuffix(".md") || filename.hasSuffix(".assets")
    else { return nil }
    let stem = String(filename.dropLast(filename.hasSuffix(".md") ? 3 : 7))
    let parsed = Self.currentStem(stem)
    return CatalogCandidate(
      components: Array(components.dropLast()) + [stem], handler: kind,
      date: parsed?.date ?? LegacyDiaryReader.stemDate(stem),
      stableID: parsed?.id.description ?? "", safe: safe)
  }

  func read(_ candidate: CatalogCandidate, root: URL) async throws -> CatalogReadValue {
    metrics?.record(.validationAttempts)
    let control = CatalogReadControl(metrics: metrics)
    return try await withTaskCancellationHandler {
      try await coordinatedRead(candidate, root: root, control: control)
    } onCancel: {
      control.cancel()
    }
  }

  func readCoordinated(
    _ candidate: CatalogCandidate, root: URL, control: CatalogReadControl
  ) throws -> CatalogReadValue {
    try control.check()
    guard candidate.safe, let stem = candidate.components.last else { throw CatalogIssue.unsafe }
    let parent = Array(candidate.components.dropLast())
    let markdown = parent + [stem + ".md"]
    guard try CatalogSafeFiles.resourceExists(root: root, components: markdown) else {
      return try orphan(candidate, root: root, control: control)
    }
    let maximum = DiaryBody.maximumBytes + DiarySnippetMarkdownCodec.maximumFrontMatterBytes + 10
    let (bytes, markdownVersion) = try CatalogSafeFiles.read(
      root: root, components: markdown, maximum: maximum)
    metrics?.record(.markdownBytes, UInt64(bytes.count))
    let markdownURL = markdown.reduce(root) { $0.appendingPathComponent($1) }
    if Self.hasConflict(markdownURL) {
      return failure(
        .conflict, version: markdownVersion, payload: Self.recoveryText(bytes), hasText: true)
    }
    let result: CatalogReadValue
    switch DiarySnippetMarkdownCodec().decode(bytes) {
    case .supported(let snippet):
      result = try current(
        snippet, candidate: candidate, root: root, version: markdownVersion, control: control)
    case .unsupported:
      result = failure(
        .unsupported, version: markdownVersion, payload: Self.recoveryText(bytes), hasText: true)
    case .malformed:
      guard LegacyDiaryReader.stemDate(stem) != nil else {
        return failure(
          .malformed, version: markdownVersion, payload: Self.recoveryText(bytes), hasText: true)
      }
      result = try legacy(
        bytes, candidate: candidate, root: root, version: markdownVersion, control: control)
    }
    let (reopenedBytes, reopened) = try CatalogSafeFiles.read(
      root: root, components: markdown, maximum: maximum)
    metrics?.record(.markdownBytes, UInt64(reopenedBytes.count))
    guard reopened == markdownVersion, !Self.hasConflict(markdownURL) else {
      throw CatalogIssue.changed
    }
    try validateBindings(result.files, root: root)
    try control.check()
    return result
  }

  private func validateBindings(_ bindings: [CatalogFileBinding], root: URL) throws {
    for binding in bindings {
      let descriptor = try CatalogSafeFiles.descriptor(
        root: root, components: binding.components, directory: binding.directory)
      defer { close(descriptor) }
      var info = stat()
      guard fstat(descriptor, &info) == 0,
        DiaryFileIdentity.versionIdentity(info) == binding.identity,
        binding.directory
          || !Self.hasConflict(binding.components.reduce(root) { $0.appendingPathComponent($1) })
      else { throw CatalogIssue.changed }
    }
  }

  private func orphan(
    _ candidate: CatalogCandidate, root: URL, control: CatalogReadControl
  ) throws -> CatalogReadValue {
    guard let stem = candidate.components.last, let parsed = Self.currentStem(stem) else {
      return failure(.missingMarkdown, version: "missing-markdown")
    }
    let parent = Array(candidate.components.dropLast())
    let audio = try CatalogAudioInspector.inspect(
      root: root, components: parent + [stem + ".assets", parsed.id.description + ".m4a"],
      maximumDuration: 301, control: control)
    return failure(.missingMarkdown, version: audio.version, hasAudio: true)
  }

  func failure(
    _ issue: CatalogIssue, version: String, payload: (any CatalogDetailPayload)? = nil,
    hasText: Bool = false, hasAudio: Bool = false
  ) -> CatalogReadValue {
    CatalogReadValue(
      version: version, assetID: nil, createdAt: nil, title: nil, favorite: nil,
      payload: payload, issue: issue, hasText: hasText, hasAudio: hasAudio)
  }

  private static func recoveryText(_ bytes: Data) -> CatalogRecoveryText? {
    guard let text = String(data: bytes, encoding: .utf8), text.hasPrefix("---\n"),
      let end = text.range(
        of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex),
      text[..<end.upperBound].utf8.count <= DiarySnippetMarkdownCodec.maximumFrontMatterBytes + 5
    else { return nil }
    let body = String(text[end.upperBound...])
    guard body.utf8.count <= DiaryBody.maximumBytes else { return nil }
    return CatalogRecoveryText(body: body)
  }

  static func currentStem(_ stem: String) -> (id: AssetID, date: Date)? {
    guard stem.utf8.count == 56, let id = try? AssetID(String(stem.suffix(36))) else { return nil }
    let timestamp = String(stem.prefix(19)).replacingOccurrences(of: "_", with: "T")
    let datePart = String(timestamp.prefix(10))
    let timePart = String(timestamp.suffix(8)).replacingOccurrences(of: "-", with: ":")
    guard let instant = try? SchemaInstant(datePart + "T" + timePart + "Z") else { return nil }
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: instant.description),
      DiarySnippetLayout(id: id, createdAt: instant).markdownFilename == stem + ".md"
    else { return nil }
    return (id, date)
  }

  static func assetsExist(root: URL, parent: [String], name: String) throws -> Bool {
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: parent, directory: true)
    defer { Darwin.close(descriptor) }
    var info = stat()
    if fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
      if errno == ENOENT { return false }
      throw CatalogIssue.unavailable
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR else { throw CatalogIssue.unsafe }
    return true
  }

  static func hasConflict(_ url: URL) -> Bool {
    !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.isEmpty ?? true)
  }

  static func detail(
    _ snippet: DiarySnippetV1, date: Date, audioAvailable: Bool
  ) -> DiaryCatalogDetail {
    DiaryCatalogDetail(
      title: snippet.title, body: snippet.body.text, favorite: snippet.favorite,
      recordedAt: snippet.creationMethod == .manual ? nil : date,
      duration: snippet.recordingDurationMilliseconds.map { Double($0) / 1_000 },
      language: snippet.transcription?.languageHint,
      location: snippet.location.map {
        CatalogLocation(latitude: $0.latitude, longitude: $0.longitude, placeName: $0.placeName)
      },
      weather: snippet.weather.map {
        CatalogWeather(summary: $0.summary, temperatureCelsius: $0.temperatureCelsius)
      },
      audioAvailable: audioAvailable, isLegacy: false, assetID: snippet.id.description,
      isManual: snippet.creationMethod == .manual)
  }
}
