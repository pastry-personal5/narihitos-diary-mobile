import CryptoKit
import Foundation
import Testing

@testable import NarihitosDiary

struct SQLiteCatalogIndexTests {
  private let scope = CatalogIndexScope(
    key: String(repeating: "a", count: 64), validatorRevision: 1)

  @Test func keysetMatchesSwiftPrecisionUnicodeLegacyAndDuplicateClaims() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    var oracle = CatalogCollection()
    let session = CatalogSessionID()
    let identifiers: [String?] = ["Ω", "🧑", "가", "中", "x", nil, "é", "e\u{301}"]
    for number in (0..<40).reversed() {
      let assetID = identifiers[number % identifiers.count].map { $0 + "\(number / 8)" }
      let candidate = candidate(number, assetID: assetID)
      let read = read(candidate, assetID: assetID)
      let stamp = try await index.bind(candidate, scope: scope)
      #expect(try await index.apply(read, to: stamp, scope: scope))
      let hash = SHA256.hash(data: Data(candidate.key.utf8))
        .map { String(format: "%02x", $0) }.joined()
      let summary = CatalogSummary(
        handle: CatalogItemHandle(
          session: session, resource: stamp.rowID.rawValue, version: UUID(), kind: candidate.handler
        ),
        assetID: assetID, resourceOrder: hash, createdAt: try #require(read.createdAt),
        title: try #require(read.title), favorite: read.favorite)
      oracle.merge(
        CatalogPage(
          session: session, summaries: [summary], recovery: [], continuation: nil,
          examinedCandidates: 1, isDiscovering: false))
    }
    var rows: [CatalogRememberedRow] = []
    var cursor: CatalogIndexCursor?
    repeat {
      let page = try await index.page(scope: scope, after: cursor)
      #expect(page.rows.count <= 10)
      rows += page.rows
      cursor = page.continuation
    } while cursor != nil
    #expect(rows.map(\.id.rawValue) == oracle.ordered.map(\.id))
    #expect(rows.map(\.createdAt) == oracle.ordered.map(\.createdAt))
    #expect(rows.count == 30)  // Five canonically equivalent claim pairs are excluded.
    let plan = try await index.queryPlan(scope: scope)
    #expect(plan.contains { $0.contains("INDEX timeline") })
    #expect(!plan.contains { $0.contains("TEMP B-TREE") })
    await index.close()
  }

  @Test func reopenRetainsIdentityButRejectsOldCursorAndResourceStamp() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    var firstStamp: CatalogResourceStamp?
    for number in 0..<11 {
      let candidate = candidate(number)
      let stamp = try await index.bind(candidate, scope: scope)
      firstStamp = firstStamp ?? stamp
      #expect(try await index.apply(read(candidate), to: stamp, scope: scope))
    }
    let first = try await index.page(scope: scope, after: nil)
    #expect(first.rows.count == 10)
    let cursor = try #require(first.continuation)
    #expect(try await index.page(scope: scope, after: cursor).rows.count == 1)
    await index.close()
    let reopened = try await index.page(scope: scope, after: nil)
    #expect(reopened.rows == first.rows)
    await #expect(throws: CatalogIndexFailure.changed) {
      try await index.page(scope: scope, after: cursor)
    }
    let old = try #require(firstStamp)
    #expect(try await !index.apply(read(candidate(0)), to: old, scope: scope))
    await index.close()
  }

  @Test func invalidationRejectsOldReadsAndPreservesRememberedRows() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    let candidate = candidate(0)
    let stale = try await index.bind(candidate, scope: scope)
    try await index.invalidate(scope: scope)
    #expect(try await !index.apply(read(candidate), to: stale, scope: scope))
    #expect(try await index.page(scope: scope, after: nil).rows.isEmpty)
    let current = try await index.bind(candidate, scope: scope)
    #expect(try await index.apply(read(candidate), to: current, scope: scope))
    try await index.invalidate(scope: scope)
    #expect(try await index.page(scope: scope, after: nil).rows.count == 1)
    #expect(try await !index.apply(read(candidate), to: current, scope: scope))
    await index.close()
  }

  @Test func rejectedWriteRollsBackAndRetryableResultCannotSeedMain() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    let candidate = candidate(1)
    let stamp = try await index.bind(candidate, scope: scope)
    let malformed = read(candidate, title: String(repeating: "x", count: 4_097))
    await #expect(throws: CatalogIndexFailure.unsafe) {
      try await index.apply(malformed, to: stamp, scope: scope)
    }
    #expect(try await index.page(scope: scope, after: nil).rows.isEmpty)
    #expect(try await index.apply(read(candidate), to: stamp, scope: scope))
    let next = try await index.bind(candidate, scope: scope)
    let unavailable = CatalogReadValue(
      version: "unavailable", assetID: nil, createdAt: nil, title: nil,
      favorite: nil, payload: nil, issue: .unavailable, hasText: false, hasAudio: false)
    #expect(try await index.apply(unavailable, to: next, scope: scope))
    #expect(try await index.page(scope: scope, after: nil).rows.count == 1)
    let unseen = try await index.bind(self.candidate(2), scope: scope)
    #expect(try await index.apply(unavailable, to: unseen, scope: scope))
    #expect(try await index.page(scope: scope, after: nil).rows.count == 1)
    await index.close()
  }

  @Test func scopeValidatorAndCorruptionRebuildOnlyDisposableArtifacts() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let sentinel = root.appending(path: "unrelated-diary.md")
    try Data("Synthetic preserved diary".utf8).write(to: sentinel)
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    let candidate = candidate(1)
    let stamp = try await index.bind(candidate, scope: scope)
    #expect(try await index.apply(read(candidate), to: stamp, scope: scope))
    await index.close()
    let otherScope = CatalogIndexScope(key: String(repeating: "b", count: 64), validatorRevision: 1)
    #expect(try await index.page(scope: otherScope, after: nil).rows.isEmpty)
    await index.close()
    try Data("Broken SQLite".utf8).write(to: root.appending(path: "catalog.sqlite"))
    #expect(try await index.page(scope: scope, after: nil).rows.isEmpty)
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "Synthetic preserved diary")
    await index.close()
    try await index.discard()
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
  }

  @Test func missingScopeMetadataCannotRelabelAnotherAccountsRows() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    let candidate = candidate(1)
    let stamp = try await index.bind(candidate, scope: scope)
    #expect(try await index.apply(read(candidate), to: stamp, scope: scope))
    await index.close()
    do {
      let damaged = try CatalogSQLiteDatabase(url: root.appending(path: "catalog.sqlite"))
      try damaged.execute("DELETE FROM metadata")
    }
    let other = CatalogIndexScope(key: String(repeating: "d", count: 64), validatorRevision: 1)
    #expect(try await index.page(scope: other, after: nil).rows.isEmpty)
    await index.close()
  }

  @Test func protectionAndUnsafeProjectionPathsFailWithoutWritingDiaries() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let locked = SQLiteCatalogIndex(
      root: root, protection: DiaryFixtureProtection(), protectedDataAvailable: { false })
    await #expect(throws: CatalogIndexFailure.unavailable) {
      try await locked.page(scope: scope, after: nil)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    let sentinel = root.appending(path: "diary.md")
    try Data("Preserved".utf8).write(to: sentinel)
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "catalog.sqlite"), withDestinationURL: sentinel)
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    await #expect(throws: CatalogIndexFailure.self) {
      try await index.page(scope: scope, after: nil)
    }
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "Preserved")
    await index.close()
  }

  @Test func busyWriterIsBoundedAndDoesNotDiscardPriorRows() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    let firstCandidate = candidate(1)
    let stamp = try await index.bind(firstCandidate, scope: scope)
    #expect(try await index.apply(read(firstCandidate), to: stamp, scope: scope))
    let competing = try CatalogSQLiteDatabase(url: root.appending(path: "catalog.sqlite"))
    try competing.execute("BEGIN IMMEDIATE")
    let clock = ContinuousClock()
    let start = clock.now
    await #expect(throws: CatalogIndexFailure.busy) {
      try await index.bind(candidate(2), scope: scope)
    }
    #expect(start.duration(to: clock.now) < .seconds(1))
    try competing.execute("ROLLBACK")
    #expect(try await index.page(scope: scope, after: nil).rows.count == 1)
    _ = try await index.bind(candidate(2), scope: scope)
    await index.close()
  }

  @Test func fullProjectionRollsBackAndRetainsPreviouslyCommittedSummaries() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(
      root: root, protection: DiaryFixtureProtection(), maximumDatabaseBytes: 65_536)
    let first = candidate(0)
    let stamp = try await index.bind(first, scope: scope)
    #expect(try await index.apply(read(first), to: stamp, scope: scope))
    var full = false
    for number in 1..<100 {
      do {
        let candidate = candidate(number)
        let stamp = try await index.bind(candidate, scope: scope)
        _ = try await index.apply(
          read(candidate, title: String(repeating: "x", count: 4_000)), to: stamp, scope: scope)
      } catch CatalogIndexFailure.capacity {
        full = true
        break
      }
    }
    #expect(full)
    let page = try await index.page(scope: scope, after: nil)
    #expect(page.rows.contains { $0.id == stamp.rowID && $0.title == "Synthetic" })
    await index.close()
  }

  @Test func rejectedMetadataBatchRollsBackClaimsAndSnapshotRevision() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    let candidates = (0..<11).map { candidate($0) }
    let stamps = try await index.bindCandidates(candidates, scope: scope)
    for (candidate, stamp) in zip(candidates, stamps) {
      #expect(try await index.apply(read(candidate), to: stamp, scope: scope))
    }
    let page = try await index.page(scope: scope, after: nil)
    let cursor = try #require(page.continuation)
    let unsafe = CatalogCandidate(
      components: ["..", "outside"], handler: "test.metadata", date: nil, stableID: "", safe: true)
    await #expect(throws: CatalogIndexFailure.unsafe) {
      try await index.bindCandidates([candidate(20), unsafe], scope: scope)
    }
    #expect(try await index.page(scope: scope, after: cursor).rows.count == 1)
    await #expect(throws: CatalogIndexFailure.unsafe) {
      try await index.bindCandidates(Array(repeating: candidate(20), count: 51), scope: scope)
    }
    await index.close()
  }

}

extension SQLiteCatalogIndexTests {
  fileprivate func fixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  fileprivate func candidate(_ number: Int, assetID: String? = nil) -> CatalogCandidate {
    CatalogCandidate(
      components: ["notes", "\(number).note"], handler: "test.metadata",
      date: Date(
        timeIntervalSinceReferenceDate: 1_000.125 + Double(number / 8)
          + Double(number % 3) / 10_000_000),
      stableID: assetID ?? "", safe: true)
  }

  fileprivate func read(
    _ candidate: CatalogCandidate, assetID: String? = nil, title: String = "Synthetic"
  ) -> CatalogReadValue {
    CatalogReadValue(
      version: "strict-content-proof", assetID: assetID, createdAt: candidate.date,
      title: title, favorite: true, payload: nil, issue: nil, hasText: true, hasAudio: true)
  }
}
