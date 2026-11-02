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
    let lease = try manager.acquireLease()
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
    let lease = try manager.acquireLease()
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

  private func waitForInstall(_ manager: CohereModelManager) async {
    var remaining = 200
    while manager.isInstalling, remaining > 0 {
      try? await Task.sleep(for: .milliseconds(10))
      remaining -= 1
    }
    XCTAssertFalse(manager.isInstalling)
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

  private func descriptor(for data: Data) -> CohereTrustedModel {
    let production = CohereTrustedModel.production
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
