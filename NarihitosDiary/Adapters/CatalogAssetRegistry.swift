import Foundation

struct CatalogCandidate: Hashable, Sendable {
  let components: [String]
  let handler: String
  let date: Date?
  let stableID: String
  let safe: Bool
  var key: String { handler + ":" + components.joined(separator: "/") }
}

struct CatalogFileBinding: Sendable {
  let components: [String]
  let identity: String
  var directory = false
}

struct CatalogReadValue: Sendable {
  let version: String
  let assetID: String?
  let createdAt: Date?
  let title: String?
  let favorite: Bool?
  let payload: (any CatalogDetailPayload)?
  let issue: CatalogIssue?
  let hasText: Bool
  let hasAudio: Bool
  var files: [CatalogFileBinding] = []
}

protocol CatalogAssetHandler: Sendable {
  var kind: String { get }
  func descends(into components: [String]) -> Bool
  func candidate(components: [String], safe: Bool) -> CatalogCandidate?
  func read(_ candidate: CatalogCandidate, root: URL) async throws -> CatalogReadValue
}

struct CatalogAssetRegistry: Sendable {
  private var handlers: [String: any CatalogAssetHandler] = [:]

  mutating func register(_ handler: any CatalogAssetHandler) { handlers[handler.kind] = handler }
  func handler(_ kind: String) -> (any CatalogAssetHandler)? { handlers[kind] }
  func descends(into components: [String]) -> Bool {
    handlers.values.contains { $0.descends(into: components) }
  }
  func candidates(components: [String], safe: Bool) -> [CatalogCandidate] {
    handlers.values.compactMap { $0.candidate(components: components, safe: safe) }
  }
}

struct CatalogDirectoryIndex: Sendable {
  private struct Frame: Sendable {
    let components: [String]
    var cursor: CatalogDirectoryCursor?
  }
  private var stack = [Frame(components: [])]
  private(set) var candidates: [String: CatalogCandidate] = [:]
  var complete: Bool { stack.isEmpty }

  mutating func advance(root: URL, registry: CatalogAssetRegistry) throws -> Int {
    var remaining = 50
    while remaining > 0, var frame = stack.popLast() {
      let cursor =
        try frame.cursor ?? CatalogDirectoryCursor(root: root, components: frame.components)
      frame.cursor = cursor
      let slice = try cursor.next(root: root, components: frame.components, maximum: remaining)
      // Dots are included in the enumeration slice even though they are not candidates.
      remaining -= max(1, slice.visited)
      if !slice.ended { stack.append(frame) }
      for entry in slice.entries {
        let components = frame.components + [entry.name]
        for candidate in registry.candidates(components: components, safe: entry.safe) {
          if let previous = candidates[candidate.key], !previous.safe { continue }
          candidates[candidate.key] = candidate
        }
        if entry.safe, entry.isDirectory, registry.descends(into: components) {
          stack.append(Frame(components: components))
        }
      }
    }
    return 50 - max(0, remaining)
  }

}
