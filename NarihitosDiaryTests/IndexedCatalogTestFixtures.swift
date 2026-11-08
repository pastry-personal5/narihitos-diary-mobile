import Foundation

@testable import NarihitosDiary

@MainActor
final class IndexedCatalogDestinationStore: DestinationSettingsStore {
  var record: StoredDestinationRecord?
  init() {
    record = StoredDestinationRecord(
      id: DestinationID.make().rawValue, displayName: "Synthetic", bookmark: Data([1]),
      identityArchive: Data([2]), disclosureAcknowledged: true)
  }
  func loadDestination() -> StoredDestinationRecord? { record }
  func saveDestination(_ destination: StoredDestinationRecord) throws { record = destination }
}

@MainActor
final class IndexedCatalogDestinationPlatform: DestinationPlatform {
  var root: URL
  var identity = Data([2])
  var activeLoans = 0
  var maximumLoans = 0
  var starts = 0
  var stops = 0
  init(root: URL) { self.root = root }
  func startAccessing(_ url: URL) -> Bool {
    starts += 1
    activeLoans += 1
    maximumLoans = max(maximumLoans, activeLoans)
    return true
  }
  func stopAccessing(_ url: URL) {
    stops += 1
    activeLoans -= 1
  }
  func inspect(_ url: URL) throws -> DestinationCandidateInspection {
    DestinationCandidateInspection(
      facts: DestinationCandidateFacts(
        isDirectory: true, isSymbolicLink: false, isUbiquitousItem: true, hasICloudIdentity: true),
      displayName: "Synthetic")
  }
  func makeBookmark(for url: URL) throws -> Data { Data([1]) }
  func resolveBookmark(_ bookmark: Data) throws -> ResolvedDestinationBookmark {
    ResolvedDestinationBookmark(url: root, isStale: false)
  }
  func currentIdentityArchive() throws -> Data { identity }
  func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool { stored == current }
}

@MainActor
struct IndexedCatalogInstallation: InstallationIdentityPort {
  func currentOrCreate() -> InstallationIdentityResult { .available("synthetic-installation") }
  func current() -> InstallationIdentityResult { currentOrCreate() }
}

actor IndexedCatalogClock {
  private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
  var pending: Int { waiters.count }
  func sleep(_ duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { waiters[id] = $0 }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }
  func advance() {
    let pending = waiters
    waiters = [:]
    for waiter in pending.values { waiter.resume() }
  }
  private func cancel(_ id: UUID) {
    waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}

struct FailingCatalogProtection: DraftFileProtectionPolicy {
  func applyAndVerify(to fileURL: URL) throws { throw CatalogIndexFailure.unavailable }
  func verify(_ fileURL: URL) throws { throw CatalogIndexFailure.unavailable }
}
