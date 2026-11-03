import Foundation
import Testing

@testable import NarihitosDiary

private struct PurgeTestProtection: DraftFileProtectionPolicy {
  func applyAndVerify(to _: URL) throws {}
  func verify(_: URL) throws {}
}

@MainActor
final class SyntheticPurgePort: PurgePort {
  var pending: PurgeTransaction?
  var destinationID = DestinationID.make().rawValue
  var failure = false
  var unavailable = false
  var performed: [PurgeScope] = []
  var prepared = 0
  var hold: CheckedContinuation<Void, Never>?
  var suspendPerform = false

  func pendingTransaction() throws -> PurgeTransaction? {
    if unavailable { throw PurgeFailure.unavailable }
    return pending
  }
  func prepare(_ scope: PurgeScope) async throws -> PurgeTransaction {
    prepared += 1
    if unavailable { throw PurgeFailure.unavailable }
    return PurgeTransaction(
      scope: scope, destinationID: scope == .activeFolder ? destinationID : nil)
  }
  func begin(_ transaction: PurgeTransaction) throws { pending = transaction }
  func perform(
    _ transaction: PurgeTransaction, progress: @escaping @Sendable (Int) -> Void
  ) async throws {
    performed.append(transaction.scope)
    if suspendPerform { await withCheckedContinuation { hold = $0 } }
    if failure { throw PurgeFailure.unavailable }
    progress(3)
  }
  func finish() throws { pending = nil }
}

@MainActor
struct PurgeTests {
  @Test func confirmationsCancelAndStaleActivationNeverDelete() async throws {
    let port = SyntheticPurgePort()
    let model = DangerZoneModel()
    model.configure(port)
    model.acquireMaintenance = { true }
    #expect(port.performed.isEmpty)
    await model.request(.activeFolder)
    let stale = try #require(model.confirmation?.id)
    model.disarm()
    await model.confirm(stale)
    await model.request(.internalStaging)
    #expect(model.confirmation?.transaction.scope == .internalStaging)
    await model.confirm(stale)
    #expect(port.performed.isEmpty)
    model.disarm()
    #expect(port.pending == nil)
  }

  @Test func duplicateConfirmationCannotStartConcurrentPurge() async throws {
    let port = SyntheticPurgePort()
    port.suspendPerform = true
    let model = DangerZoneModel()
    model.configure(port)
    model.acquireMaintenance = { true }
    await model.request(.internalStaging)
    let id = try #require(model.confirmation?.id)
    let task = Task { await model.confirm(id) }
    await waitUntil { port.hold != nil }
    #expect(model.blocksWork)
    await model.confirm(id)
    #expect(port.performed == [.internalStaging])
    port.hold?.resume()
    await task.value
    #expect(!model.blocksWork)
    #expect(model.message == "Purge complete.")
  }

  @Test func busyAndChangedDestinationFailBeforeDurableIntent() async throws {
    let port = SyntheticPurgePort()
    let model = DangerZoneModel()
    model.configure(port)
    await model.request(.activeFolder)
    await model.confirm(try #require(model.confirmation?.id))
    #expect(port.pending == nil)
    #expect(port.performed.isEmpty)
    model.acquireMaintenance = { true }
    await model.request(.activeFolder)
    let id = try #require(model.confirmation?.id)
    port.destinationID = DestinationID.make().rawValue
    await model.confirm(id)
    #expect(port.pending == nil)
    #expect(port.performed.isEmpty)
    #expect(!model.blocksWork)
  }

  @Test func partialFailureRetainsBarrierAndReopenNeedsExplicitSameScopeRetry() async throws {
    let port = SyntheticPurgePort()
    port.failure = true
    let first = DangerZoneModel()
    first.configure(port)
    first.acquireMaintenance = { true }
    var releases = 0
    first.releaseMaintenance = { releases += 1 }
    await first.request(.internalStaging)
    await first.confirm(try #require(first.confirmation?.id))
    #expect(first.blocksWork)
    #expect(releases == 0)
    let reopened = DangerZoneModel()
    reopened.configure(port)
    reopened.acquireMaintenance = { true }
    #expect(reopened.blocksWork)
    #expect(port.performed.count == 1)
    await reopened.request(.activeFolder)
    #expect(reopened.confirmation == nil)
    port.failure = false
    await reopened.request(.internalStaging)
    await reopened.confirm(try #require(reopened.confirmation?.id))
    #expect(!reopened.blocksWork)
    #expect(port.pending == nil)
    #expect(port.performed == [.internalStaging, .internalStaging])
  }

  @Test func unavailableJournalBlocksWorkWithoutDeletion() async {
    let port = SyntheticPurgePort()
    port.unavailable = true
    let model = DangerZoneModel()
    model.configure(port)
    #expect(model.blocksWork)
    await model.request(.internalStaging)
    #expect(model.confirmation == nil)
    #expect(port.performed.isEmpty)
  }

  @Test func recursiveDeletionPreservesRootAndOutsideSymlinkTarget() throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    let root = fixture.support.appending(path: "Captures")
    try fixture.write("Captures/deep/inside")
    try fixture.write("Captures/.hidden")
    try fixture.write("keep/survivor")
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "escape"),
      withDestinationURL: fixture.support.appending(path: "keep"))
    let identity = try PurgeFileTree.identity(root)
    #expect(try PurgeFileTree().purge(root) == 4)
    #expect(try PurgeFileTree.identity(root) == identity)
    #expect(try PurgeFileTree.isEmpty(root))
    #expect(
      FileManager.default.fileExists(atPath: fixture.support.appending(path: "keep/survivor").path))
    #expect(try PurgeFileTree().purge(root) == 0)
    #expect(throws: PurgeFailure.self) {
      try PurgeFileTree().purge(root, expectedIdentity: "different")
    }
  }

  @Test func stagingAllowlistAndDurableRecoverySurviveFreshService() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    for root in ApplePurgeService.stagingNames { try fixture.write("\(root)/nested/private") }
    for keep in ["settings/extra.json", "CohereModel/model.gguf", "unrelated/file"] {
      try fixture.write(keep)
    }
    let service = fixture.service()
    let transaction = try await service.prepare(.internalStaging)
    try service.begin(transaction)
    let reopened = fixture.service()
    #expect(try reopened.pendingTransaction() == transaction)
    try await reopened.perform(transaction) { _ in }
    for root in ApplePurgeService.stagingNames {
      #expect(try PurgeFileTree.isEmpty(fixture.support.appending(path: root)))
    }
    #expect(try reopened.pendingTransaction() == transaction)
    try reopened.finish()
    #expect(try fixture.service().pendingTransaction() == nil)
    for keep in ["settings/extra.json", "CohereModel/model.gguf", "unrelated/file"] {
      #expect(FileManager.default.fileExists(atPath: fixture.support.appending(path: keep).path))
    }
  }

  @Test func failedDeletionAndProtectedDataRetainJournal() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("Captures/private")
    let failing = fixture.service(
      tree: PurgeFileTree(beforeRemoval: { throw PurgeFailure.unavailable }))
    let transaction = try await failing.prepare(.internalStaging)
    try failing.begin(transaction)
    await #expect(throws: PurgeFailure.self) { try await failing.perform(transaction) { _ in } }
    #expect(try fixture.service().pendingTransaction() == transaction)
    let locked = fixture.service(available: false)
    #expect(throws: PurgeFailure.self) { try locked.pendingTransaction() }
    let retry = fixture.service()
    try await retry.perform(transaction) { _ in }
    try retry.finish()
    #expect(try retry.pendingTransaction() == nil)
  }

  @Test func folderPurgeRevalidatesIdentityBalancesAccessAndPreservesSettings() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("icloud/year/month/diary.md")
    try fixture.write("icloud/unrelated.txt")
    try fixture.write("elsewhere/keep")
    let service = fixture.service()
    let transaction = try await service.prepare(.activeFolder)
    try service.begin(transaction)
    try await service.perform(transaction) { _ in }
    try service.finish()
    #expect(try PurgeFileTree.isEmpty(fixture.platform.url))
    #expect(
      await fixture.destination.activeDestination().summary?.id.rawValue
        == transaction.destinationID)
    #expect(fixture.platform.starts == fixture.platform.stops)
    #expect(
      FileManager.default.fileExists(atPath: fixture.support.appending(path: "elsewhere/keep").path)
    )
  }

  @Test func folderPurgeBlocksPendingStagingAndAccountChange() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("Captures/receipt.json")
    try fixture.write("icloud/keep")
    let service = fixture.service()
    await #expect(throws: PurgeFailure.self) { try await service.prepare(.activeFolder) }
    #expect(try service.pendingTransaction() == nil)
    let staging = try await service.prepare(.internalStaging)
    try service.begin(staging)
    try await service.perform(staging) { _ in }
    try service.finish()
    let folder = try await service.prepare(.activeFolder)
    try service.begin(folder)
    fixture.platform.matches = false
    await #expect(throws: (any Error).self) { try await service.perform(folder) { _ in } }
    #expect(try service.pendingTransaction() == folder)
    #expect(
      FileManager.default.fileExists(atPath: fixture.platform.url.appending(path: "keep").path))
    #expect(fixture.platform.starts == fixture.platform.stops)
  }

  @Test func movedDirectoryAndLinkedRootAreRefusedWithoutDeletingOutsideData() throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("Captures/nested/keep")
    try fixture.write("outside/survivor")
    let root = fixture.support.appending(path: "Captures")
    let nested = root.appending(path: "nested")
    let escaped = fixture.support.appending(path: "outside/moved")
    let tree = PurgeFileTree(beforeRemoval: {
      try FileManager.default.moveItem(at: nested, to: escaped)
      try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: escaped)
    })
    #expect(throws: PurgeFailure.self) { try tree.purge(root) }
    #expect(FileManager.default.fileExists(atPath: escaped.appending(path: "keep").path))
    #expect(throws: PurgeFailure.self) { try PurgeFileTree().purge(nested) }
    #expect(FileManager.default.fileExists(atPath: escaped.appending(path: "keep").path))
  }

  @Test func corruptJournalIsRetainedAndDepthIsBounded() throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("purge-transaction.json")
    #expect(throws: (any Error).self) { try fixture.service().pendingTransaction() }
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.support.appending(path: "purge-transaction.json").path))
    var path = "Captures"
    for _ in 0..<129 { path += "/d" }
    try fixture.write(path + "/keep")
    #expect(throws: PurgeFailure.self) {
      try PurgeFileTree().purge(fixture.support.appending(path: "Captures"))
    }
    #expect(
      FileManager.default.fileExists(atPath: fixture.support.appending(path: path + "/keep").path))
  }

  private func waitUntil(_ predicate: () -> Bool) async {
    for _ in 0..<100 {
      if predicate() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Synthetic purge did not reach its suspension point")
  }
}

@MainActor
struct PurgeDiskFixture {
  let support: URL
  let destination: AppleDestinationService
  let platform: PurgeDestinationPlatform

  init() throws {
    support = FileManager.default.temporaryDirectory.appending(path: "purge-test-\(UUID())")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    platform = PurgeDestinationPlatform(url: support.appending(path: "icloud"))
    try FileManager.default.createDirectory(at: platform.url, withIntermediateDirectories: true)
    destination = AppleDestinationService(
      repository: PrivateSettingsRepository(root: support.appending(path: "settings")),
      platform: platform)
    guard case .prepared(let value) = destination.prepareSelection(of: platform.url),
      case .committed = destination.commitPreparedSelection(value.id)
    else { throw PurgeFailure.unavailable }
  }

  func service(tree: PurgeFileTree = PurgeFileTree(), available: Bool = true) -> ApplePurgeService {
    ApplePurgeService(
      destination: destination, support: support, protection: PurgeTestProtection(),
      protectedDataAvailable: { available }, tree: tree)
  }

  func write(_ path: String) throws {
    let url = support.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("synthetic".utf8).write(to: url)
  }

  func close() { try? FileManager.default.removeItem(at: support) }
}

@MainActor
final class PurgeDestinationPlatform: DestinationPlatform {
  let url: URL
  var starts = 0
  var stops = 0
  var matches = true
  init(url: URL) { self.url = url }
  func startAccessing(_: URL) -> Bool {
    starts += 1
    return true
  }
  func stopAccessing(_: URL) { stops += 1 }
  func inspect(_: URL) throws -> DestinationCandidateInspection {
    DestinationCandidateInspection(
      facts: DestinationCandidateFacts(
        isDirectory: true, isSymbolicLink: false,
        isUbiquitousItem: true, hasICloudIdentity: true), displayName: "Synthetic Folder")
  }
  func makeBookmark(for _: URL) throws -> Data { Data("synthetic-bookmark".utf8) }
  func resolveBookmark(_: Data) throws -> ResolvedDestinationBookmark {
    ResolvedDestinationBookmark(url: url, isStale: false)
  }
  func currentIdentityArchive() throws -> Data { Data("synthetic-identity".utf8) }
  func identitiesMatch(_: Data, _: Data) throws -> Bool { matches }
}
