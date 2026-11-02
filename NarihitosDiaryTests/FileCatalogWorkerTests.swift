import Darwin
import Foundation
import Testing

@testable import NarihitosDiary

private struct SyntheticCatalogPayload: CatalogDetailPayload { let text: String }
private struct SyntheticCatalogHandler: CatalogAssetHandler {
  let kind = "test.synthetic"
  func descends(into components: [String]) -> Bool { components == ["notes"] }
  func candidate(components: [String], safe: Bool) -> CatalogCandidate? {
    guard components.count == 2, components[0] == "notes", components[1].hasSuffix(".note"),
      let number = Int(components[1].dropLast(5))
    else { return nil }
    return CatalogCandidate(
      components: components, handler: kind, date: Date(timeIntervalSince1970: Double(number)),
      stableID: String(format: "%06d", number), safe: safe)
  }
  func read(_ candidate: CatalogCandidate, root: URL) async throws -> CatalogReadValue {
    guard candidate.safe else { throw CatalogIssue.unsafe }
    let (data, version) = try CatalogSafeFiles.read(
      root: root, components: candidate.components, maximum: 1_024)
    guard let text = String(data: data, encoding: .utf8) else { throw CatalogIssue.malformed }
    return CatalogReadValue(
      version: version, assetID: candidate.stableID, createdAt: candidate.date,
      title: "Synthetic", favorite: nil, payload: SyntheticCatalogPayload(text: text),
      issue: text == "unsupported" ? .unsupported : nil, hasText: true, hasAudio: false)
  }
}

struct FileCatalogWorkerTests {
  @Test func secondKindDiscoversOutsideDiaryLayoutWithBoundedProgressAndStableOrder() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    for number in (0..<127).reversed() {
      try Data("Synthetic".utf8).write(to: root.appending(path: "notes/\(number).note"))
    }
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    registry.register(SyntheticCatalogHandler())
    let session = CatalogSessionID()
    let first = CatalogCursor(session: session, token: UUID())
    let worker = FileCatalogWorker(session: session, cursor: first, registry: registry)
    var cursor: CatalogCursor? = first
    var summaries: [CatalogSummary] = []
    var progress = 0
    var requests = 0
    while let current = cursor {
      requests += 1
      guard requests < 20 else {
        Issue.record("Catalog cursor did not finish")
        return
      }
      let page = try await worker.page(current, root: root)
      #expect(page.examinedCandidates <= 50)
      #expect(page.continuation != current)
      if page.isDiscovering {
        progress += 1
        #expect(page.summaries.isEmpty)
      }
      summaries.append(contentsOf: page.summaries)
      cursor = page.continuation
    }
    #expect(progress >= 3)
    #expect(summaries.count == 127)
    #expect(summaries.map(\.createdAt) == summaries.map(\.createdAt).sorted(by: >))
    #expect(Set(summaries.map(\.id)).count == 127)
    let handle = try #require(summaries.first?.handle)
    let detail = try await worker.detail(handle, root: root)
    #expect((detail.payload as? SyntheticCatalogPayload)?.text == "Synthetic")
    await #expect(throws: CatalogIssue.self) { try await worker.page(first, root: root) }
    try Data("Changed".utf8).write(to: root.appending(path: "notes/126.note"))
    await #expect(throws: CatalogIssue.self) { try await worker.detail(handle, root: root) }
  }

  @Test func badCandidateDoesNotBlockOthersAndUnsafeParentsCannotEscapeRoot() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("unsupported".utf8).write(to: root.appending(path: "notes/2.note"))
    try Data("Synthetic".utf8).write(to: root.appending(path: "notes/1.note"))
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "notes/3.note"),
      withDestinationURL: root.appending(path: "notes/1.note"))
    var registry = CatalogAssetRegistry()
    registry.register(SyntheticCatalogHandler())
    let session = CatalogSessionID()
    var cursor: CatalogCursor? = CatalogCursor(session: session, token: UUID())
    let worker = FileCatalogWorker(
      session: session, cursor: try #require(cursor), registry: registry)
    var recovery: [CatalogRecovery] = []
    var summaries: [CatalogSummary] = []
    while let current = cursor {
      let page = try await worker.page(current, root: root)
      recovery += page.recovery
      summaries += page.summaries
      cursor = page.continuation
    }
    #expect(recovery.map(\.issue).contains(.unsupported))
    #expect(recovery.map(\.issue).contains(.unsafe))
    #expect(summaries.count == 1)
    #expect(throws: CatalogIssue.self) {
      try CatalogSafeFiles.read(root: root, components: ["..", "outside"], maximum: 1_024)
    }
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "linked"), withDestinationURL: root.appending(path: "notes"))
    #expect(throws: CatalogIssue.self) {
      try CatalogSafeFiles.read(root: root, components: ["linked", "1.note"], maximum: 1_024)
    }
  }

  @Test func directoryReplacementAndFIFOAreRejectedWithoutFollowingOrBlocking() throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let cursor = try CatalogDirectoryCursor(root: root, components: ["notes"])
    _ = try cursor.next(root: root, components: ["notes"], maximum: 1)
    try Data("Synthetic".utf8).write(to: root.appending(path: "notes/new.note"))
    #expect(throws: CatalogIssue.self) {
      try cursor.next(root: root, components: ["notes"], maximum: 1)
    }
    let pipe = root.appending(path: "pipe")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: CatalogIssue.self) {
      try CatalogSafeFiles.read(root: root, components: ["pipe"], maximum: 1_024)
    }
  }

  private func fixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: root.appending(path: "notes"), withIntermediateDirectories: true)
    return root
  }
}
