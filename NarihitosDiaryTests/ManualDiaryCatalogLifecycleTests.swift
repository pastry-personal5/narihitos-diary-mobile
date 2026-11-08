// swift-format wraps multiline closure parameters and declarations.
// swiftlint:disable closure_parameter_position
import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct ManualDiaryCatalogLifecycleTests {
  @Test func indexedCatalogResolvesTextOnlyRowsAgainstFreshMarkdown() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let snippet = try ManualDiaryCodecTests.snippet("A manual indexed diary.")
    let path = try write(snippet, root: disk.platform.url)
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    let catalog = AppleIndexedAssetCatalog(
      destination: disk.destination, registry: registry,
      index: SQLiteCatalogIndex(
        root: disk.support.appending(path: "cache"), protection: DiaryFixtureProtection()),
      environment: CatalogProjectionEnvironment(
        installation: FakeInstallationIdentity(), protectedDataAvailable: { true }))
    do {
      guard case .ready = await catalog.begin() else { throw CatalogIssue.unavailable }
      _ = try await catalog.remembered(after: nil)
      try await wait {
        catalog.projectionStatus?.metadataComplete == true
          && (catalog.projectionStatus?.demandSatisfied == true
            || catalog.projectionStatus?.exhausted == true)
      }
      let row = try #require(try await catalog.remembered(after: nil).rows.first)
      #expect(row.assetID == snippet.id.description)
      let detail = try await catalog.resolve(row.id)
      #expect((detail.payload as? DiaryCatalogDetail)?.isManual == true)
      try FileManager.default.removeItem(at: path)
      await #expect(throws: Error.self) { try await catalog.resolve(row.id) }
    } catch {
      catalog.end()
      await catalog.settled()
      throw error
    }
    catalog.end()
    await catalog.settled()
  }

  @Test func restoredAcceptanceNeverPublishesAndPendingTextBlocksFolderPurge() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let staging = disk.support.appending(path: "PrivateWorkspaces")
    let root = staging.appending(path: "ManualDiaries")
    let files = DiaryEditPrivateFiles(root: root, protection: DiaryFixtureProtection())
    let journal = ManualDiaryJournal(files: files)
    let destination = try await disk.destination.committedDestinationRecord()
    let submission = ManualDiarySubmission(
      id: UUID(), createdAt: .now, body: "Protected submitted text.")
    _ = try await journal.accept(
      submission, destination: destination,
      rootIdentity: CommittedDiaryResource.rootIdentity(disk.platform.url), installation: "original"
    )
    #expect(try !DiaryStagingNamespaces.isEmpty(staging))
    let restored = ManualDiaryJournal(files: files)
    await #expect(throws: DiaryEditIssue.reviewRequired) {
      try await restored.inventory(installation: "another")
    }
    #expect(try await journal.envelope(submission.id, installation: "original").markdown.count > 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: disk.platform.url.path).isEmpty)
    let purge = disk.service()
    await #expect(throws: PurgeFailure.self) { try await purge.prepare(.activeFolder) }
  }

  @Test func externalManualRevisionIsRetainedAsTextOnlyConflictSnapshot() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let source = try ManualDiaryCodecTests.snippet("Original text.")
    let path = try write(source, root: disk.platform.url)
    let layout = DiarySnippetLayout(id: source.id, createdAt: source.createdAt)
    let handler = DiaryCatalogHandler()
    let candidate = try #require(
      handler.candidate(
        components: layout.directoryComponents + [layout.markdownFilename], safe: true))
    let value = try await handler.read(candidate, root: disk.platform.url)
    let resource = CatalogActionResource(candidate: candidate, version: value.version)
    let facts = try await CommittedDiaryResource.coordinated(resource, root: disk.platform.url) {
      root, control in
      try CommittedDiaryResource.inspect(resource, root: root, control: control)
    }
    let destination = try await disk.destination.committedDestinationRecord()
    let id = UUID()
    let binding = DiaryEditBinding(
      schema: 1, id: UUID(), transactionID: id,
      installationBinding: "current",
      resourceKey: CommittedDiaryResource.resourceKey(
        destinationID: destination.id, rootIdentity: facts.rootIdentity, candidate: candidate),
      destination: destination, rootIdentity: facts.rootIdentity, candidate: candidate,
      sourceVersion: facts.version, markdownContentIdentity: facts.markdownContentIdentity,
      audioContentIdentity: facts.audioContentIdentity, audioComponents: [], audioByteCount: 0,
      submissionDigest: CommittedDiaryResource.submissionDigest(.body("My submitted edit.")),
      publicationToken: UUID())
    let files = DiaryEditPrivateFiles(
      root: disk.support.appending(path: "PrivateWorkspaces/DiaryEdits"),
      protection: DiaryFixtureProtection())
    let journal = DiaryEditJournal(files: files)
    _ = try await journal.inventory(after: nil, installation: "current")
    _ = try await journal.prepare(binding)
    let local = try DiaryEditRevision.make(
      source: source, change: .body("My submitted edit."), now: .now)
    let accepted = try await journal.accept(binding, candidate: local, regeneratesTitle: true)
    var foreign = source
    foreign.body = try DiaryBody("The external writer’s version.")
    try DiarySnippetMarkdownCodec().encode(foreign).write(to: path, options: .atomic)
    let snapshot = try DiaryEditConflictSnapshots(files: files).capture(
      accepted, binding: binding,
      root: disk.platform.url, control: CatalogReadControl())
    #expect(!snapshot.version.requiresAudio)
    #expect(
      try DiaryEditConflictSnapshots(files: files).preview(accepted, snapshotID: snapshot.id).body
        == foreign.body)
    #expect(try await journal.candidate(accepted).body == local.body)
    #expect(try Data(contentsOf: path) == DiarySnippetMarkdownCodec().encode(foreign))
  }

  private func write(_ snippet: DiarySnippetV1, root: URL) throws -> URL {
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let day = layout.directoryComponents.reduce(root) { $0.appendingPathComponent($1) }
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let url = day.appending(path: layout.markdownFilename)
    try DiarySnippetMarkdownCodec().encode(snippet).write(to: url)
    return url
  }

  private func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !predicate() {
      guard ContinuousClock.now < deadline else { throw CatalogIssue.unavailable }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}
// swiftlint:enable closure_parameter_position
