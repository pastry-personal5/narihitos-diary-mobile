import Foundation

extension DiaryCatalogHandler {
  func current(
    _ snippet: DiarySnippetV1, candidate: CatalogCandidate, root: URL, version: String,
    control: CatalogReadControl
  ) throws -> CatalogReadValue {
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let parent = Array(candidate.components.dropLast())
    guard let stem = candidate.components.last, parent == layout.directoryComponents,
      stem + ".md" == layout.markdownFilename, snippet.audioFilename == layout.audioFilename,
      let date = Self.currentStem(stem)?.date
    else { return failure(.malformed, version: version, hasText: true) }
    let audioComponents = parent + [layout.assetsDirectoryName, layout.audioFilename]
    let detail = Self.detail(snippet, date: date, audioAvailable: false)
    let audio: CatalogAudioInspection
    do {
      guard try Self.assetsExist(root: root, parent: parent, name: layout.assetsDirectoryName),
        try CatalogSafeFiles.resourceExists(root: root, components: audioComponents)
      else { throw CatalogIssue.missingAudio }
      audio = try CatalogAudioInspector.inspect(
        root: root, components: audioComponents, maximumDuration: 301, control: control)
      let actualDigest = audio.version.split(separator: ":").last.map(String.init)
      if let digest = snippet.audioSHA256, actualDigest != digest {
        throw CatalogIssue.invalidAudio
      }
    } catch let issue as CatalogIssue {
      return failure(issue, version: version, payload: detail, hasText: true)
    }
    let audioURL = audioComponents.reduce(root) { $0.appendingPathComponent($1) }
    guard !Self.hasConflict(audioURL) else {
      return failure(
        .conflict, version: version + audio.version, payload: detail, hasText: true, hasAudio: true)
    }
    var result = CatalogReadValue(
      version: version + ":" + audio.version, assetID: snippet.id.description,
      createdAt: date, title: snippet.title, favorite: snippet.favorite,
      payload: Self.detail(snippet, date: date, audioAvailable: true),
      issue: nil, hasText: true, hasAudio: true)
    result.files = [
      CatalogFileBinding(components: audioComponents, identity: String(audio.version.prefix(64)))
    ]
    return result
  }
}
