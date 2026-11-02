import Combine
import CryptoKit
import Foundation
import XCTest

@testable import NarihitosDiary

private final class StubCohereDownloader: CohereModelDownloading, @unchecked Sendable {
  let data: Data
  let failure: CohereModelFailure?

  init(data: Data, failure: CohereModelFailure? = nil) {
    self.data = data
    self.failure = failure
  }

  func download(
    from _: URL, to destination: URL, expectedBytes _: Int64,
    allowedHosts _: Set<String>, progress: @escaping @Sendable (Int64) -> Void
  ) async throws {
    if let failure { throw failure }
    try data.write(to: destination, options: .withoutOverwriting)
    progress(Int64(data.count))
  }
}

private final class BlockingArtifactVerifier: CohereModelArtifactVerifying, @unchecked Sendable {
  enum Settlement {
    case release
    case cancellation
  }

  private let settlement: Settlement
  private let lock = NSLock()
  private let releaseSemaphore = DispatchSemaphore(value: 0)
  private var started = false
  private var mainThread = false

  init(settlement: Settlement) {
    self.settlement = settlement
  }

  func verify(_: URL, descriptor _: CohereTrustedModel) throws {
    lock.withLock {
      started = true
      mainThread = Thread.isMainThread
    }
    switch settlement {
    case .release:
      _ = releaseSemaphore.wait(timeout: .now() + 2)
    case .cancellation:
      while !Task<Never, Never>.isCancelled {
        Thread.sleep(forTimeInterval: 0.005)
      }
      try Task.checkCancellation()
    }
  }

  var hasStarted: Bool { lock.withLock { started } }
  var ranOnMainThread: Bool { lock.withLock { mainThread } }

  func release() { releaseSemaphore.signal() }
}

@MainActor
final class CohereModelManagerTests: XCTestCase {
  func testVerifiedInstallBecomesReadyAndCanBeLeased() async throws {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })

    manager.install()
    await waitForInstall(manager)

    XCTAssertEqual(manager.readiness, .ready(descriptor.installationIdentity))
    let lease = try await manager.acquireLease()
    XCTAssertEqual(lease.identity, descriptor.installationIdentity)
    XCTAssertEqual(
      try lease.url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
      true)
    manager.release(lease)
    let refreshed = await manager.refresh()
    XCTAssertEqual(refreshed, .ready(descriptor.installationIdentity))
  }

  func testInsufficientSpaceFailsBeforeDownloaderPublication() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in 1 }, protectedDataAvailable: { true })

    manager.install()
    await waitForInstall(manager)

    XCTAssertEqual(manager.readiness, .failed(.insufficientSpace))
  }

  func testDigestMismatchNeverBecomesReady() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    var descriptor = descriptor(for: artifact)
    descriptor = replacing(descriptor, sha256: String(repeating: "0", count: 64))
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })

    manager.install()
    await waitForInstall(manager)

    XCTAssertEqual(manager.readiness, .failed(.invalidDigest))
    let refreshed = await manager.refresh()
    XCTAssertEqual(refreshed, .notInstalled)
  }

  func testSameSizeAndModificationTimeTamperingIsNotReady() async throws {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })

    manager.install()
    await waitForInstall(manager)
    let lease = try await manager.acquireLease()
    manager.release(lease)
    let attributes = try FileManager.default.attributesOfItem(atPath: lease.url.path)
    let originalDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
    var tampered = artifact
    tampered[tampered.count - 1] ^= 1
    try tampered.write(to: lease.url)
    try FileManager.default.setAttributes(
      [.modificationDate: originalDate], ofItemAtPath: lease.url.path)

    let refreshed = await manager.refresh()
    XCTAssertFalse(refreshed == .ready(descriptor.installationIdentity))
  }

  func testLinkedInstallationRecordIsNeverReadAsReady() async throws {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    manager.install()
    await waitForInstall(manager)
    XCTAssertEqual(manager.readiness, .ready(descriptor.installationIdentity))

    let record = root.appending(path: "active-installation-v1.json")
    let target = root.appending(path: "record-target.json")
    try FileManager.default.moveItem(at: record, to: target)
    try FileManager.default.createSymbolicLink(at: record, withDestinationURL: target)

    let refreshed = await manager.refresh()
    XCTAssertFalse(refreshed == .ready(descriptor.installationIdentity))
  }

  func testPublishedVerificationRunsOffMainActorAndKeepsMainSchedulable() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let installer = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    installer.install()
    await waitForInstall(installer)
    XCTAssertEqual(installer.readiness, .ready(descriptor.installationIdentity))

    let verifier = BlockingArtifactVerifier(settlement: .release)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact), artifactVerifier: verifier,
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    let refresh = Task { await manager.refresh() }

    await waitForVerifier(verifier)
    XCTAssertTrue(verifier.hasStarted)
    XCTAssertFalse(verifier.ranOnMainThread)
    verifier.release()
    let readiness = await refresh.value
    XCTAssertEqual(readiness, .ready(descriptor.installationIdentity))
  }

  func testCancellationDuringPublishedVerificationSettlesAsCancelled() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let installer = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    installer.install()
    await waitForInstall(installer)
    XCTAssertEqual(installer.readiness, .ready(descriptor.installationIdentity))

    let verifier = BlockingArtifactVerifier(settlement: .cancellation)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact), artifactVerifier: verifier,
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    let refresh = Task { await manager.refresh() }

    await waitForVerifier(verifier)
    refresh.cancel()
    let readiness = await refresh.value
    XCTAssertEqual(readiness, .failed(.cancelled))
    XCTAssertFalse(verifier.ranOnMainThread)
  }

  func testLatePublishedVerificationCannotOverwriteNewerReadiness() async throws {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let installer = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    installer.install()
    await waitForInstall(installer)
    XCTAssertEqual(installer.readiness, .ready(descriptor.installationIdentity))

    let verifier = BlockingArtifactVerifier(settlement: .release)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact), artifactVerifier: verifier,
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    let oldRefresh = Task { await manager.refresh() }
    await waitForVerifier(verifier)
    try FileManager.default.removeItem(
      at: root.appending(path: "active-installation-v1.json"))

    let newerReadiness = await manager.refresh()
    XCTAssertEqual(newerReadiness, .notInstalled)
    verifier.release()
    let oldOutcome = await oldRefresh.value
    XCTAssertEqual(oldOutcome, .notInstalled)
    XCTAssertEqual(manager.readiness, .notInstalled)
  }

  func testRepeatedMissingQ5RefreshKeepsStableNotInstalledState() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact, base: .productionQ5)
    let manager = CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: StubCohereDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
    var published: [CohereModelReadiness] = []
    let observation = manager.$readiness.dropFirst().sink { published.append($0) }
    defer { observation.cancel() }

    let initial = await manager.refresh()
    XCTAssertEqual(initial, .notInstalled)
    XCTAssertEqual(published, [.notInstalled])

    published.removeAll()
    let repeated = await manager.refresh()
    XCTAssertEqual(repeated, .notInstalled)
    XCTAssertTrue(published.isEmpty)
  }

  private func waitForInstall(_ manager: CohereModelManager) async {
    var remaining = 200
    while manager.isInstalling, remaining > 0 {
      try? await Task.sleep(for: .milliseconds(10))
      remaining -= 1
    }
    XCTAssertFalse(manager.isInstalling)
  }

  private func waitForVerifier(_ verifier: BlockingArtifactVerifier) async {
    var remaining = 200
    while !verifier.hasStarted, remaining > 0 {
      try? await Task.sleep(for: .milliseconds(10))
      remaining -= 1
    }
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "cohere-model-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func modelArtifact() -> Data {
    Data([0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04])
  }

  private func descriptor(
    for data: Data, base production: CohereTrustedModel = .production
  ) -> CohereTrustedModel {
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return CohereTrustedModel(
      schema: production.schema, descriptorRevision: "test-descriptor-v1",
      modelID: production.modelID, quantization: production.quantization,
      repository: production.repository, repositoryRevision: production.repositoryRevision,
      filename: production.filename, downloadURL: production.downloadURL,
      byteCount: Int64(data.count), sha256: digest,
      allowedRedirectHosts: production.allowedRedirectHosts,
      approvedLanguages: production.approvedLanguages,
      runtimeIdentity: production.runtimeIdentity,
      conversionIdentity: production.conversionIdentity,
      chunkingIdentity: production.chunkingIdentity, revoked: false)
  }

  private func replacing(
    _ value: CohereTrustedModel, sha256: String
  ) -> CohereTrustedModel {
    CohereTrustedModel(
      schema: value.schema, descriptorRevision: value.descriptorRevision,
      modelID: value.modelID, quantization: value.quantization, repository: value.repository,
      repositoryRevision: value.repositoryRevision, filename: value.filename,
      downloadURL: value.downloadURL, byteCount: value.byteCount, sha256: sha256,
      allowedRedirectHosts: value.allowedRedirectHosts,
      approvedLanguages: value.approvedLanguages, runtimeIdentity: value.runtimeIdentity,
      conversionIdentity: value.conversionIdentity, chunkingIdentity: value.chunkingIdentity,
      revoked: value.revoked)
  }
}
