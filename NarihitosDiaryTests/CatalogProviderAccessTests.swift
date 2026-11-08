import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct CatalogProviderAccessTests {
  @Test func queuedAdmissionIsBoundedAndCancellationKeepsActualLoan() async throws {
    let root = try makeReconciliationFixture([3: 1])
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IndexedCatalogDestinationStore()
    let platform = IndexedCatalogDestinationPlatform(root: root)
    let destination = AppleDestinationService(repository: store, platform: platform)
    let id = try #require(await destination.activeDestination().summary?.id)
    let access = CatalogProviderAccess(destination: destination, allowed: { true })
    var held: CheckedContinuation<Void, Never>?
    let owner = Task {
      try await access.perform(expectedID: id, userRequested: false) { _ in
        await withCheckedContinuation { held = $0 }
      }
    }
    try await wait { held != nil }
    var entered = 0
    let queued = (0..<255).map { _ in
      Task {
        entered += 1
        try await access.perform(expectedID: id, userRequested: true) { _ in
          _ = Issue.record("An invalidated queued operation must never borrow the root")
        }
      }
    }
    try await wait { entered == 255 }
    await #expect(throws: CatalogIssue.unavailable) {
      try await access.perform(expectedID: id, userRequested: true) { _ in }
    }
    access.invalidate()
    var settled = false
    let cleanup = Task {
      await access.settled()
      settled = true
    }
    await Task.yield()
    #expect(!settled)
    #expect(platform.activeLoans == 1)
    held?.resume()
    await #expect(throws: CatalogScopeAccessFailure.self) { try await owner.value }
    for task in queued {
      await #expect(throws: CatalogScopeAccessFailure.self) { try await task.value }
    }
    await cleanup.value
    #expect(platform.maximumLoans == 1)
    #expect(platform.starts == platform.stops)
  }

  @Test func userRequestPrecedesBackgroundAfterCurrentAccessorSettles() async throws {
    let root = try makeReconciliationFixture([3: 1])
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IndexedCatalogDestinationStore()
    let destination = AppleDestinationService(
      repository: store, platform: IndexedCatalogDestinationPlatform(root: root))
    let id = try #require(await destination.activeDestination().summary?.id)
    let access = CatalogProviderAccess(destination: destination, allowed: { true })
    var held: CheckedContinuation<Void, Never>?
    let first = Task {
      try await access.perform(expectedID: id, userRequested: false) { _ in
        await withCheckedContinuation { held = $0 }
      }
    }
    try await wait { held != nil }
    var visits: [String] = []
    var entered = 0
    let background = Task {
      entered += 1
      try await access.perform(expectedID: id, userRequested: false) { _ in
        visits.append("background")
      }
    }
    let user = Task {
      entered += 1
      try await access.perform(expectedID: id, userRequested: true) { _ in visits.append("user") }
    }
    try await wait { entered == 2 }
    held?.resume()
    try await first.value
    try await user.value
    try await background.value
    #expect(visits == ["user", "background"])
  }

  private func wait(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<1_000 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Synthetic accessor did not reach the expected state")
  }
}
