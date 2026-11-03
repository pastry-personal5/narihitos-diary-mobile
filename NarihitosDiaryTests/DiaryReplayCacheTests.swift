import Foundation
import Testing

@testable import NarihitosDiary

private struct ReplayTestProtection: DraftFileProtectionPolicy {
  func applyAndVerify(to _: URL) throws {}
  func verify(_: URL) throws {}
}

struct DiaryReplayCacheTests {
  @Test func capacityAdmissionRefusesInsufficientSpaceButAllowsUnknownTelemetry() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "replay-capacity-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let refused = DiaryReplayCache(
      root: root, protection: ReplayTestProtection(), capacity: { _ in 0 })
    await #expect(throws: DiaryEditIssue.storage) {
      try await refused.prepare(UUID(), bytes: 1_024)
    }
    #expect(try PurgeFileTree.isEmpty(root))
    let unknown = DiaryReplayCache(
      root: root, protection: ReplayTestProtection(), capacity: { _ in nil })
    let id = UUID()
    _ = try await unknown.prepare(id, bytes: CatalogAudioInspector.maximumBytes)
    try await unknown.remove(id)
    await #expect(throws: DiaryEditIssue.unsupported) {
      try await unknown.prepare(UUID(), bytes: CatalogAudioInspector.maximumBytes + 1)
    }
    #expect(try PurgeFileTree.isEmpty(root))
  }

  @Test func partialCacheCleanupPreservesSourceAndUnknownEntries() async throws {
    let source = try DiaryCatalogHandlerTests().makeLegacy()
    defer { try? FileManager.default.removeItem(at: source.root) }
    let before = try Data(contentsOf: source.audio)
    let root = source.root.appending(path: "private-replay")
    let cache = DiaryReplayCache(root: root, protection: ReplayTestProtection())
    let id = UUID()
    let directory = try await cache.prepare(id, bytes: Int64(before.count))
    try before.prefix(before.count / 2).write(to: directory.appending(path: "audio.m4a"))
    try Data("unowned".utf8).write(to: root.appending(path: "unknown"))
    try await cache.reconcile()
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(try Data(contentsOf: source.audio) == before)
    #expect(try Data(contentsOf: root.appending(path: "unknown")) == Data("unowned".utf8))
  }

  @Test func unsafeCacheAudioCannotFollowOrRemoveAnExternalFile() async throws {
    let source = try DiaryCatalogHandlerTests().makeLegacy()
    defer { try? FileManager.default.removeItem(at: source.root) }
    let before = try Data(contentsOf: source.audio)
    let cache = DiaryReplayCache(
      root: source.root.appending(path: "private-replay"), protection: ReplayTestProtection())
    let id = UUID()
    let directory = try await cache.prepare(id, bytes: Int64(before.count))
    try FileManager.default.createSymbolicLink(
      at: directory.appending(path: "audio.m4a"), withDestinationURL: source.audio)
    await #expect(throws: CatalogIssue.unsafe) { try await cache.remove(id) }
    #expect(try Data(contentsOf: source.audio) == before)
  }
}
