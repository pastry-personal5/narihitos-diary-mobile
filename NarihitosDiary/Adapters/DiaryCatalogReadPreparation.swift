import Foundation

struct CatalogLegacySiblingProof: CatalogReadPreparation {
  let rootIdentity: String
  let components: [String]
  let version: String
  let name: String?
  let issue: CatalogIssue?
}

private struct CatalogLegacySiblingScan: CatalogReadPreparation {
  let rootIdentity: String
  let candidateKey: String
  let components: [String]
  let cursor: CatalogDirectoryCursor
  var name: String?
}

extension DiaryCatalogHandler {
  func prepareRead(
    _ candidate: CatalogCandidate, root: URL, continuation: (any CatalogReadPreparation)?
  ) async throws -> CatalogReadPreparationResult {
    guard candidate.safe, let stem = candidate.components.last,
      LegacyDiaryReader.stemDate(stem) != nil
    else { return .ready(nil, visits: 0) }
    let components = Array(candidate.components.dropLast()) + [stem + ".assets"]
    return try await BoundedFileCoordinator().perform(
      intents: [.readingIntent(with: root, options: .immediatelyAvailableMetadataOnly)],
      timeout: .seconds(15)
    ) { urls in
      guard let root = urls.first else { throw CatalogIssue.unavailable }
      do {
        guard
          try Self.assetsExist(
            root: root, parent: Array(components.dropLast()), name: stem + ".assets")
        else { return .ready(nil, visits: 0) }
      } catch CatalogIssue.unsafe { return .ready(nil, visits: 0) }
      let identity = try PurgeFileTree.identity(root)
      var scan: CatalogLegacySiblingScan
      if let previous = continuation {
        guard let previous = previous as? CatalogLegacySiblingScan,
          previous.rootIdentity == identity, previous.candidateKey == candidate.key,
          previous.components == components
        else { throw CatalogIssue.changed }
        scan = previous
      } else {
        scan = CatalogLegacySiblingScan(
          rootIdentity: identity, candidateKey: candidate.key, components: components,
          cursor: try CatalogDirectoryCursor(root: root, components: components))
      }
      let slice = try scan.cursor.next(root: root, components: components, maximum: 50)
      var issue: CatalogIssue?
      for entry in slice.entries where entry.name.hasSuffix(".m4a") {
        if !entry.safe || entry.isDirectory {
          issue = .unsafe
          break
        }
        if scan.name != nil {
          issue = .ambiguousAudio
          break
        }
        scan.name = entry.name
      }
      if issue != nil || slice.ended {
        let proof = CatalogLegacySiblingProof(
          rootIdentity: identity, components: components, version: slice.version, name: scan.name,
          issue: issue ?? (scan.name == nil ? .missingAudio : nil))
        return .ready(proof, visits: slice.visited)
      }
      return .progress(scan, visits: slice.visited)
    }
  }

  func readPrepared(
    _ candidate: CatalogCandidate, root: URL, preparation: (any CatalogReadPreparation)?
  ) async throws -> CatalogReadValue {
    var prepared = self
    if let preparation {
      guard let proof = preparation as? CatalogLegacySiblingProof else {
        throw CatalogIssue.changed
      }
      prepared.preparedLegacy = proof
    }
    return try await prepared.read(candidate, root: root)
  }
}
