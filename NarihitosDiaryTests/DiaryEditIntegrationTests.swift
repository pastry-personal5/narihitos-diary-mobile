import Darwin
import Foundation
import Testing

@testable import NarihitosDiary

// swift-format places braces after multiline result types.
// swiftlint:disable opening_brace

/// Synthetic provider reports still bind to real coordinated file observations.
private final class SyntheticEditUploadObserver: DiaryFileObserverPort, @unchecked Sendable {
  private let lock = NSLock()
  private var audioUploaded = true

  func setAudioUploaded(_ value: Bool) { lock.withLock { audioUploaded = value } }

  func observe(_ url: URL, maximumBytes: Int64) throws -> DiaryFileObservation {
    reported(try AppleDiaryFileObserver().observe(url, maximumBytes: maximumBytes), url: url)
  }

  func observeBounded(_ url: URL, maximumBytes: Int64, timeout: Duration) async throws
    -> DiaryFileObservation
  {
    reported(
      try await AppleDiaryFileObserver().observeBounded(
        url, maximumBytes: maximumBytes, timeout: timeout),
      url: url)
  }

  private func reported(_ observed: DiaryFileObservation, url: URL) -> DiaryFileObservation {
    DiaryFileObservation(
      identity: observed.identity, digest: observed.digest, byteCount: observed.byteCount,
      uploaded: url.pathExtension == "md" || lock.withLock { audioUploaded },
      modifiedAt: observed.modifiedAt, hasUnresolvedConflict: observed.hasUnresolvedConflict)
  }
}

@MainActor
private struct EditIntegrationFixture {
  let disk: PurgeDiskFixture
  let catalog: AppleAssetCatalog
  let store: AppleDiaryEditStore
  let coordinator: DiaryEditCoordinator
  let model: EditTitleModel
  let observer: SyntheticEditUploadObserver
  let markdown: URL
  let audio: URL
  let handle: CatalogItemHandle

  static func make() async throws -> EditIntegrationFixture {
    let disk = try PurgeDiskFixture()
    let legacy = try DiaryCatalogHandlerTests().makeLegacy()
    defer { try? FileManager.default.removeItem(at: legacy.root) }
    let snippet = try DiaryEditFixture.snippet()
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let day = layout.directoryComponents.reduce(disk.platform.url) { $0.appendingPathComponent($1) }
    let assets = day.appending(path: layout.assetsDirectoryName)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let audio = assets.appending(path: layout.audioFilename)
    try FileManager.default.copyItem(at: legacy.audio, to: audio)
    let markdown = day.appending(path: layout.markdownFilename)
    try DiarySnippetMarkdownCodec().encode(snippet).write(to: markdown)
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    let catalog = AppleAssetCatalog(destination: disk.destination, registry: registry)
    guard case .ready(_, let first) = await catalog.begin() else {
      throw DiaryEditIssue.unavailable
    }
    var cursor: CatalogCursor? = first
    var found: CatalogItemHandle?
    while let current = cursor {
      let page = try await catalog.page(current)
      found = page.summaries.first(where: { $0.assetID == snippet.id.description })?.handle ?? found
      cursor = page.continuation
    }
    let handle = try #require(found)
    let observer = SyntheticEditUploadObserver()
    let store = AppleDiaryEditStore(
      catalog: catalog, destination: disk.destination, installation: FakeInstallationIdentity(),
      root: disk.support.appending(path: "PrivateWorkspaces/DiaryEdits"),
      protection: DiaryFixtureProtection(), observer: observer, protectedDataAvailable: { true })
    let model = EditTitleModel()
    let coordinator = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: model, languageDetector: EditLanguageDetector()),
      retrySleep: { _ in try await Task.sleep(for: .milliseconds(50)) }
    )
    coordinator.activate()
    try await waitUntil { !coordinator.hasActiveWork }
    return EditIntegrationFixture(
      disk: disk, catalog: catalog, store: store, coordinator: coordinator, model: model,
      observer: observer, markdown: markdown, audio: audio, handle: handle)
  }

  static func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw DiaryEditIssue.busy }
      try await Task.sleep(for: .milliseconds(2))
    }
  }

  func close() {
    coordinator.deactivate()
    catalog.end()
    disk.close()
  }
}

@MainActor
struct DiaryEditIntegrationTests {
  @Test func realEditPipelineCompletesOnlyAfterPersistedProofAndFinalPairCheck() async throws {
    let fixture = try await EditIntegrationFixture.make()
    defer { fixture.close() }
    let audio = try Data(contentsOf: fixture.audio)
    let session = try await fixture.coordinator.open(fixture.handle)
    let intent = DiaryEditSubmission(
      id: UUID(), sessionID: session.id, change: .body("A synthetic new body."))
    #expect(await fixture.coordinator.submit(intent, session: session) == .accepted(intent.id))
    try await EditIntegrationFixture.waitUntil {
      !fixture.coordinator.hasActiveWork && fixture.coordinator.pending.isEmpty
    }
    let data = try Data(contentsOf: fixture.markdown)
    guard case .supported(let result) = DiarySnippetMarkdownCodec().decode(data) else {
      Issue.record("Edited pair must remain a supported diary")
      return
    }
    #expect(result.body.text == "A synthetic new body.")
    #expect(result.title == "A peaceful afternoon")
    #expect(result.transcription == session.snippet.transcription)
    #expect(result.language == session.snippet.language)
    #expect(try Data(contentsOf: fixture.audio) == audio)
    #expect(fixture.model.calls == 1)
    #expect(
      try PurgeFileTree.isEmpty(
        fixture.disk.support.appending(path: "PrivateWorkspaces/DiaryEdits")))
  }

  @Test func missingAudioUploadRetainsCandidateThenVerificationRetryCleansWithoutRetitling()
    async throws
  {
    let fixture = try await EditIntegrationFixture.make()
    defer { fixture.close() }
    fixture.observer.setAudioUploaded(false)
    let session = try await fixture.coordinator.open(fixture.handle)
    let intent = DiaryEditSubmission(
      id: UUID(), sessionID: session.id, change: .body("Retained body."))
    _ = await fixture.coordinator.submit(intent, session: session)
    try await EditIntegrationFixture.waitUntil { !fixture.coordinator.hasActiveWork }
    let pending = try #require(fixture.coordinator.pending.first)
    #expect(pending.issue == .upload)
    #expect(try await fixture.store.candidate(for: pending).body.text == "Retained body.")
    fixture.observer.setAudioUploaded(true)
    fixture.coordinator.prerequisiteChanged()
    try await EditIntegrationFixture.waitUntil {
      !fixture.coordinator.hasActiveWork && fixture.coordinator.pending.isEmpty
    }
    #expect(fixture.model.calls == 1)
  }

  @Test func favoriteNoOpDoesNotWriteOrStartTitleWorkAndSessionSurvivesForegroundReturn()
    async throws
  {
    let fixture = try await EditIntegrationFixture.make()
    defer { fixture.close() }
    let before = try Data(contentsOf: fixture.markdown)
    let session = try await fixture.coordinator.open(fixture.handle)
    fixture.coordinator.deactivate()
    fixture.coordinator.activate()
    let intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(false))
    #expect(await fixture.coordinator.submit(intent, session: session) == .unchanged)
    #expect(try Data(contentsOf: fixture.markdown) == before)
    #expect(fixture.model.calls == 0)
    fixture.coordinator.closeSession(session.id)
  }

  @Test func confirmedMaintenanceInvalidatesOldSubmissionAuthority() async throws {
    let fixture = try await EditIntegrationFixture.make()
    defer { fixture.close() }
    let before = try Data(contentsOf: fixture.markdown)
    let session = try await fixture.coordinator.open(fixture.handle)
    fixture.coordinator.suspendForMaintenance()
    fixture.coordinator.endMaintenance()
    fixture.coordinator.activate()
    try await EditIntegrationFixture.waitUntil { !fixture.coordinator.hasActiveWork }
    let intent = DiaryEditSubmission(
      id: UUID(), sessionID: session.id, change: .body("Stale callback."))
    #expect(await fixture.coordinator.submit(intent, session: session) == .rejected(.changed))
    #expect(try Data(contentsOf: fixture.markdown) == before)
  }

  @Test func externalEditAndSubmittedBodyHaveSeparateProtectedPairsWithSharedUnchangedAudio()
    async throws
  {
    let fixture = try await EditIntegrationFixture.make()
    defer { fixture.close() }
    fixture.model.hold = true
    let session = try await fixture.coordinator.open(fixture.handle)
    let intent = DiaryEditSubmission(
      id: UUID(), sessionID: session.id, change: .body("Submitted body."))
    _ = await fixture.coordinator.submit(intent, session: session)
    try await EditIntegrationFixture.waitUntil { fixture.model.continuation != nil }
    var external = session.snippet
    external.body = try DiaryBody("External body.")
    try DiarySnippetMarkdownCodec().encode(external).write(to: fixture.markdown, options: .atomic)
    fixture.model.continuation?.resume(
      returning: TitleModelReply(text: "A peaceful afternoon", outputTokens: 5))
    try await EditIntegrationFixture.waitUntil { !fixture.coordinator.hasActiveWork }
    let pending = try #require(fixture.coordinator.pending.first)
    #expect(pending.stage == .recovery)
    #expect(pending.issue == .changed)
    let snapshots = try await fixture.store.recoverySnapshots(for: pending.id)
    let snapshot = try #require(snapshots.first)
    #expect(snapshots.count == 1)
    #expect(snapshot.sharesSubmittedAudio)
    #expect(
      try await fixture.store.recoveryCandidate(recordID: pending.id, snapshotID: nil).body.text
        == "Submitted body.")
    #expect(
      try await fixture.store.recoveryCandidate(recordID: pending.id, snapshotID: snapshot.id).body
        .text == "External body.")
    #expect(
      DiaryPairConflictPolicy.select(
        first: DiaryPairModificationTimes(markdown: nil, audio: nil), second: snapshot.modifiedAt)
        == .userChoice)
    external.body = try DiaryBody("A later external body.")
    try DiarySnippetMarkdownCodec().encode(external).write(to: fixture.markdown, options: .atomic)
    #expect(
      try await fixture.store.recoveryCandidate(recordID: pending.id, snapshotID: snapshot.id).body
        .text == "External body.")
  }
}

// swiftlint:enable opening_brace
