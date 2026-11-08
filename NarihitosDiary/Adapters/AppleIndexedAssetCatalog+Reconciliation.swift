import Foundation

extension AppleIndexedAssetCatalog {
  func fallbackAfterStartFailure(_ error: Error, generation: UUID) async -> CatalogStart {
    guard generation == epoch else { return .unavailable }
    guard environment.allowed, !Task.isCancelled else {
      end()
      return .unavailable
    }
    if error is CatalogScopeAccessFailure || error is DestinationValidationError {
      end()
      return .unavailable
    }
    worker?.lifetime.cancel()
    worker = nil
    if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
    presenter = nil
    scope = nil
    initialPage = nil
    await index.suspend()
    projectionDisabled = true
    usingFallback = true
    return await fallback.begin()
  }

  func prepare(
    root: URL, installation: String, record: StoredDestinationRecord, session: CatalogSessionID,
    generation: UUID
  ) async throws -> (CatalogIndexScope, CatalogIndexPage) {
    let identity = try await Task.detached { try PurgeFileTree.identity(root) }.value
    guard generation == epoch else { throw CatalogIssue.changed }
    try verifyPurgeGeneration()
    guard let purgeGeneration else { throw CatalogScopeAccessFailure.changed }
    access.bindRoot(identity)
    let key = try Self.scopeKey(
      installation: installation, record: record, rootIdentity: identity,
      purgeGeneration: purgeGeneration)
    let scope = CatalogIndexScope(key: key, validatorRevision: 1)
    let page = try await index.page(scope: scope, after: nil)
    guard generation == epoch else { throw CatalogIssue.changed }
    try verifyPurgeGeneration()
    let created = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: session)
    worker = created
    try await created.begin(expectedRootIdentity: identity)
    guard generation == epoch else {
      created.lifetime.cancel()
      throw CatalogIssue.changed
    }
    let presenterID = UUID()
    let observer = CatalogFolderPresenter(id: presenterID, root: root) { [weak self] in
      Task { @MainActor [weak self] in self?.providerChanged(presenterID: presenterID) }
    }
    presenter = observer
    NSFileCoordinator.addFilePresenter(observer)
    rootIdentity = identity
    return (scope, page)
  }

  func currentAccess<Value: Sendable>(
    _ id: DestinationID, operation: (URL) async throws -> Value
  ) async throws -> Value {
    let generation = epoch
    do {
      try verifyPurgeGeneration()
      let value = try await access.perform(
        expectedID: id, userRequested: true, operation: operation)
      try verifyPurgeGeneration()
      return value
    } catch {
      let accessLost =
        !environment.allowed || error is CatalogScopeAccessFailure
        || error is DestinationValidationError
      if generation == epoch, accessLost {
        end()
        onEvent?(.accessChanged)
      }
      throw error
    }
  }

  func verifyRoot(_ root: URL) async throws {
    try verifyPurgeGeneration()
    let observed = try await Task.detached { try PurgeFileTree.identity(root) }.value
    guard observed == rootIdentity else { throw CatalogScopeAccessFailure.changed }
  }

  func verifyPurgeGeneration() throws {
    guard environment.allowed,
      let current = try? environment.projectionGeneration(), current == purgeGeneration
    else { throw CatalogScopeAccessFailure.changed }
  }

  func startPump(_ expected: CatalogReconciliationWorker, generation: UUID) {
    waitingForSweep = false
    pump = Task { [weak self] in
      guard let self else { return }
      while generation == epoch, worker === expected, !Task.isCancelled {
        do {
          guard let destinationID else { return }
          let progress = try await access.perform(
            expectedID: destinationID, userRequested: false
          ) { root in
            try verifyPurgeGeneration()
            return try await expected.step(root: root, demand: demand)
          }
          guard generation == epoch, worker === expected, !Task.isCancelled else { return }
          initialPage = nil
          projectionStatus = CatalogProjectionStatus(
            session: projectionStatus?.session ?? CatalogSessionID(),
            metadataComplete: progress.metadataComplete, demandSatisfied: progress.demandSatisfied,
            exhausted: progress.exhausted, recovery: await expected.recovery(),
            currentSummaries: await expected.summaries())
          onEvent?(.projectionChanged)
          if progress.metadataComplete && (progress.demandSatisfied || progress.exhausted) {
            retryAttempt = 0
            waitingForSweep = true
            try await environment.sleep(environment.sweepInterval)
            waitingForSweep = false
            try await access.perform(expectedID: destinationID, userRequested: false) { root in
              try await verifyRoot(root)
              try await expected.begin(expectedRootIdentity: rootIdentity)
            }
          } else {
            await Task.yield()
          }
        } catch {
          guard generation == epoch, worker === expected, !Task.isCancelled else { return }
          handlePumpFailure(error, expected: expected, generation: generation)
          return
        }
      }
    }
  }

  func handlePumpFailure(
    _ error: Error, expected: CatalogReconciliationWorker, generation: UUID
  ) {
    let accessLost =
      !environment.allowed || error is CatalogScopeAccessFailure
      || error is DestinationValidationError
    if accessLost {
      end()
      onEvent?(.accessChanged)
    } else if error is CatalogIndexFailure {
      projectionDisabled = true
      usesRememberedRows = false
      usingFallback = true
      expected.lifetime.cancel()
      onEvent?(.invalidated)
    } else {
      if let status = projectionStatus {
        projectionStatus = CatalogProjectionStatus(
          session: status.session, metadataComplete: false, demandSatisfied: false,
          exhausted: false, recovery: status.recovery, wait: .unavailable)
        onEvent?(.projectionChanged)
      }
      let delays = [1, 2, 5, 15, 30]
      let delay = delays[min(retryAttempt, delays.count - 1)]
      retryAttempt = min(retryAttempt + 1, delays.count - 1)
      scheduleRestart(after: .seconds(delay), generation: generation)
    }
  }

  func scheduleRestart(after delay: Duration, generation: UUID) {
    guard restart == nil else { return }
    let taskID = UUID()
    restartID = taskID
    restart = Task { [weak self] in
      guard let self else { return }
      defer {
        if restartID == taskID {
          restart = nil
          restartID = nil
        }
      }
      do {
        try await environment.sleep(delay)
        guard generation == epoch, let destinationID, let scope,
          let session = projectionStatus?.session
        else { return }
        await access.settled()
        let replacement = CatalogReconciliationWorker(
          index: index, scope: scope, registry: registry, session: session)
        worker = replacement
        try await access.perform(expectedID: destinationID, userRequested: false) { root in
          try await verifyRoot(root)
          try await index.invalidate(scope: scope)
          try await replacement.begin(expectedRootIdentity: rootIdentity)
        }
        guard generation == epoch, !Task.isCancelled else { return }
        startPump(replacement, generation: generation)
      } catch {
        guard generation == epoch, !Task.isCancelled else { return }
        if error is CatalogIndexFailure {
          projectionDisabled = true
          usesRememberedRows = false
          usingFallback = true
          worker?.lifetime.cancel()
          onEvent?(.invalidated)
          return
        }
        end()
        onEvent?(.accessChanged)
      }
    }
  }
}
