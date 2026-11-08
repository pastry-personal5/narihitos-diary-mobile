// swift-format wraps multiline declarations and collections.
// swiftlint:disable opening_brace closure_parameter_position
import Foundation
import Testing

@testable import NarihitosDiary

struct ManualDiaryCodecTests {
  @Test func manualRoundTripPreservesBodyAndOmitsRecordingProvenance() throws {
    let body = "  A manually written day.\r\n\n한국어와 👨‍👩‍👧‍👦.\n---\n"
    var snippet = try Self.snippet(body)
    snippet.preservedScalars = [PreservedScalar(key: "custom_value", rawValue: "7", sourceOrder: 0)]
    let codec = DiarySnippetMarkdownCodec()
    let data = try codec.encode(snippet)
    guard case .supported(let decoded) = codec.decode(data) else {
      Issue.record("Manual text did not round trip")
      return
    }
    #expect(decoded.body == snippet.body)
    #expect(decoded.preservedScalars.map(\.key) == ["custom_value"])
    #expect(try codec.encode(decoded) == data)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("schema_version: 2\n"))
    #expect(text.contains("creation_method: \"manual\"\n"))
    #expect(!text.contains("audio_filename:"))
    #expect(!text.contains("transcription_method_id:"))
    #expect(!text.contains("recording_duration_ms:"))
    #expect(!text.contains("language:"))
  }

  @Test func manualDoesNotDowngradeBrokenRecordedAssetsOrAllowMixedResources() throws {
    let codec = DiarySnippetMarkdownCodec()
    let manual = try #require(
      String(data: codec.encode(Self.snippet("Written text.")), encoding: .utf8))
    let mixed = manual.replacingOccurrences(
      of: "favorite: false", with: "favorite: false\naudio_filename: \"fake.m4a\"")
    #expect(codec.decode(Data(mixed.utf8)) == .malformed(.invalidField))
    let missingDiscriminator = manual.replacingOccurrences(
      of: "creation_method: \"manual\"\n", with: "")
    #expect(codec.decode(Data(missingDiscriminator.utf8)) == .malformed(.missingRequiredField))
    let recorded = try #require(
      String(data: codec.encode(DiaryEditFixture.snippet()), encoding: .utf8))
    let broken = recorded.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.hasPrefix("audio_filename:") }.joined(separator: "\n")
    #expect(codec.decode(Data(broken.utf8)) == .malformed(.missingRequiredField))
  }

  @Test func manualEditKeepsSourceAndAllowsExistingEmptyBody() throws {
    let snippet = try Self.snippet("Written text.")
    let changed = try DiaryEditRevision.make(source: snippet, change: .body(""), now: .now)
    #expect(changed.creationMethod == .manual)
    #expect(changed.title == "Untitled")
    #expect(changed.audioFilename == nil)
    #expect(changed.transcription == nil)
    #expect(
      DiarySnippetMarkdownCodec().decode(try DiarySnippetMarkdownCodec().encode(changed))
        == .supported(changed))
  }

  @Test func textOnlyEditProofDoesNotRelaxRecordedCreationProof() {
    let version = DiaryPairVersion(
      markdownIdentity: "text", audioIdentity: "absent",
      markdownDigest: "digest", audioDigest: "absent", audioRequired: false)
    let proof = DiaryPairUploadObservation(
      markdown: DiaryFileUploadProof(identity: "text", digest: "digest"), audio: nil)
    #expect(!proof.proves(version))
    #expect(proof.provesEditResources(version))
    var recorded = version
    recorded.audioRequired = nil
    #expect(!proof.provesEditResources(recorded))
  }

  static func snippet(_ text: String) throws -> DiarySnippetV1 {
    let title = DiaryTitlePolicy.fallback(text)
    return DiarySnippetV1.manual(
      id: try AssetID("123e4567-e89b-42d3-a456-426614174000"),
      createdAt: try SchemaInstant("2026-01-02T03:04:05Z"), body: try DiaryBody(text),
      title: title.text, provenance: title.provenance)
  }
}

final class ManualUploadObserver: DiaryFileObserverPort, @unchecked Sendable {
  private let lock = NSLock()
  private var reportsUpload = false
  func setUploaded(_ value: Bool) { lock.withLock { reportsUpload = value } }

  func observe(_ url: URL, maximumBytes: Int64) throws -> DiaryFileObservation {
    report(try AppleDiaryFileObserver().observe(url, maximumBytes: maximumBytes))
  }

  func observeBounded(_ url: URL, maximumBytes: Int64, timeout: Duration) async throws
    -> DiaryFileObservation
  {
    report(
      try await AppleDiaryFileObserver().observeBounded(
        url, maximumBytes: maximumBytes, timeout: timeout))
  }

  private func report(_ value: DiaryFileObservation) -> DiaryFileObservation {
    DiaryFileObservation(
      identity: value.identity, digest: value.digest, byteCount: value.byteCount,
      uploaded: lock.withLock { reportsUpload }, modifiedAt: value.modifiedAt,
      hasUnresolvedConflict: value.hasUnresolvedConflict)
  }
}

@MainActor
struct ManualDiaryStorageTests {
  @Test func durableAcceptanceSurvivesRestartAndCompletesOnlyAfterTextUpload() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let root = disk.support.appending(path: "PrivateWorkspaces/ManualDiaries")
    let observer = ManualUploadObserver()
    let store = makeStore(disk, root: root, observer: observer)
    let submission = ManualDiarySubmission(
      id: UUID(), createdAt: Date(timeIntervalSince1970: 1_767_323_045),
      body: "  A synthetic written diary.\n\n한국어 입력.\n")
    let accepted = try await store.accept(submission)
    #expect(try await store.accept(submission) == accepted)
    #expect(try await store.body(accepted).text == submission.body)
    #expect(try ManualDiaryJournal.hasPending(in: root))
    let restarted = makeStore(disk, root: root, observer: observer)
    #expect(try await restarted.inventory() == [accepted])
    let ready = try await restarted.finalize(
      accepted, title: DiaryTitlePolicy.fallback(submission.body))
    #expect(try await !restarted.publish(ready))
    #expect(try await restarted.inventory().count == 1)
    let id = try AssetID(submission.id.uuidString.lowercased())
    let layout = try DiarySnippetLayout(
      id: id, createdAt: SchemaInstant.from(date: submission.createdAt))
    let day = layout.directoryComponents.reduce(disk.platform.url) { $0.appendingPathComponent($1) }
    #expect(
      !FileManager.default.fileExists(atPath: day.appending(path: layout.assetsDirectoryName).path))
    observer.setUploaded(true)
    #expect(try await restarted.publish(ready))
    #expect(try await restarted.inventory().isEmpty)
    #expect(try !ManualDiaryJournal.hasPending(in: root))
    // A completed Save keeps a small receipt without body/bookmark, so even an
    // uncertain acknowledgment after restart never creates a second asset.
    let afterCompletion = makeStore(disk, root: root, observer: observer)
    let retry = try await afterCompletion.accept(submission)
    #expect(retry.completed)
    #expect(try await afterCompletion.publish(retry))
    let receipt = try Data(
      contentsOf: root.appending(path: ManualDiaryJournal.completionName(submission.id)))
    let receiptText = try #require(String(data: receipt, encoding: .utf8))
    #expect(!receiptText.contains(submission.body))
    await #expect(throws: DiaryEditIssue.self) {
      try await afterCompletion.accept(
        ManualDiarySubmission(id: submission.id, createdAt: submission.createdAt, body: "Different")
      )
    }
  }

  @Test func externalReplacementIsNeverOverwrittenOrAdopted() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let observer = ManualUploadObserver()
    let store = makeStore(disk, root: disk.support.appending(path: "manual"), observer: observer)
    let submission = ManualDiarySubmission(id: UUID(), createdAt: .now, body: "A stable source.")
    let accepted = try await store.accept(submission)
    let ready = try await store.finalize(
      accepted, title: DiaryTitlePolicy.fallback(submission.body))
    #expect(try await !store.publish(ready))
    let layout = try DiarySnippetLayout(
      id: AssetID(ready.assetID), createdAt: SchemaInstant.from(date: submission.createdAt))
    let path = (layout.directoryComponents + [layout.markdownFilename]).reduce(disk.platform.url) {
      $0.appendingPathComponent($1)
    }
    let foreign = Data("Foreign content must survive.".utf8)
    try foreign.write(to: path, options: .atomic)
    observer.setUploaded(true)
    await #expect(throws: DiaryEditIssue.self) { try await store.publish(ready) }
    #expect(try Data(contentsOf: path) == foreign)
    #expect(try await store.inventory().count == 1)
  }

  @Test func retryFinishesInterruptedCleanupBeforeReportingCompletion() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let root = disk.support.appending(path: "manual")
    let observer = ManualUploadObserver()
    observer.setUploaded(true)
    let store = makeStore(disk, root: root, observer: observer)
    let submission = ManualDiarySubmission(
      id: UUID(), createdAt: .now, body: "Retained until cleanup.")
    let accepted = try await store.accept(submission)
    let ready = try await store.finalize(
      accepted, title: DiaryTitlePolicy.fallback(submission.body))
    let files = await store.journal.files
    let directory = try files.directory(submission.id)
    let obstruction = directory.appending(path: "unrecognized-file")
    try Data([1]).write(to: obstruction)
    await #expect(throws: DiaryEditIssue.self) { try await store.publish(ready) }
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "request.json").path))
    try FileManager.default.removeItem(at: obstruction)
    #expect(try await store.publish(ready))
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(try await store.inventory().isEmpty)
  }

  @Test func manualCatalogAndExactDeletionNeedNoAudio() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let snippet = try ManualDiaryCodecTests.snippet("An inert [link](https://example.invalid).")
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let day = layout.directoryComponents.reduce(root) { $0.appendingPathComponent($1) }
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let markdown = day.appending(path: layout.markdownFilename)
    try DiarySnippetMarkdownCodec().encode(snippet).write(to: markdown)
    let handler = DiaryCatalogHandler()
    let candidate = try #require(
      handler.candidate(
        components: layout.directoryComponents + [layout.markdownFilename], safe: true))
    let value = try await handler.read(candidate, root: root)
    #expect(value.issue == nil)
    #expect(!value.hasAudio)
    let detail = try #require(value.payload as? DiaryCatalogDetail)
    #expect(detail.isManual && !detail.isLegacy)
    #expect(detail.recordedAt == nil && detail.duration == nil && detail.language == nil)
    let resource = CatalogActionResource(candidate: candidate, version: value.version)
    let facts = try await CommittedDiaryResource.coordinated(resource, root: root) {
      root, control in
      try CommittedDiaryResource.inspect(resource, root: root, control: control)
    }
    #expect(!facts.version.requiresAudio)
    #expect(facts.audioComponents.isEmpty)
    try await DiaryPairDeletion.remove(resource, root: root)
    #expect(!FileManager.default.fileExists(atPath: markdown.path))
  }

  private func makeStore(_ disk: PurgeDiskFixture, root: URL, observer: ManualUploadObserver)
    -> AppleManualDiaryStore
  {
    AppleManualDiaryStore(
      destination: disk.destination, installation: FakeInstallationIdentity(), root: root,
      protection: DiaryFixtureProtection(), observer: observer, protectedDataAvailable: { true })
  }
}

@MainActor
struct ManualDiaryEditingTests {
  @Test func bodyAndFavoriteUseTextOnlyJournalAndVerifyNoAudioProof() async throws {
    let disk = try PurgeDiskFixture()
    defer { disk.close() }
    let observer = ManualUploadObserver()
    observer.setUploaded(true)
    let store = AppleManualDiaryStore(
      destination: disk.destination, installation: FakeInstallationIdentity(),
      root: disk.support.appending(path: "PrivateWorkspaces/ManualDiaries"),
      protection: DiaryFixtureProtection(),
      observer: observer, protectedDataAvailable: { true })
    let submission = ManualDiarySubmission(
      id: UUID(), createdAt: .now, body: "The original written text.")
    let accepted = try await store.accept(submission)
    let ready = try await store.finalize(
      accepted, title: DiaryTitlePolicy.fallback(submission.body))
    #expect(try await store.publish(ready))
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    let catalog = AppleAssetCatalog(destination: disk.destination, registry: registry)
    defer { catalog.end() }
    let handle = try await findHandle(catalog, assetID: ready.assetID)
    let edits = AppleDiaryEditStore(
      catalog: catalog, destination: disk.destination, installation: FakeInstallationIdentity(),
      root: disk.support.appending(path: "PrivateWorkspaces/DiaryEdits"),
      protection: DiaryFixtureProtection(),
      observer: observer, protectedDataAvailable: { true })
    let coordinator = DiaryEditCoordinator(
      store: edits,
      titles: DiaryTitlePolicy(model: EditTitleModel(), languageDetector: EditLanguageDetector()))
    coordinator.activate()
    defer { coordinator.deactivate() }
    try await wait { !coordinator.hasActiveWork }
    let session = try await coordinator.open(handle)
    #expect(session.snippet.creationMethod == .manual)
    let changed = "The new manually edited text. 한국어."
    let request = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body(changed))
    #expect(await coordinator.submit(request, session: session) == .accepted(request.id))
    try await wait { coordinator.pending.isEmpty && !coordinator.hasActiveWork }
    let next = try await findHandle(catalog, assetID: ready.assetID)
    let detail = try await catalog.detail(next)
    #expect((detail.payload as? DiaryCatalogDetail)?.body == changed)
    let favoriteSession = try await coordinator.open(next)
    let favorite = DiaryEditSubmission(
      id: UUID(), sessionID: favoriteSession.id, change: .favorite(true))
    #expect(await coordinator.submit(favorite, session: favoriteSession) == .accepted(favorite.id))
    try await wait { coordinator.pending.isEmpty && !coordinator.hasActiveWork }
    let final = try await catalog.detail(findHandle(catalog, assetID: ready.assetID))
    #expect((final.payload as? DiaryCatalogDetail)?.favorite == true)
  }

  private func findHandle(_ catalog: AppleAssetCatalog, assetID: String) async throws
    -> CatalogItemHandle
  {
    guard case .ready(_, let first) = await catalog.begin() else { throw CatalogIssue.unavailable }
    var cursor: CatalogCursor? = first
    var handle: CatalogItemHandle?
    while let current = cursor {
      let page = try await catalog.page(current)
      handle = page.summaries.first(where: { $0.assetID == assetID })?.handle ?? handle
      cursor = page.continuation
    }
    return try #require(handle)
  }

  private func wait(_ predicate: () -> Bool) async throws {
    let end = ContinuousClock.now.advanced(by: .seconds(10))
    while !predicate() {
      guard ContinuousClock.now < end else { throw DiaryEditIssue.busy }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}

// swiftlint:enable opening_brace closure_parameter_position
