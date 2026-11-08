import Foundation

/// One active owner serializes metadata, demanded inspection, exact lookup and action binding.
actor CatalogReconciliationWorker {
  nonisolated let lifetime: CatalogWorkerLifetime
  private let index: SQLiteCatalogIndex
  private let scope: CatalogIndexScope
  private let registry: CatalogAssetRegistry
  private var state: CatalogReconciliationState
  private var busy = false

  init(
    index: SQLiteCatalogIndex, scope: CatalogIndexScope, registry: CatalogAssetRegistry,
    session: CatalogSessionID, lifetime: CatalogWorkerLifetime = CatalogWorkerLifetime()
  ) {
    self.index = index
    self.scope = scope
    self.registry = registry
    self.lifetime = lifetime
    state = CatalogReconciliationState(session: session)
  }

  func begin(expectedRootIdentity: String? = nil) async throws {
    try lifetime.check()
    guard !busy else { throw CatalogIssue.unavailable }
    busy = true
    defer { busy = false }
    let scan = try await index.beginScan(scope: scope)
    try lifetime.check()
    let observations = state.observations
    let rootIdentity = state.rootIdentity
    state = CatalogReconciliationState(session: state.session)
    state.observations = observations
    state.rootIdentity = expectedRootIdentity ?? rootIdentity
    state.scan = scan
  }

  func step(root: URL, demand: Int) async throws -> CatalogReconciliationProgress {
    try lifetime.check()
    guard !busy, let scan = state.scan else { throw CatalogIssue.unavailable }
    busy = true
    defer { busy = false }
    try verifyRoot(root)
    var candidateVisits = 0
    var enumerationVisits = 0
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while candidateVisits < 50, state.provenCount < demand || !state.metadataQueue.isEmpty {
      try lifetime.check()
      if let next = state.nextQueued, canInspect(next) {
        state.popNext()
        candidateVisits += 1
        guard !state.processed.contains(next.candidate.key),
          state.discovery.candidates[next.candidate.key] == next.candidate
        else { continue }
        let inspection = try await inspect(next, root: root)
        enumerationVisits += inspection.visits
        if !inspection.ready {
          state.queue.insert(next)
          break
        }
      } else {
        break
      }
      if enumerationVisits > 0 || ContinuousClock.now >= deadline { break }
    }
    let mayDiscover =
      !state.discovery.complete && candidateVisits < 50 && enumerationVisits == 0
      && ContinuousClock.now < deadline
    if mayDiscover {
      let batch = try await discover(root: root, budget: 50 - candidateVisits)
      candidateVisits += batch.candidateVisits
      enumerationVisits += batch.enumerationVisits
      guard candidateVisits <= 50 else { throw CatalogIssue.changed }
    } else if state.discovery.complete, !state.discovery.coverageVerified, enumerationVisits == 0 {
      enumerationVisits += try await verifyCoverage(root: root)
    } else if state.discovery.coverageVerified, !state.scanFinished, enumerationVisits == 0 {
      candidateVisits += try await reconcileMissing(
        root: root, scan: scan, budget: 50 - candidateVisits)
    }
    try lifetime.check()
    try verifyRoot(root)
    return CatalogReconciliationProgress(
      candidateVisits: candidateVisits, enumerationVisits: enumerationVisits,
      metadataComplete: state.scanFinished, demandSatisfied: state.provenCount >= demand,
      exhausted: state.scanFinished && state.queue.isEmpty && state.metadataQueue.isEmpty)
  }

  func summaries() -> [CatalogSummary] { state.provenSummaries }
  func recovery() -> [CatalogRecovery] { Array(state.current.recovery.values) }

  private func canInspect(_ item: CatalogReconciliationState.Queued) -> Bool {
    if !item.candidate.safe || !item.potential || !item.orderKnown { return true }
    guard let bound = state.discovery.unexploredUpperBound else { return false }
    return item.key.instant >= bound
  }

  private func inspect(
    _ item: CatalogReconciliationState.Queued, root: URL
  ) async throws -> (ready: Bool, visits: Int) {
    let candidate = item.candidate
    let stamp = try await index.bind(candidate, scope: scope)
    let read: CatalogReadValue
    var preparation: (any CatalogReadPreparation)?
    var visits = 0
    if !candidate.safe || !item.potential {
      read = Self.failure(candidate.safe ? .malformed : .unsafe)
    } else if (state.claims[candidate.stableID]?.count ?? 0) > 1 {
      read = Self.failure(.duplicateID)
    } else {
      switch try await prepare(candidate, root: root) {
      case .progress(let token, let count):
        state.preparationProgress = (candidate.key, token)
        return (false, count)
      case .ready(let token, let count):
        state.preparationProgress = nil
        preparation = token
        visits = count
      }
      if let failure = preparation as? CatalogReadPreparationFailure {
        read = Self.failure(failure.issue)
      } else {
        read = try await readCandidate(candidate, root: root, preparation: preparation)
      }
    }
    try lifetime.check()
    guard try await index.apply(read, to: stamp, scope: scope) else { throw CatalogIssue.changed }
    try lifetime.check()
    _ = state.observe(candidate, read: read, rowID: stamp.rowID)
    state.processed.insert(candidate.key)
    return (true, visits)
  }

  private func discover(root: URL, budget: Int) async throws -> CatalogDiscoveryBatch {
    let snapshot = state.discovery
    let registry = registry
    let result = try await BoundedFileCoordinator().perform(
      intents: [.readingIntent(with: root, options: .immediatelyAvailableMetadataOnly)],
      timeout: .seconds(15)
    ) { urls in
      guard let root = urls.first else { throw CatalogIssue.unavailable }
      var discovery = snapshot
      return try (
        discovery.advance(root: root, registry: registry, maximumCandidates: budget), discovery
      )
    }
    try lifetime.check()
    state.discovery = result.1
    let stamps = try await index.bindCandidates(result.0.candidates, scope: scope)
    guard let scan = state.scan,
      try await index.markSeen(stamps.map(\.rowID), scan: scan, scope: scope)
    else { throw CatalogIssue.changed }
    try lifetime.check()
    for (candidate, stamp) in zip(result.0.candidates, stamps) {
      state.metadata[stamp.rowID.rawValue] = candidate
      state.enqueue(candidate, registry: registry)
      acceptClaim(candidate, rowID: stamp.rowID)
    }
    return result.0
  }

  private func acceptClaim(_ candidate: CatalogCandidate, rowID: CatalogRowID) {
    guard !candidate.stableID.isEmpty else { return }
    state.claims[candidate.stableID, default: []].insert(rowID.rawValue)
    guard let claims = state.claims[candidate.stableID], claims.count > 1 else { return }
    for id in claims {
      if let previous = state.observations[id] {
        state.mergeRecovery(previous.handle, issue: .duplicateID)
      } else if let candidate = state.metadata[id] {
        _ = state.observe(candidate, read: Self.failure(.duplicateID), rowID: CatalogRowID(id))
      }
    }
  }

  private func verifyCoverage(root: URL) async throws -> Int {
    let snapshot = state.discovery
    let result = try await BoundedFileCoordinator().perform(
      intents: [.readingIntent(with: root, options: .immediatelyAvailableMetadataOnly)],
      timeout: .seconds(15)
    ) { urls in
      guard let root = urls.first else { throw CatalogIssue.unavailable }
      var discovery = snapshot
      return try (discovery.verifyCoverage(root: root), discovery)
    }
    try lifetime.check()
    state.discovery = result.1
    return result.0
  }

  private func reconcileMissing(
    root: URL, scan: CatalogIndexScanStamp, budget: Int
  ) async throws -> Int {
    guard budget > 0 else { return 0 }
    let resources = Array(try await index.unseen(scan: scan, scope: scope).prefix(budget))
    if resources.isEmpty {
      state.scanFinished = try await index.finishScan(scan, scope: scope)
      return 0
    }
    let registry = registry
    let presence = try await BoundedFileCoordinator().perform(
      intents: [.readingIntent(with: root, options: .immediatelyAvailableMetadataOnly)],
      timeout: .seconds(15)
    ) { urls in
      guard let root = urls.first else { throw CatalogIssue.unavailable }
      return try resources.map { resource in
        try registry.handler(resource.candidate.handler)?.presence(
          of: resource.candidate, root: root)
          ?? .unsafe
      }
    }
    try lifetime.check()
    var missing: [CatalogResourceStamp] = []
    var seen: [CatalogRowID] = []
    for (resource, presence) in zip(resources, presence) {
      if presence == .missing {
        missing.append(resource.stamp)
      } else {
        seen.append(resource.stamp.rowID)
        if presence == .unsafe {
          _ = try await index.apply(Self.failure(.unsafe), to: resource.stamp, scope: scope)
        }
      }
    }
    guard try await index.retire(missing, scan: scan, scope: scope),
      try await index.markSeen(seen, scan: scan, scope: scope)
    else { throw CatalogIssue.changed }
    for resource in missing { state.observations.removeValue(forKey: resource.rowID.rawValue) }
    return resources.count
  }

  private func readCandidate(
    _ candidate: CatalogCandidate, root: URL, preparation: (any CatalogReadPreparation)? = nil
  ) async throws -> CatalogReadValue {
    guard let handler = registry.handler(candidate.handler) else {
      return Self.failure(.unsupported)
    }
    do {
      let read = try await handler.readPrepared(candidate, root: root, preparation: preparation)
      if read.issue == nil {
        guard read.title != nil, read.createdAt != nil,
          candidate.date == nil || candidate.date == read.createdAt,
          candidate.stableID.isEmpty || candidate.stableID == read.assetID
        else { return Self.failure(.malformed) }
      }
      return read
    } catch is CancellationError {
      throw CancellationError()
    } catch { return Self.failure((error as? CatalogIssue) ?? .unavailable) }
  }

  private func verifyRoot(_ root: URL) throws {
    let identity = try PurgeFileTree.identity(root)
    guard state.rootIdentity == nil || state.rootIdentity == identity else {
      throw CatalogIssue.changed
    }
    state.rootIdentity = identity
  }

  private static func failure(_ issue: CatalogIssue) -> CatalogReadValue {
    CatalogReadValue(
      version: issue.rawValue, assetID: nil, createdAt: nil, title: nil, favorite: nil,
      payload: nil, issue: issue, hasText: false, hasAudio: false)
  }
}

extension CatalogReconciliationWorker {
  private func prepare(
    _ candidate: CatalogCandidate, root: URL
  ) async throws -> CatalogReadPreparationResult {
    guard let handler = registry.handler(candidate.handler) else { return .ready(nil, visits: 0) }
    let previous =
      state.preparationProgress?.key == candidate.key ? state.preparationProgress?.token : nil
    do {
      let result = try await handler.prepareRead(candidate, root: root, continuation: previous)
      try lifetime.check()
      return result
    } catch is CancellationError { throw CancellationError() } catch {
      return .ready(
        CatalogReadPreparationFailure(issue: (error as? CatalogIssue) ?? .unavailable), visits: 0)
    }
  }

  private func prepareDirect(
    _ candidate: CatalogCandidate, root: URL
  ) async throws -> (any CatalogReadPreparation)? {
    while true {
      switch try await prepare(candidate, root: root) {
      case .ready(let token, _):
        state.preparationProgress = nil
        if let failure = token as? CatalogReadPreparationFailure { throw failure.issue }
        return token
      case .progress(let token, _):
        state.preparationProgress = (candidate.key, token)
        await Task.yield()
      }
    }
  }

  func metadataIsComplete() -> Bool { state.scanFinished }

  func resolve(_ id: CatalogRowID, root: URL) async throws -> CatalogDetail {
    try lifetime.check()
    guard !busy else { throw CatalogIssue.unavailable }
    busy = true
    defer { busy = false }
    try verifyRoot(root)
    let candidate = try await index.locator(for: id, scope: scope)
    let stamp = try await index.bind(candidate, scope: scope)
    guard stamp.rowID == id else { throw CatalogIssue.changed }
    let preparation = try await prepareDirect(candidate, root: root)
    let read = try await readCandidate(candidate, root: root, preparation: preparation)
    try lifetime.check()
    guard try await index.apply(read, to: stamp, scope: scope) else { throw CatalogIssue.changed }
    try lifetime.check()
    let handle = state.observe(candidate, read: read, rowID: id)
    if let issue = read.issue { throw issue }
    if let assetID = read.assetID, (state.claims[assetID]?.count ?? 0) > 1 {
      throw CatalogIssue.duplicateID
    }
    guard let payload = read.payload else { throw CatalogIssue.unavailable }
    try lifetime.check()
    try verifyRoot(root)
    return CatalogDetail(handle: handle, payload: payload)
  }

  func detail(_ handle: CatalogItemHandle, root: URL) async throws -> CatalogDetail {
    try lifetime.check()
    guard !busy else { throw CatalogIssue.unavailable }
    busy = true
    defer { busy = false }
    return try await detailValue(handle, root: root).detail
  }

  func actionResource(
    _ handle: CatalogItemHandle, root: URL
  ) async throws -> CatalogActionResource {
    try lifetime.check()
    guard !busy, state.scanFinished, handle.kind == DiarySnippetSupportPolicy.kind else {
      throw CatalogIssue.changed
    }
    busy = true
    defer { busy = false }
    let fresh = try await detailValue(handle, root: root)
    guard let observation = state.observations[handle.resource] else { throw CatalogIssue.changed }
    return CatalogActionResource(
      candidate: observation.candidate, version: observation.version,
      preparation: fresh.preparation)
  }

  private func detailValue(
    _ handle: CatalogItemHandle, root: URL
  ) async throws -> (detail: CatalogDetail, preparation: (any CatalogReadPreparation)?) {
    guard handle.session == state.session, let observation = state.observations[handle.resource],
      observation.handle == handle
    else { throw CatalogIssue.changed }
    if let claims = state.claims[observation.candidate.stableID], claims.count > 1 {
      throw CatalogIssue.duplicateID
    }
    try verifyRoot(root)
    let preparation = try await prepareDirect(observation.candidate, root: root)
    let read = try await readCandidate(observation.candidate, root: root, preparation: preparation)
    try lifetime.check()
    guard read.version == observation.version, let payload = read.payload else {
      throw read.issue ?? CatalogIssue.changed
    }
    try verifyRoot(root)
    _ = state.observe(observation.candidate, read: read, rowID: CatalogRowID(handle.resource))
    return (CatalogDetail(handle: handle, payload: payload), preparation)
  }
}
