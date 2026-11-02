import CryptoKit
import Foundation
import XCTest

@testable import NarihitosDiary

@MainActor
final class CohereTrustedModelTests: XCTestCase {
  func testProductionDescriptorIsPinnedAndValid() throws {
    let descriptor = CohereTrustedModel.production

    let url = try descriptor.validatedURL()

    XCTAssertEqual(descriptor.byteCount, 1_558_162_944)
    XCTAssertEqual(
      descriptor.sha256,
      "0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb")
    XCTAssertEqual(url.host, "huggingface.co")
    XCTAssertFalse(descriptor.downloadURL.contains("main"))
    XCTAssertFalse(descriptor.installationIdentity.contains("unknown"))
  }

  func testDescriptorRejectsRevocationAndMutableURL() {
    let production = CohereTrustedModel.production
    let revoked = replacing(production, revoked: true)
    let mutableURL = production.downloadURL.replacingOccurrences(
      of: production.repositoryRevision, with: "main")
    let mutable = replacing(production, downloadURL: mutableURL)

    XCTAssertThrowsError(try revoked.validatedURL())
    XCTAssertThrowsError(try mutable.validatedURL())
  }

  func testDescriptorRejectsAPathOutsideApprovedRepository() {
    let production = CohereTrustedModel.production
    let wrongRepositoryURL = production.downloadURL.replacingOccurrences(
      of: "/handy-computer/", with: "/another-publisher/")
    XCTAssertThrowsError(
      try replacing(production, downloadURL: wrongRepositoryURL).validatedURL())
  }

  func testPeakSpaceCalculationIncludesTwoCopiesPreservedInstallAndReserve() throws {
    let model: Int64 = 1_000
    let preserved: Int64 = 1_000

    let required = try CohereModelManager.requiredAvailableBytes(
      modelBytes: model, preservedBytes: preserved)
    XCTAssertEqual(
      required,
      model * 2 + preserved + CohereModelManager.reserveBytes
        + CohereModelManager.metadataAllowanceBytes)
  }

  func testPeakSpaceCalculationRejectsOverflow() {
    XCTAssertThrowsError(
      try CohereModelManager.requiredAvailableBytes(
        modelBytes: .max, preservedBytes: .max))
  }

  private func replacing(
    _ value: CohereTrustedModel, downloadURL: String? = nil, revoked: Bool? = nil
  ) -> CohereTrustedModel {
    CohereTrustedModel(
      schema: value.schema, descriptorRevision: value.descriptorRevision,
      modelID: value.modelID, quantization: value.quantization, repository: value.repository,
      repositoryRevision: value.repositoryRevision, filename: value.filename,
      downloadURL: downloadURL ?? value.downloadURL, byteCount: value.byteCount,
      sha256: value.sha256, allowedRedirectHosts: value.allowedRedirectHosts,
      approvedLanguages: value.approvedLanguages, runtimeIdentity: value.runtimeIdentity,
      conversionIdentity: value.conversionIdentity, chunkingIdentity: value.chunkingIdentity,
      revoked: revoked ?? value.revoked)
  }
}
