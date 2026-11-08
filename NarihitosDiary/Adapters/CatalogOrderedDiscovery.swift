import Foundation

struct CatalogDiscoveryBatch: Sendable {
  let candidates: [CatalogCandidate]
  let candidateVisits: Int
  let enumerationVisits: Int
}

/// Complete necessary sibling metadata before claiming a newest range. Contents stay demand-driven.
struct CatalogOrderedDiscovery: Sendable {
  private struct Frame: Sendable {
    let components: [String]
    let upperBound: Date?
    var cursor: CatalogDirectoryCursor?
    var children: [[String]] = []
  }

  private var frames = CatalogPriorityQueue<Frame> {
    if ($0.upperBound == nil) != ($1.upperBound == nil) { return $0.upperBound == nil }
    let left = $0.upperBound ?? .distantFuture
    let right = $1.upperBound ?? .distantFuture
    return left == right ? $0.components.count < $1.components.count : left > right
  }
  private var pending: [CatalogCandidate] = []
  private var pendingOffset = 0
  private var pendingUpperBound: Date? = .distantPast
  private var directoryProofs: [([String], String)] = []
  private var verifiedDirectories = 0
  private(set) var candidates: [String: CatalogCandidate] = [:]

  init() { frames.insert(Frame(components: [], upperBound: nil)) }

  var complete: Bool { frames.isEmpty && pendingOffset == pending.count }
  var coverageVerified: Bool { complete && verifiedDirectories == directoryProofs.count }

  var unexploredUpperBound: Date? {
    var bound = Date.distantPast
    if let first = frames.first {
      guard let upper = first.upperBound else { return nil }
      bound = max(bound, upper)
    }
    if pendingOffset < pending.count {
      guard let upper = pendingUpperBound else { return nil }
      bound = max(bound, upper)
    }
    return bound
  }

  mutating func advance(
    root: URL, registry: CatalogAssetRegistry, maximumCandidates: Int = 50
  ) throws -> CatalogDiscoveryBatch {
    guard (1...50).contains(maximumCandidates) else { throw CatalogIssue.unavailable }
    var visited = 0
    if pendingOffset == pending.count, var frame = frames.pop() {
      let cursor =
        try frame.cursor ?? CatalogDirectoryCursor(root: root, components: frame.components)
      frame.cursor = cursor
      let slice = try cursor.next(root: root, components: frame.components, maximum: 50)
      visited = slice.visited
      pending = []
      pendingOffset = 0
      for entry in slice.entries {
        let components = frame.components + [entry.name]
        pending += registry.candidates(components: components, safe: entry.safe)
        if entry.safe, entry.isDirectory, registry.descends(into: components) {
          frame.children.append(components)
        }
      }
      if slice.ended {
        directoryProofs.append((frame.components, slice.version))
        for child in frame.children {
          frames.insert(
            Frame(components: child, upperBound: registry.unexploredDateUpperBound(in: child)))
        }
      } else {
        frames.insert(frame)
      }
    }
    let end = min(pendingOffset + maximumCandidates, pending.count)
    var updates: [CatalogCandidate] = []
    for candidate in pending[pendingOffset..<end] {
      if let previous = candidates[candidate.key], !previous.safe { continue }
      if candidates[candidate.key] != candidate {
        candidates[candidate.key] = candidate
        updates.append(candidate)
      }
    }
    let candidateVisits = end - pendingOffset
    pendingOffset = end
    updatePendingBound(registry)
    return CatalogDiscoveryBatch(
      candidates: updates, candidateVisits: candidateVisits, enumerationVisits: visited)
  }

  private mutating func updatePendingBound(_ registry: CatalogAssetRegistry) {
    pendingUpperBound = .distantPast
    for candidate in pending[pendingOffset...] {
      guard registry.handler(candidate.handler)?.mayAppearInTimeline(candidate) != false else {
        continue
      }
      guard let date = candidate.date else {
        pendingUpperBound = nil
        break
      }
      let exclusive = Date(
        timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.nextUp)
      pendingUpperBound = max(pendingUpperBound ?? .distantPast, exclusive)
    }
  }

  mutating func verifyCoverage(root: URL) throws -> Int {
    guard complete else { return 0 }
    let end = min(verifiedDirectories + 50, directoryProofs.count)
    let start = verifiedDirectories
    while verifiedDirectories < end {
      let (components, version) = directoryProofs[verifiedDirectories]
      guard try CatalogSafeFiles.directoryVersion(root: root, components: components) == version
      else {
        throw CatalogIssue.changed
      }
      verifiedDirectories += 1
    }
    return end - start
  }
}
