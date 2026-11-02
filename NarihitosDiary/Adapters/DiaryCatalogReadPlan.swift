import Foundation

struct CatalogPlannedRead: Sendable {
  let metadata: [[String]]
  let files: [[String]]
  let audio: Set<[String]>
}

extension DiaryCatalogHandler {
  /// Directory coordination does not coordinate individual child-file contents.
  /// Discover confined targets without reading their bytes, then coordinate the
  /// exact Markdown/audio resources together so cloud downloads can settle.
  func planRead(
    _ candidate: CatalogCandidate, root: URL, control: CatalogReadControl
  ) throws -> CatalogPlannedRead {
    guard candidate.safe, let stem = candidate.components.last else { throw CatalogIssue.unsafe }
    let parent = Array(candidate.components.dropLast())
    var metadata = [parent]
    var files: [[String]] = []
    var audio: Set<[String]> = []
    let markdown = parent + [stem + ".md"]
    if try CatalogSafeFiles.resourceExists(root: root, components: markdown) {
      files.append(markdown)
    }
    let assetsPresent: Bool
    do {
      assetsPresent = try Self.assetsExist(root: root, parent: parent, name: stem + ".assets")
    } catch CatalogIssue.unsafe {
      return CatalogPlannedRead(metadata: metadata, files: files, audio: audio)
    }
    if assetsPresent {
      let assets = parent + [stem + ".assets"]
      metadata.append(assets)
      if let parsed = Self.currentStem(stem) {
        let path = assets + [parsed.id.description + ".m4a"]
        if try CatalogSafeFiles.resourceExists(root: root, components: path) { audio.insert(path) }
      } else if LegacyDiaryReader.stemDate(stem) != nil {
        do {
          let sibling = try legacySibling(root: root, assets: assets, control: control)
          audio.insert(assets + [sibling.name])
        } catch let issue as CatalogIssue {
          guard issue == .missingAudio || issue == .ambiguousAudio || issue == .unsafe else {
            throw issue
          }
        }
      }
    }
    files += audio.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
    return CatalogPlannedRead(metadata: metadata, files: files, audio: audio)
  }

  func coordinatedRead(
    _ candidate: CatalogCandidate, root: URL, control: CatalogReadControl
  ) async throws -> CatalogReadValue {
    let metadata = NSFileAccessIntent.readingIntent(
      with: root, options: .immediatelyAvailableMetadataOnly)
    let plan = try await BoundedFileCoordinator().perform(
      intents: [metadata], timeout: .seconds(15)
    ) { urls in
      guard let root = urls.first else { throw CatalogIssue.unavailable }
      return try planRead(candidate, root: root, control: control)
    }
    control.allowAudio(plan.audio)
    let metadataPaths = [[]] + plan.metadata
    let paths = metadataPaths + plan.files
    let intents = paths.enumerated().map { index, components in
      NSFileAccessIntent.readingIntent(
        with: components.reduce(root) { $0.appendingPathComponent($1) },
        options: index < metadataPaths.count ? .immediatelyAvailableMetadataOnly : [])
    }
    return try await BoundedFileCoordinator().perform(
      intents: intents, timeout: .seconds(120)
    ) { urls in
      guard let coordinatedRoot = urls.first, urls.count == paths.count else {
        throw CatalogIssue.unavailable
      }
      for (components, coordinated) in zip(paths, urls) {
        let expected = components.reduce(coordinatedRoot) { $0.appendingPathComponent($1) }
        guard expected.standardizedFileURL == coordinated.standardizedFileURL else {
          throw CatalogIssue.changed
        }
      }
      return try readCoordinated(candidate, root: coordinatedRoot, control: control)
    }
  }
}
