import Foundation

enum CatalogScopeAccessFailure: Error { case changed }

/// User-requested access wins after the current accessor settles. Cancellation does not release it.
@MainActor
final class CatalogProviderAccess {
  private let destination: AppleDestinationService
  private let allowed: @MainActor () -> Bool
  private var generation = UUID()
  private var busy = false
  private var userRequests = 0
  private var admittedRequests = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var rootIdentity: String?

  init(destination: AppleDestinationService, allowed: @escaping @MainActor () -> Bool) {
    self.destination = destination
    self.allowed = allowed
  }

  func invalidate() {
    generation = UUID()
    rootIdentity = nil
    wake()
  }

  func bindRoot(_ identity: String) { rootIdentity = identity }

  func settled() async {
    while busy { await withCheckedContinuation { waiters.append($0) } }
  }

  func perform<Value: Sendable>(
    expectedID: DestinationID, userRequested: Bool,
    operation: (URL) async throws -> Value
  ) async throws -> Value {
    guard admittedRequests < 256 else { throw CatalogIssue.unavailable }
    admittedRequests += 1
    let epoch = generation
    if userRequested { userRequests += 1 }
    defer {
      admittedRequests -= 1
      if userRequested { userRequests -= 1 }
      wake()
    }
    while busy || (!userRequested && userRequests > 0) {
      await withCheckedContinuation { waiters.append($0) }
      try check(epoch)
    }
    try check(epoch)
    busy = true
    defer {
      busy = false
      wake()
    }
    let result = try await destination.withActiveCatalog(expectedID: expectedID) { root in
      try await verifyRoot(root)
      let result = try await operation(root)
      try await verifyRoot(root)
      return result
    }
    try check(epoch)
    return result
  }

  private func check(_ epoch: UUID) throws {
    try Task.checkCancellation()
    guard epoch == generation, allowed() else { throw CatalogScopeAccessFailure.changed }
  }

  private func verifyRoot(_ root: URL) async throws {
    guard let rootIdentity else { return }
    let actual: String
    do { actual = try await Task.detached { try PurgeFileTree.identity(root) }.value } catch {
      throw CatalogScopeAccessFailure.changed
    }
    guard actual == rootIdentity else { throw CatalogScopeAccessFailure.changed }
  }

  private func wake() {
    let waiting = waiters
    waiters.removeAll()
    for waiter in waiting { waiter.resume() }
  }
}
