import CryptoKit
import Foundation
import XCTest

@testable import NarihitosDiary

private final class HeadroomStubDownloader: CohereModelDownloading, @unchecked Sendable {
  let data: Data

  init(data: Data) {
    self.data = data
  }

  func download(
    from _: URL, to destination: URL, expectedBytes _: Int64,
    allowedHosts _: Set<String>, progress: @escaping @Sendable (Int64) -> Void
  ) async throws {
    try data.write(to: destination, options: .withoutOverwriting)
    progress(Int64(data.count))
  }
}

@MainActor
final class CohereModelHeadroomTests: XCTestCase {
  func testQ5PreflightWaitsInsteadOfLoadingOnUncertifiedProductionPath() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact, base: .productionQ5)
    let manager = modelManager(descriptor: descriptor, artifact: artifact, root: root)
    manager.install()
    await waitForInstall(manager)
    let adapter = adapter(
      models: manager, root: root, selection: .cohereQ5)

    let result = await adapter.preflight(for: .english)

    XCTAssertEqual(result.readiness, .waiting(.cohereQ5MemoryUnsupported))
    XCTAssertTrue(result.effectiveValues.isEmpty)
  }

  func testQ5PreflightAllowsAnExplicitlyCertifiedProductionPath() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact, base: .productionQ5)
    let manager = modelManager(descriptor: descriptor, artifact: artifact, root: root)
    manager.install()
    await waitForInstall(manager)
    let adapter = adapter(
      models: manager, root: root, selection: .cohereQ5, q5RuntimeCertified: { true })

    let result = await adapter.preflight(for: .korean)

    XCTAssertEqual(result.readiness, .ready)
    XCTAssertEqual(result.effectiveValues["installedIdentity"], descriptor.installationIdentity)
  }

  func testQ4PreflightKeepsItsExistingTargetPhonePath() async {
    let root = temporaryDirectory()
    let artifact = modelArtifact()
    let descriptor = descriptor(for: artifact)
    let manager = modelManager(descriptor: descriptor, artifact: artifact, root: root)
    manager.install()
    await waitForInstall(manager)
    let adapter = adapter(
      models: manager, root: root, selection: .cohereQ4)

    let result = await adapter.preflight(for: .english)

    XCTAssertEqual(result.readiness, .ready)
  }

  private func modelManager(
    descriptor: CohereTrustedModel, artifact: Data, root: URL
  ) -> CohereModelManager {
    CohereModelManager(
      descriptor: descriptor, root: root,
      downloader: HeadroomStubDownloader(data: artifact),
      availableCapacity: { _ in Int64.max }, protectedDataAvailable: { true })
  }

  private func adapter(
    models: CohereModelManager, root: URL, selection: TranscriptionModelSelection,
    q5RuntimeCertified: @escaping @Sendable () -> Bool = { false }
  ) -> CohereTranscriptionAdapter {
    CohereTranscriptionAdapter(
      store: MemoryQueueStore(),
      audio: VerifiedCaptureAudioSource(
        files: CapturePrivateFiles(root: root.appending(path: "captures"))),
      models: models, q5Models: models, selectedModel: { selection },
      q5RuntimeCertified: q5RuntimeCertified)
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
      path: "cohere-headroom-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
}
