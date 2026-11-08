import Foundation

final class CatalogWorkerLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  func cancel() { lock.withLock { cancelled = true } }
  func check() throws {
    guard !lock.withLock({ cancelled }), !Task.isCancelled else { throw CancellationError() }
  }
}

struct CatalogReconciliationProgress: Sendable {
  let candidateVisits: Int
  let enumerationVisits: Int
  let metadataComplete: Bool
  let demandSatisfied: Bool
  let exhausted: Bool
}

struct CatalogReconciliationState {
  struct Queued: Sendable {
    let candidate: CatalogCandidate
    let key: CatalogTimelineKey
    let orderKnown: Bool
    let potential: Bool
  }
  struct Observation: Sendable {
    let candidate: CatalogCandidate
    let handle: CatalogItemHandle
    let version: String
  }

  let session: CatalogSessionID
  var discovery = CatalogOrderedDiscovery()
  var queue = CatalogPriorityQueue<Queued> {
    if $0.potential != $1.potential { return $0.potential }
    if $0.orderKnown != $1.orderKnown { return !$0.orderKnown }
    return $0.key.precedes($1.key)
  }
  var processed: Set<String> = []
  var metadataQueue = CatalogPriorityQueue<Queued> { $0.key.precedes($1.key) }
  var claims: [String: Set<UUID>] = [:]
  var metadata: [UUID: CatalogCandidate] = [:]
  var observations: [UUID: Observation] = [:]
  var current = CatalogCollection()
  var scan: CatalogIndexScanStamp?
  var scanFinished = false
  var rootIdentity: String?
  var preparationProgress: (key: String, token: any CatalogReadPreparation)?

  mutating func enqueue(_ candidate: CatalogCandidate, registry: CatalogAssetRegistry) {
    let handler = registry.handler(candidate.handler)
    let order = SQLiteCatalogIndex.resourceOrder(candidate)
    let queued = Queued(
      candidate: candidate,
      key: CatalogTimelineKey(
        instant: candidate.date ?? .distantFuture,
        sortID: candidate.stableID.isEmpty ? order : candidate.stableID, resourceOrder: order),
      orderKnown: handler?.hasKnownTimelineOrder(candidate) == true,
      potential: handler?.mayAppearInTimeline(candidate) == true)
    if !candidate.safe || !queued.potential {
      metadataQueue.insert(queued)
    } else {
      queue.insert(queued)
    }
  }

  var nextQueued: Queued? { metadataQueue.first ?? queue.first }
  mutating func popNext() { _ = metadataQueue.isEmpty ? queue.pop() : metadataQueue.pop() }

  func proven(_ summary: CatalogSummary) -> Bool {
    guard let bound = discovery.unexploredUpperBound, summary.createdAt >= bound else {
      return false
    }
    guard let next = queue.first, next.potential else { return true }
    guard next.orderKnown else { return false }
    let key = CatalogTimelineKey(
      instant: summary.createdAt, sortID: summary.assetID ?? summary.resourceOrder,
      resourceOrder: summary.resourceOrder)
    return key == next.key || key.precedes(next.key)
  }

  var provenCount: Int {
    current.summaries.values.filter { current.recovery[$0.id] == nil && proven($0) }.count
  }

  var provenSummaries: [CatalogSummary] { current.ordered.filter(proven) }

  mutating func observe(
    _ candidate: CatalogCandidate, read: CatalogReadValue, rowID: CatalogRowID
  ) -> CatalogItemHandle {
    let resource = rowID.rawValue
    let previous = observations[resource]
    let handle: CatalogItemHandle
    if let previous, previous.version == read.version {
      handle = previous.handle
    } else {
      handle = CatalogItemHandle(
        session: session, resource: resource, version: UUID(), kind: candidate.handler)
    }
    observations[resource] = Observation(
      candidate: candidate, handle: handle, version: read.version)
    if let issue = read.issue {
      mergeRecovery(handle, issue: issue, text: read.hasText, audio: read.hasAudio)
    } else if let title = read.title, let date = read.createdAt {
      let summary = CatalogSummary(
        handle: handle, assetID: read.assetID,
        resourceOrder: SQLiteCatalogIndex.resourceOrder(candidate),
        createdAt: date, title: title, favorite: read.favorite)
      current.merge(
        CatalogPage(
          session: session, summaries: [summary], recovery: [], continuation: nil,
          examinedCandidates: 1, isDiscovering: false))
    }
    return handle
  }

  mutating func mergeRecovery(
    _ handle: CatalogItemHandle, issue: CatalogIssue, text: Bool = false, audio: Bool = false
  ) {
    let recovery = CatalogRecovery(handle: handle, issue: issue, hasText: text, hasAudio: audio)
    current.merge(
      CatalogPage(
        session: session, summaries: [], recovery: [recovery], continuation: nil,
        examinedCandidates: 1, isDiscovering: false))
  }
}
