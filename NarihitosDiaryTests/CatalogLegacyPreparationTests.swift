import Foundation
import Testing

@testable import NarihitosDiary

struct CatalogLegacyPreparationTests {
  private let scope = CatalogIndexScope(
    key: String(repeating: "f", count: 64), validatorRevision: 1)

  @Test func largeSiblingDirectoryYieldsBeforeDecodeAndFreshActionChecksItsProof() async throws {
    let fixture = try DiaryCatalogHandlerTests().makeLegacy()
    let root = fixture.root
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let assets = fixture.audio.deletingLastPathComponent()
    for number in 0..<213 {
      try Data("Unrelated".utf8).write(to: assets.appending(path: "\(number).txt"))
    }
    let metrics = CatalogPerformanceProbe()
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler(metrics: metrics))
    let index = SQLiteCatalogIndex(
      root: root.appending(path: "cache"), protection: DiaryFixtureProtection())
    let worker = CatalogReconciliationWorker(
      index: index, scope: scope, registry: registry, session: CatalogSessionID())
    try await worker.begin()
    var emptyPreparationSlices = 0
    for _ in 0..<100 {
      let progress = try await worker.step(root: root, demand: 10)
      #expect(progress.candidateVisits <= 50)
      #expect(progress.enumerationVisits <= 50)
      if progress.enumerationVisits == 50, metrics.snapshot["audioHashBytes"] == nil {
        emptyPreparationSlices += 1
      }
      if progress.exhausted { break }
    }
    #expect(emptyPreparationSlices >= 4)
    #expect(metrics.snapshot["validationAttempts"] == 1)
    let summary = try #require(await worker.summaries().first)
    let detail = try await worker.detail(summary.handle, root: root)
    #expect((detail.payload as? DiaryCatalogDetail)?.isLegacy == true)
    let resource = try await worker.actionResource(summary.handle, root: root)
    #expect(resource.preparation is CatalogLegacySiblingProof)
    typealias Inspection = @Sendable (URL, CatalogReadControl) throws -> CommittedDiaryFacts
    let inspect: Inspection = { root, control in
      try CommittedDiaryResource.inspect(resource, root: root, control: control)
    }
    let facts = try await CommittedDiaryResource.coordinated(
      resource, root: root, operation: inspect)
    #expect(facts.snippet == nil)
    try Data("New sibling".utf8).write(to: assets.appending(path: "new.m4a"))
    await #expect(throws: CatalogIssue.changed) {
      try await CommittedDiaryResource.coordinated(resource, root: root, operation: inspect)
    }
    await index.close()
  }

  @Test func changedContinuationIsRejectedAndAmbiguityRetainsReadableText() async throws {
    let fixture = try DiaryCatalogHandlerTests().makeLegacy()
    let root = fixture.root
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let assets = fixture.audio.deletingLastPathComponent()
    for number in 0..<100 {
      try Data("Unrelated".utf8).write(to: assets.appending(path: "\(number).txt"))
    }
    let handler = DiaryCatalogHandler()
    let first = try await handler.prepareRead(
      fixture.candidate, root: root, continuation: nil)
    guard case .progress(let token, let visits) = first else {
      Issue.record("Expected bounded sibling discovery")
      return
    }
    #expect(visits <= 50)
    try Data(contentsOf: fixture.audio).write(to: assets.appending(path: "second.m4a"))
    await #expect(throws: CatalogIssue.changed) {
      try await handler.prepareRead(fixture.candidate, root: root, continuation: token)
    }
    var continuation: (any CatalogReadPreparation)?
    var proof: (any CatalogReadPreparation)?
    for _ in 0..<10 {
      let next = try await handler.prepareRead(
        fixture.candidate, root: root, continuation: continuation)
      switch next {
      case .progress(let token, _): continuation = token
      case .ready(let token, _): proof = token
      }
      if proof != nil { break }
    }
    let read = try await handler.readPrepared(
      fixture.candidate, root: root, preparation: proof)
    #expect(read.issue == .ambiguousAudio)
    #expect((read.payload as? DiaryCatalogDetail)?.body.contains("synthetic") == true)
  }
}
