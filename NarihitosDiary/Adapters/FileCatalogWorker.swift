import CryptoKit
import Darwin
import Foundation

actor FileCatalogWorker {
  private struct Observation: Sendable {
    let candidate: CatalogCandidate
    let handle: CatalogItemHandle
    let fileVersion: String
  }

  let session: CatalogSessionID
  private let registry: CatalogAssetRegistry
  private var index = CatalogDirectoryIndex()
  private var ordered: [CatalogCandidate]?
  private var nextIndex = 0
  private var cursor: CatalogCursor
  private var observations: [UUID: Observation] = [:]
  private var resources: [String: UUID] = [:]
  private var resourceOrders: [String: String] = [:]
  private var rootIdentity: String?

  init(session: CatalogSessionID, cursor: CatalogCursor, registry: CatalogAssetRegistry) {
    self.session = session
    self.cursor = cursor
    self.registry = registry
  }

  func page(_ requested: CatalogCursor, root: URL) async throws -> CatalogPage {
    guard requested == cursor, requested.session == session else { throw CatalogIssue.changed }
    try verifyRoot(root)
    try Task.checkCancellation()
    if !index.complete { return try await discover(root) }
    var summaries: [CatalogSummary] = []
    var recovery: [CatalogRecovery] = []
    let candidates = ordered ?? []
    let end = min(nextIndex + 50, candidates.count)
    let start = nextIndex
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while nextIndex < end {
      try Task.checkCancellation()
      let candidate = candidates[nextIndex]
      guard let handler = registry.handler(candidate.handler) else {
        throw CatalogIssue.unsupported
      }
      let read = try await readCandidate(candidate, handler: handler, root: root)
      let handle = observe(candidate, read: read)
      if let issue = read.issue {
        recovery.append(
          CatalogRecovery(
            handle: handle, issue: issue, hasText: read.hasText, hasAudio: read.hasAudio))
      } else if let title = read.title, let date = read.createdAt {
        summaries.append(
          CatalogSummary(
            handle: handle, assetID: read.assetID,
            resourceOrder: resourceOrders[candidate.key] ?? Self.resourceOrder(candidate.key),
            createdAt: date, title: title,
            favorite: read.favorite))
      }
      nextIndex += 1
      if ContinuousClock.now >= deadline { break }
    }
    try verifyRoot(root)
    cursor = CatalogCursor(session: session, token: UUID())
    return CatalogPage(
      session: session, summaries: summaries, recovery: recovery,
      continuation: nextIndex < candidates.count ? cursor : nil,
      examinedCandidates: nextIndex - start, isDiscovering: false)
  }

  private func discover(_ root: URL) async throws -> CatalogPage {
    let snapshot = index
    let registry = registry
    let intent = NSFileAccessIntent.readingIntent(with: root, options: [])
    let result = try await BoundedFileCoordinator().perform(
      intents: [intent], timeout: .seconds(15)
    ) { urls in
      guard let root = urls.first else { throw CatalogIssue.unavailable }
      var updated = snapshot
      let count = try updated.advance(root: root, registry: registry)
      return (updated, count)
    }
    index = result.0
    if index.complete { prepareOrdering() }
    cursor = CatalogCursor(session: session, token: UUID())
    return CatalogPage(
      session: session, summaries: [], recovery: [], continuation: cursor,
      examinedCandidates: result.1, isDiscovering: true)
  }

  private func prepareOrdering() {
    for candidate in index.candidates.values {
      resources[candidate.key] = UUID()
      resourceOrders[candidate.key] = Self.resourceOrder(candidate.key)
    }
    let resourceOrders = resourceOrders
    ordered = index.candidates.values.sorted { left, right in
      if left.date != right.date {
        return (left.date ?? .distantPast) > (right.date ?? .distantPast)
      }
      let leftResource = resourceOrders[left.key] ?? ""
      let rightResource = resourceOrders[right.key] ?? ""
      let leftID = left.stableID.isEmpty ? leftResource : left.stableID
      let rightID = right.stableID.isEmpty ? rightResource : right.stableID
      return leftID == rightID ? leftResource < rightResource : leftID < rightID
    }
  }

  private static func resourceOrder(_ key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func readCandidate(
    _ candidate: CatalogCandidate, handler: any CatalogAssetHandler, root: URL
  ) async throws -> CatalogReadValue {
    do { return try await handler.read(candidate, root: root) } catch is CancellationError {
      throw CancellationError()
    } catch {
      return CatalogReadValue(
        version: "unavailable", assetID: nil, createdAt: nil, title: nil,
        favorite: nil, payload: nil, issue: (error as? CatalogIssue) ?? .unavailable,
        hasText: false, hasAudio: false)
    }
  }

  func detail(_ handle: CatalogItemHandle, root: URL) async throws -> CatalogDetail {
    guard handle.session == session, let observed = observations[handle.resource],
      observed.handle == handle, let handler = registry.handler(handle.kind)
    else { throw CatalogIssue.changed }
    try verifyRoot(root)
    let read = try await handler.read(observed.candidate, root: root)
    guard read.version == observed.fileVersion, let payload = read.payload else {
      throw read.issue ?? CatalogIssue.changed
    }
    try verifyRoot(root)
    return CatalogDetail(handle: handle, payload: payload)
  }

  // swiftlint:disable opening_brace
  func actionResource(_ handle: CatalogItemHandle, root: URL) async throws -> CatalogActionResource
  {
    guard index.complete, handle.session == session,
      let observation = observations[handle.resource], observation.handle == handle,
      handle.kind == DiarySnippetSupportPolicy.kind
    else { throw CatalogIssue.changed }
    let candidate = observation.candidate
    if !candidate.stableID.isEmpty {
      let claims = index.candidates.values.filter { $0.stableID == candidate.stableID }
      guard claims.count == 1 else { throw CatalogIssue.duplicateID }
    }
    _ = try await detail(handle, root: root)
    return CatalogActionResource(candidate: candidate, version: observation.fileVersion)
  }
  // swiftlint:enable opening_brace

  private func observe(_ candidate: CatalogCandidate, read: CatalogReadValue) -> CatalogItemHandle {
    let resource = resources[candidate.key] ?? UUID()
    resources[candidate.key] = resource
    if let prior = observations[resource], prior.fileVersion == read.version { return prior.handle }
    let handle = CatalogItemHandle(
      session: session, resource: resource, version: UUID(), kind: candidate.handler)
    observations[resource] = Observation(
      candidate: candidate, handle: handle, fileVersion: read.version)
    return handle
  }

  private func verifyRoot(_ root: URL) throws {
    let descriptor = try CatalogSafeFiles.descriptor(root: root, components: [], directory: true)
    defer { Darwin.close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw CatalogIssue.unavailable }
    let identity = "\(info.st_dev):\(info.st_ino)"
    guard rootIdentity == nil || rootIdentity == identity else { throw CatalogIssue.changed }
    rootIdentity = identity
  }
}
