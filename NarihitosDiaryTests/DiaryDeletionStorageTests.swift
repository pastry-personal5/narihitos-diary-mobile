import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct DiaryDeletionStorageTests {
  @Test func creationGuardRequiresCompletedCleanupAndNoCaptureWorkspace() throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let captures = disk.support.appending(path: "Captures")
    try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
    let queue = MemoryQueueStore()
    let id = try AssetID.random().description
    func settled() throws -> Bool {
      try AppleDiaryDeletionService.creationIsSettled(id: id, queue: queue, captures: captures)
    }
    #expect(try settled())
    let receipt = QueueReceipt(
      id: try WorkspaceID.random(), startedAt: .now, language: .english,
      destinationReference: UUID(), installationBinding: "synthetic",
      inspection: CaptureInspection(byteCount: 512, duration: 1, isMonoAAC: true, isPlayable: true))
    var job = QueueJob(receipt: receipt, state: .readyToSave)
    job.draftAssetID = id
    queue.values[job.id] = job
    #expect(try !settled())
    job.state = .saved
    queue.values[job.id] = job
    #expect(try !settled())
    job.commitCleanupDone = true
    queue.values[job.id] = job
    #expect(try settled())
    let workspace = captures.appending(path: job.id)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
    #expect(try !settled())
  }

  @Test(arguments: [false, true])
  func deletesOnlySelectedPairAndPreservesUnrelatedFiles(legacy: Bool) async throws {
    let fixture = try await DeletionDiskFixture.make(legacy: legacy)
    defer { fixture.close() }
    let unrelated = fixture.audio.deletingLastPathComponent().appending(path: "keep.txt")
    try Data("Keep this unrelated file.".utf8).write(to: unrelated)
    let outside = fixture.markdown.deletingLastPathComponent().appending(path: "other.md")
    try Data("Keep this other diary.".utf8).write(to: outside)
    // Rediscover after adding files so the legacy assets-directory version is current.
    let handle = try await fixture.discover()
    try await fixture.service().delete(handle)
    #expect(!FileManager.default.fileExists(atPath: fixture.markdown.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.audio.path))
    #expect(try String(contentsOf: unrelated, encoding: .utf8) == "Keep this unrelated file.")
    #expect(try String(contentsOf: outside, encoding: .utf8) == "Keep this other diary.")
  }

  @Test func changedPairAndSymlinkAreNeverDeleted() async throws {
    let fixture = try await DeletionDiskFixture.make()
    defer { fixture.close() }
    let handle = try await fixture.discover()
    let oldText = try Data(contentsOf: fixture.markdown)
    var snippet = try DiaryEditFixture.snippet()
    snippet.body = try DiaryBody("A newer external body.")
    let updated = try DiarySnippetMarkdownCodec().encode(snippet)
    try updated.write(to: fixture.markdown, options: .atomic)
    await #expect(throws: (any Error).self) { try await fixture.service().delete(handle) }
    #expect(try Data(contentsOf: fixture.markdown) == updated)
    #expect(FileManager.default.fileExists(atPath: fixture.audio.path))
    try oldText.write(to: fixture.markdown, options: .atomic)
    let current = try await fixture.discover()
    let outside = fixture.disk.support.appending(path: "outside.m4a")
    try FileManager.default.moveItem(at: fixture.audio, to: outside)
    try FileManager.default.createSymbolicLink(at: fixture.audio, withDestinationURL: outside)
    await #expect(throws: (any Error).self) { try await fixture.service().delete(current) }
    #expect(FileManager.default.fileExists(atPath: fixture.markdown.path))
    #expect(FileManager.default.fileExists(atPath: outside.path))
  }

  @Test func retainedCreationOrProtectedDataFailurePreservesBothFiles() async throws {
    let fixture = try await DeletionDiskFixture.make()
    defer { fixture.close() }
    let handle = try await fixture.discover()
    await #expect(throws: DiaryDeletionIssue.busy) {
      try await fixture.service(settled: false).delete(handle)
    }
    await #expect(throws: DiaryDeletionIssue.unavailable) {
      try await fixture.service(available: false).delete(handle)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.markdown.path))
    #expect(FileManager.default.fileExists(atPath: fixture.audio.path))
  }

  @Test func partialDeletionReportsIncompleteAndPreservesSurvivingText() async throws {
    let fixture = try await DeletionDiskFixture.make()
    defer { fixture.close() }
    let binding = try await fixture.catalog.actionBinding(fixture.discover())
    let text = try Data(contentsOf: fixture.markdown)
    await #expect(throws: DiaryDeletionIssue.incomplete) {
      try await DiaryPairDeletion.remove(binding.resource, root: fixture.disk.platform.url) {
        throw DiaryDeletionIssue.unavailable
      }
    }
    #expect(try Data(contentsOf: fixture.markdown) == text)
    #expect(!FileManager.default.fileExists(atPath: fixture.audio.path))
  }
}

@MainActor
private struct DeletionDiskFixture {
  let disk: PurgeDiskFixture
  let catalog: AppleAssetCatalog
  let markdown: URL
  let audio: URL

  static func make(legacy: Bool = false) async throws -> DeletionDiskFixture {
    let disk = try PurgeDiskFixture()
    let source = try DiaryCatalogHandlerTests().makeLegacy()
    defer { try? FileManager.default.removeItem(at: source.root) }
    let snippet = try DiaryEditFixture.snippet()
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let components =
      legacy ? Array(source.candidate.components.dropLast()) : layout.directoryComponents
    let day = components.reduce(disk.platform.url) { $0.appendingPathComponent($1) }
    let stem =
      legacy
      ? try #require(source.candidate.components.last) : String(layout.markdownFilename.dropLast(3))
    let directory = day.appending(path: stem + ".assets")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let audio = directory.appending(
      path: legacy ? source.audio.lastPathComponent : layout.audioFilename)
    try FileManager.default.copyItem(at: source.audio, to: audio)
    let markdown = day.appending(path: stem + ".md")
    let bytes =
      legacy
      ? try Data(contentsOf: source.markdown) : try DiarySnippetMarkdownCodec().encode(snippet)
    try bytes.write(to: markdown)
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    return DeletionDiskFixture(
      disk: disk, catalog: AppleAssetCatalog(destination: disk.destination, registry: registry),
      markdown: markdown, audio: audio)
  }

  func discover() async throws -> CatalogItemHandle {
    guard case .ready(_, let first) = await catalog.begin() else {
      throw DiaryDeletionIssue.unavailable
    }
    var cursor: CatalogCursor? = first
    var handle: CatalogItemHandle?
    while let next = cursor {
      let page = try await catalog.page(next)
      handle = page.summaries.first?.handle ?? handle
      cursor = page.continuation
    }
    return try #require(handle)
  }

  func service(settled: Bool = true, available: Bool = true) -> AppleDiaryDeletionService {
    AppleDiaryDeletionService(
      catalog: catalog, destination: disk.destination, creationIsSettled: { _ in settled },
      protectedDataAvailable: { available })
  }

  func close() {
    catalog.end()
    disk.close()
  }
}
