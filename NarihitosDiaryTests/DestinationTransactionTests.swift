import Foundation
import Testing

// Transaction and capture-snapshot cases share one adapter fake.
// swiftlint:disable file_length type_body_length

@testable import NarihitosDiary

@MainActor
struct DestinationTransactionTests {
  @Test func prepareAndCommitBalanceScopesAndPersistDisclosure() async {
    let store = FakeDestinationStore()
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url) else {
      Issue.record("Expected a prepared destination")
      return
    }
    #expect(prepared.needsDisclosure)
    guard case .committed(let summary) = service.commitPreparedSelection(prepared.id) else {
      Issue.record("Expected the prepared destination to commit")
      return
    }

    #expect(summary.displayName == "Diary")
    #expect(store.destination?.id == summary.id.rawValue)
    #expect(store.destination?.disclosureAcknowledged == true)
    #expect(platform.startCount == 2)
    #expect(platform.stopCount == 2)
    #expect(await service.activeDestination().accessState == .accessible)
    #expect(platform.startCount == 3)
    #expect(platform.stopCount == 3)
  }

  @Test func rejectedCandidateAndFailedCommitRetainPreviousDestination() {
    let previous = storedDestination(displayName: "Previous")
    let store = FakeDestinationStore(destination: previous)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    platform.inspection = DestinationCandidateInspection(
      facts: DestinationCandidateFacts(
        isDirectory: true,
        isSymbolicLink: false,
        isUbiquitousItem: false,
        hasICloudIdentity: true),
      displayName: "Rejected")
    #expect(service.prepareSelection(of: platform.url) == .rejected)
    #expect(store.destination == previous)

    platform.inspection = .valid
    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url) else {
      Issue.record("Expected a prepared destination")
      return
    }
    store.shouldFailSave = true
    #expect(service.commitPreparedSelection(prepared.id) == .failed)
    #expect(store.destination == previous)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func newerSelectionAndInvalidationSupersedePreparedWork() {
    let store = FakeDestinationStore()
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    guard case .prepared(let first) = service.prepareSelection(of: platform.url),
      case .prepared(let second) = service.prepareSelection(of: platform.url)
    else {
      Issue.record("Expected prepared destinations")
      return
    }
    #expect(service.commitPreparedSelection(first.id) == .superseded)
    service.invalidateAccess()
    #expect(service.commitPreparedSelection(second.id) == .superseded)
    #expect(store.destination == nil)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func identityChangeSupersedesCommitAndRequiresRestoreOnResolution() async {
    let previous = storedDestination()
    let store = FakeDestinationStore(destination: previous)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url) else {
      Issue.record("Expected a prepared destination")
      return
    }
    platform.identitiesAreEqual = false
    #expect(service.commitPreparedSelection(prepared.id) == .superseded)
    #expect(store.destination == previous)
    #expect(await service.activeDestination().accessState == .restoreAccessRequired)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func identityChangeDuringPreparationCannotBeCommitted() {
    let previous = storedDestination()
    let store = FakeDestinationStore(destination: previous)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)
    platform.onInspect = { platform.identity = Data([0x31]) }

    #expect(service.prepareSelection(of: platform.url) == .temporarilyUnavailable)
    #expect(store.destination == previous)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func staleBookmarkRefreshesOnlyAfterFullRevalidation() async {
    let original = storedDestination(bookmark: Data([0x10]))
    let store = FakeDestinationStore(destination: original)
    let platform = FakeDestinationPlatform()
    platform.resolvedBookmark = ResolvedDestinationBookmark(
      url: platform.url, isStale: true)
    platform.bookmark = Data([0x20])
    let service = AppleDestinationService(repository: store, platform: platform)

    let active = await service.activeDestination()

    #expect(active.accessState == .accessible)
    #expect(active.summary?.id.rawValue == original.id)
    #expect(store.destination?.bookmark == Data([0x20]))
    #expect(store.destination?.id == original.id)
    #expect(platform.inspectCount == 1)
    #expect(platform.startCount == 1)
    #expect(platform.stopCount == 1)
  }

  @Test func failedStaleRefreshKeepsOldRecordAndReportsTemporaryState() async {
    let original = storedDestination(bookmark: Data([0x10]))
    let store = FakeDestinationStore(destination: original)
    store.shouldFailSave = true
    let platform = FakeDestinationPlatform()
    platform.resolvedBookmark = ResolvedDestinationBookmark(
      url: platform.url, isStale: true)
    platform.bookmark = Data([0x20])
    let service = AppleDestinationService(repository: store, platform: platform)

    let active = await service.activeDestination()

    #expect(active.accessState == .temporarilyUnavailable)
    #expect(store.destination == original)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func staleRefreshDoesNotPersistAcrossIdentityChange() async {
    let original = storedDestination()
    let store = FakeDestinationStore(destination: original)
    let platform = FakeDestinationPlatform()
    platform.resolvedBookmark = ResolvedDestinationBookmark(url: platform.url, isStale: true)
    platform.onMakeBookmark = { platform.identity = Data([0x31]) }
    let service = AppleDestinationService(repository: store, platform: platform)

    #expect(await service.activeDestination().accessState == .restoreAccessRequired)
    #expect(store.destination == original)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func scopeAndProviderFailuresMapToRecoverableTypedStates() async {
    let store = FakeDestinationStore(destination: storedDestination())
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    platform.startSucceeds = false
    #expect(await service.activeDestination().accessState == .restoreAccessRequired)
    #expect(service.prepareSelection(of: platform.url) == .temporarilyUnavailable)
    #expect(platform.stopCount == 0)

    platform.startSucceeds = true
    platform.inspectError = DestinationValidationError.providerUnavailable
    #expect(await service.activeDestination().accessState == .temporarilyUnavailable)
    #expect(service.prepareSelection(of: platform.url) == .temporarilyUnavailable)
    #expect(platform.startCount == platform.stopCount + 2)
  }

  @Test func invalidStoredBoundsFailBeforeBookmarkResolution() async {
    let oversized = storedDestination(
      bookmark: Data(repeating: 0x01, count: AppleDestinationService.maximumBookmarkSize + 1))
    let store = FakeDestinationStore(destination: oversized)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    let active = await service.activeDestination()

    #expect(active.summary == nil)
    #expect(active.accessState == .invalidStoredReference)
    #expect(platform.resolveCount == 0)
    #expect(platform.startCount == 0)
  }

  @Test func sameDisplayNameReplacementGetsNewOpaqueIdentity() {
    let previous = storedDestination(displayName: "Diary")
    let store = FakeDestinationStore(destination: previous)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url),
      case .committed(let replacement) = service.commitPreparedSelection(prepared.id)
    else {
      Issue.record("Expected replacement to commit")
      return
    }

    #expect(replacement.displayName == "Diary")
    #expect(replacement.id.rawValue != previous.id)
    #expect(store.destination?.id == replacement.id.rawValue)
  }

  @Test func laterSelectionSkipsOneTimeDisclosure() {
    let store = FakeDestinationStore(destination: storedDestination())
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url) else {
      Issue.record("Expected a prepared destination")
      return
    }

    #expect(!prepared.needsDisclosure)
  }

  @Test func unavailableIdentityAndUnreadableProviderRetainAcceptedFolder() {
    let previous = storedDestination()
    let store = FakeDestinationStore(destination: previous)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    platform.identityError = DestinationValidationError.identityUnavailable
    #expect(service.prepareSelection(of: platform.url) == .temporarilyUnavailable)
    platform.identityError = nil
    platform.inspectError = DestinationValidationError.providerUnavailable
    #expect(service.prepareSelection(of: platform.url) == .temporarilyUnavailable)
    #expect(store.destination == previous)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func canceledSelectionAndBookmarkFailureCannotReplaceAcceptedFolder() {
    let previous = storedDestination()
    let store = FakeDestinationStore(destination: previous)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url) else {
      Issue.record("Expected a prepared destination")
      return
    }
    service.cancelPreparedSelection(prepared.id)
    #expect(service.commitPreparedSelection(prepared.id) == .superseded)

    platform.bookmarkError = CocoaError(.fileReadCorruptFile)
    #expect(service.prepareSelection(of: platform.url) == .temporarilyUnavailable)
    #expect(store.destination == previous)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func oversizedPreparedArtifactsFailClosedAndBalanceScope() {
    let store = FakeDestinationStore()
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    platform.bookmark = Data(
      repeating: 0x01, count: AppleDestinationService.maximumBookmarkSize + 1)
    #expect(service.prepareSelection(of: platform.url) == .rejected)

    platform.bookmark = Data([0x10])
    platform.identity = Data(
      repeating: 0x02, count: AppleDestinationService.maximumIdentityArchiveSize + 1)
    #expect(service.prepareSelection(of: platform.url) == .rejected)
    #expect(store.destination == nil)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func lifecycleInvalidationFencesInFlightResolutionAndCommit() async {
    let store = FakeDestinationStore(destination: storedDestination())
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)
    platform.onInspect = { [weak service] in service?.invalidateAccess() }

    #expect(await service.activeDestination().accessState == .temporarilyUnavailable)

    platform.onInspect = nil
    guard case .prepared(let prepared) = service.prepareSelection(of: platform.url) else {
      Issue.record("Expected a prepared destination")
      return
    }
    platform.onInspect = { [weak service] in service?.invalidateAccess() }
    #expect(service.commitPreparedSelection(prepared.id) == .superseded)
    #expect(platform.startCount == platform.stopCount)
  }

  @Test func captureSnapshotSurvivesActiveFolderChangeAndVerifiedOffline() async throws {
    let original = storedDestination()
    let store = FakeDestinationStore(destination: original)
    let platform = FakeDestinationPlatform()
    let service = AppleDestinationService(repository: store, platform: platform)

    let (captured, state) = try await service.captureSnapshotRecord()
    #expect(state == .accessible)
    #expect(captured == original)
    store.destination = storedDestination(bookmark: Data([0x20]))
    #expect(captured.bookmark == original.bookmark)

    store.destination = original
    platform.inspectError = DestinationValidationError.providerUnavailable
    let (_, offlineState) = try await service.captureSnapshotRecord()
    #expect(offlineState == .verifiedOffline)
    platform.identitiesAreEqual = false
    await #expect(throws: CaptureGateFailure.destination) {
      try await service.captureSnapshotRecord()
    }
    platform.identitiesAreEqual = true
    platform.startSucceeds = false
    await #expect(throws: CaptureGateFailure.destination) {
      try await service.captureSnapshotRecord()
    }
  }

  @Test func captureSnapshotUsesRefreshedBookmarkAfterStaleResolution() async throws {
    let original = storedDestination()
    let store = FakeDestinationStore(destination: original)
    let platform = FakeDestinationPlatform()
    platform.resolvedBookmark = ResolvedDestinationBookmark(url: platform.url, isStale: true)
    platform.bookmark = Data([0x44])
    let service = AppleDestinationService(repository: store, platform: platform)
    let (captured, state) = try await service.captureSnapshotRecord()
    #expect(state == .accessible)
    #expect(captured.bookmark == Data([0x44]))
    #expect(store.destination?.bookmark == Data([0x44]))
  }

  private func storedDestination(
    displayName: String = "Diary",
    bookmark: Data = Data([0x10])
  ) -> StoredDestinationRecord {
    StoredDestinationRecord(
      id: DestinationID.make().rawValue,
      displayName: displayName,
      bookmark: bookmark,
      identityArchive: Data([0x30]),
      disclosureAcknowledged: true)
  }
}

extension DestinationCandidateInspection {
  fileprivate static let valid = DestinationCandidateInspection(
    facts: DestinationCandidateFacts(
      isDirectory: true,
      isSymbolicLink: false,
      isUbiquitousItem: true,
      hasICloudIdentity: true),
    displayName: "Diary")
}

@MainActor
private final class FakeDestinationStore: DestinationSettingsStore {
  var destination: StoredDestinationRecord?
  var shouldFailSave = false

  init(destination: StoredDestinationRecord? = nil) {
    self.destination = destination
  }

  func loadDestination() -> StoredDestinationRecord? { destination }

  func saveDestination(_ destination: StoredDestinationRecord) throws {
    if shouldFailSave { throw CocoaError(.fileWriteUnknown) }
    self.destination = destination
  }
}

@MainActor
private final class FakeDestinationPlatform: DestinationPlatform {
  let url = URL(fileURLWithPath: "/synthetic/diary")
  var inspection = DestinationCandidateInspection.valid
  var inspectError: Error?
  var bookmark = Data([0x10])
  var resolvedBookmark: ResolvedDestinationBookmark
  var identity = Data([0x30])
  var identitiesAreEqual = true
  var startSucceeds = true
  var startCount = 0
  var stopCount = 0
  var inspectCount = 0
  var resolveCount = 0
  var onInspect: (() -> Void)?
  var onMakeBookmark: (() -> Void)?
  var bookmarkError: Error?
  var identityError: Error?

  init() {
    resolvedBookmark = ResolvedDestinationBookmark(url: url, isStale: false)
  }

  func startAccessing(_ url: URL) -> Bool {
    startCount += 1
    return startSucceeds
  }

  func stopAccessing(_ url: URL) {
    stopCount += 1
  }

  func inspect(_ url: URL) throws -> DestinationCandidateInspection {
    inspectCount += 1
    onInspect?()
    if let inspectError { throw inspectError }
    return inspection
  }

  func makeBookmark(for url: URL) throws -> Data {
    onMakeBookmark?()
    if let bookmarkError { throw bookmarkError }
    return bookmark
  }

  func resolveBookmark(_ data: Data) throws -> ResolvedDestinationBookmark {
    resolveCount += 1
    return resolvedBookmark
  }

  func currentIdentityArchive() throws -> Data {
    if let identityError { throw identityError }
    return identity
  }

  func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool {
    identitiesAreEqual && stored == current
  }
}

// swiftlint:enable file_length type_body_length
