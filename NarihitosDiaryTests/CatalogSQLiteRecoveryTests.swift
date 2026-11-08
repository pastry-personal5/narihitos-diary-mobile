import Foundation
import Testing

@testable import NarihitosDiary

struct CatalogSQLiteRecoveryTests {
  @Test func interruptedSpilledTransactionReopensFromProtectedRollbackJournal() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(path: UUID().uuidString)
    let recoveredRoot = manager.temporaryDirectory.appending(path: UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try manager.createDirectory(at: recoveredRoot, withIntermediateDirectories: true)
    defer {
      try? manager.removeItem(at: root)
      try? manager.removeItem(at: recoveredRoot)
    }
    let scope = CatalogIndexScope(key: String(repeating: "c", count: 64), validatorRevision: 1)
    let index = SQLiteCatalogIndex(root: root, protection: DiaryFixtureProtection())
    for number in 0..<100 {
      let candidate = CatalogCandidate(
        components: ["notes", "\(number).note"], handler: "test.metadata",
        date: Date(timeIntervalSinceReferenceDate: Double(number)), stableID: "", safe: true)
      let stamp = try await index.bind(candidate, scope: scope)
      let read = CatalogReadValue(
        version: "strict", assetID: nil, createdAt: candidate.date, title: "Committed",
        favorite: false, payload: nil, issue: nil, hasText: true, hasAudio: false)
      #expect(try await index.apply(read, to: stamp, scope: scope))
    }
    await index.close()
    let writer = try CatalogSQLiteDatabase(url: root.appending(path: "catalog.sqlite"))
    try writer.execute("PRAGMA journal_mode=PERSIST")
    try writer.execute("PRAGMA cache_size=1")
    try writer.execute("PRAGMA cache_spill=ON")
    try writer.execute("BEGIN IMMEDIATE")
    try writer.execute(
      "UPDATE resources SET title=?", values: [.text(String(repeating: "Uncommitted", count: 300))])
    // Copy a stable database+journal image while the writer is paused after page spill.
    // Opening that image exercises hot-journal recovery without killing a user's app.
    let journal = root.appending(path: "catalog.sqlite-journal")
    #expect(try Data(contentsOf: journal).count > 512)
    for name in ["catalog.sqlite", "catalog.sqlite-journal"] {
      try manager.copyItem(at: root.appending(path: name), to: recoveredRoot.appending(path: name))
    }
    try writer.execute("ROLLBACK")
    let recovered = SQLiteCatalogIndex(root: recoveredRoot, protection: DiaryFixtureProtection())
    let page = try await recovered.page(scope: scope, after: nil)
    #expect(page.rows.count == 10)
    #expect(page.rows.allSatisfy { $0.title == "Committed" })
    await recovered.close()
  }
}
