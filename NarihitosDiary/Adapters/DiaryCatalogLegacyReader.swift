import Foundation

extension DiaryCatalogHandler {
  func legacy(
    _ bytes: Data, candidate: CatalogCandidate, root: URL, version: String,
    control: CatalogReadControl
  ) throws -> CatalogReadValue {
    guard let stem = candidate.components.last else { throw CatalogIssue.malformed }
    let parent = Array(candidate.components.dropLast())
    let legacy = try LegacyDiaryReader.decode(bytes, stem: stem)
    let expectedDay = String(stem.prefix(10)).replacingOccurrences(of: "-", with: "/")
    guard parent.joined(separator: "/") == expectedDay else { throw CatalogIssue.malformed }
    let title = DiaryTitlePolicy.fallback(legacy.body).text
    let textDetail = Self.legacyDetail(legacy, title: title, audio: nil)
    do {
      guard try Self.assetsExist(root: root, parent: parent, name: stem + ".assets") else {
        throw CatalogIssue.missingAudio
      }
    } catch let issue as CatalogIssue {
      return failure(issue, version: version, payload: textDetail, hasText: true)
    }
    let assets = parent + [stem + ".assets"]
    let sibling: (name: String, version: String)
    do {
      sibling = try legacySibling(root: root, assets: assets, control: control)
    } catch let issue as CatalogIssue {
      return failure(issue, version: version, payload: textDetail, hasText: true)
    }
    let audio: CatalogAudioInspection?
    do {
      audio = try CatalogAudioInspector.inspect(
        root: root, components: assets + [sibling.name], maximumDuration: 3_600, control: control)
    } catch CatalogIssue.invalidAudio { audio = nil }
    let audioURL = (assets + [sibling.name]).reduce(root) { $0.appendingPathComponent($1) }
    guard !Self.hasConflict(audioURL) else {
      return failure(.conflict, version: version, payload: textDetail, hasText: true)
    }
    var result = CatalogReadValue(
      version: version + ":" + (audio?.version ?? "audio-unavailable"), assetID: nil,
      createdAt: legacy.createdAt, title: title, favorite: nil,
      payload: Self.legacyDetail(legacy, title: title, audio: audio),
      issue: nil, hasText: true, hasAudio: audio != nil)
    result.files = [
      CatalogFileBinding(components: assets, identity: sibling.version, directory: true)
    ]
    if let audio {
      result.files += [
        CatalogFileBinding(
          components: assets + [sibling.name], identity: String(audio.version.prefix(64)))
      ]
    }
    return result
  }

  func legacySibling(
    root: URL, assets: [String], control: CatalogReadControl
  ) throws -> (name: String, version: String) {
    let cursor = try CatalogDirectoryCursor(root: root, components: assets)
    var siblings: [String] = []
    var version = ""
    while true {
      try control.check()
      let slice = try cursor.next(root: root, components: assets, maximum: 50)
      version = slice.version
      for entry in slice.entries where entry.name.hasSuffix(".m4a") {
        guard entry.safe, !entry.isDirectory else { throw CatalogIssue.unsafe }
        siblings.append(entry.name)
        guard siblings.count < 2 else { throw CatalogIssue.ambiguousAudio }
      }
      if slice.ended { break }
    }
    guard let sibling = siblings.first else { throw CatalogIssue.missingAudio }
    return (sibling, version)
  }
  private static func legacyDetail(
    _ legacy: LegacyDiaryValue, title: String, audio: CatalogAudioInspection?
  ) -> DiaryCatalogDetail {
    DiaryCatalogDetail(
      title: title, body: legacy.body, favorite: nil, recordedAt: legacy.createdAt,
      duration: audio?.duration, language: legacy.language, location: legacy.location,
      weather: legacy.weather, audioAvailable: audio != nil, isLegacy: true)
  }

}
