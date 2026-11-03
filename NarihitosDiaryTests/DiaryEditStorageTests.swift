import Darwin
import Foundation
import Testing

@testable import NarihitosDiary

// swift-format places braces after multiline result types.
// swiftlint:disable opening_brace

struct EditStorageFixture {
  let root: URL
  let markdown: URL
  let audio: URL
  let candidate: CatalogCandidate
  let binding: DiaryEditBinding
  let files: DiaryEditPrivateFiles
  let journal: DiaryEditJournal
  let record: DiaryEditRecord
  let snippet: DiarySnippetV1
}

struct DiaryEditStorageTests {
  func fixture() async throws -> EditStorageFixture {
    let legacy = try DiaryCatalogHandlerTests().makeLegacy()
    let snippet = try DiaryEditFixture.snippet()
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let day = layout.directoryComponents.reduce(legacy.root) { $0.appendingPathComponent($1) }
    let assets = day.appending(path: layout.assetsDirectoryName)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let audio = assets.appending(path: layout.audioFilename)
    try FileManager.default.copyItem(at: legacy.audio, to: audio)
    let markdown = day.appending(path: layout.markdownFilename)
    try DiarySnippetMarkdownCodec().encode(snippet).write(to: markdown)
    let handler = DiaryCatalogHandler()
    let candidate = try #require(
      handler.candidate(
        components: layout.directoryComponents + [layout.markdownFilename], safe: true))
    let read = try await handler.read(candidate, root: legacy.root)
    let resource = CatalogActionResource(candidate: candidate, version: read.version)
    let facts = try await readFacts(resource, root: legacy.root)
    let files = DiaryEditPrivateFiles(
      root: legacy.root.appending(path: "private/DiaryEdits"), protection: DiaryFixtureProtection())
    let journal = DiaryEditJournal(files: files)
    _ = try await journal.inventory(after: nil, installation: "installation")
    let id = UUID()
    let destinationID = DestinationID.make().rawValue
    let key = CommittedDiaryResource.resourceKey(
      destinationID: destinationID, rootIdentity: facts.rootIdentity, candidate: candidate)
    let binding = DiaryEditBinding(
      schema: 1, id: UUID(), transactionID: id, installationBinding: "installation",
      resourceKey: key,
      destination: StoredDestinationRecord(
        id: destinationID, displayName: "Synthetic", bookmark: Data([1]),
        identityArchive: Data([2]), disclosureAcknowledged: true),
      rootIdentity: facts.rootIdentity, candidate: candidate, sourceVersion: facts.version,
      markdownContentIdentity: facts.markdownContentIdentity,
      audioContentIdentity: facts.audioContentIdentity,
      audioComponents: facts.audioComponents, audioByteCount: facts.audioBytes,
      submissionDigest: CommittedDiaryResource.submissionDigest(.body("A changed diary.")),
      publicationToken: UUID())
    let directory = try await journal.prepare(binding)
    try files.copyAudio(
      root: legacy.root, components: facts.audioComponents,
      expected: facts.audioVersion, to: directory, control: CatalogReadControl())
    let changed = try DiaryEditRevision.make(
      source: snippet, change: .body("A changed diary."), now: .distantPast)
    let record = try await journal.accept(binding, candidate: changed, regeneratesTitle: true)
    let retained = try await journal.candidate(record)
    return EditStorageFixture(
      root: legacy.root, markdown: markdown, audio: audio, candidate: candidate,
      binding: binding, files: files, journal: journal, record: record, snippet: retained)
  }

  private func readFacts(_ resource: CatalogActionResource, root: URL) async throws
    -> CommittedDiaryFacts
  {
    try await CommittedDiaryResource.coordinated(resource, root: root) { root, control in
      try CommittedDiaryResource.inspect(resource, root: root, control: control)
    }
  }

  @Test func acceptedJournalReopensWithoutBrowseUUIDsAndRetainsExactAudio() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let reopened = DiaryEditJournal(files: fixture.files)
    let page = try await reopened.inventory(after: nil, installation: "installation")
    #expect(page.records == [fixture.record])
    #expect(page.isolatedCount == 0)
    #expect(try await reopened.candidate(fixture.record) == fixture.snippet)
    let directory = try fixture.files.directory(fixture.record.id)
    let artifacts = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isExcludedFromBackupKey])
    #expect(artifacts.count == 4)
    for artifact in [fixture.files.root, directory] + artifacts {
      try DiaryFixtureProtection().verify(artifact)
      #expect(
        try artifact.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
          == true)
    }
    try fixture.files.verifyAudio(fixture.binding)
    let bindingData = try fixture.files.read(
      "binding.json", id: fixture.record.id, maximum: 128 * 1_024)
    let text = try #require(String(data: bindingData, encoding: .utf8))
    #expect(!text.contains("sessionID"))
    #expect(!text.contains("CatalogItemHandle"))
    #expect(!text.contains("file://"))
    await #expect(throws: DiaryEditIssue.busy) {
      try await reopened.assertAvailable(resourceKey: fixture.record.resourceKey)
    }
  }

  @Test func otherInstallationIsQuarantinedAndCorruptSiblingIsIsolated() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let malformed = fixture.files.root.appending(path: UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: false)
    try Data("malformed".utf8).write(to: malformed.appending(path: "binding.json"))
    let reopened = DiaryEditJournal(files: fixture.files)
    let page = try await reopened.inventory(after: nil, installation: "another-installation")
    #expect(page.isolatedCount == 1)
    #expect(page.records.count == 1)
    #expect(page.records.first?.stage == .quarantined)
    #expect(page.records.first?.issue == .reviewRequired)
    #expect(try Data(contentsOf: fixture.audio).count > 0)
  }

  @Test func failedFinalizationPreservesAcceptedBodyAndAllFields() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var invalid = fixture.snippet
    invalid.titleProvenance = TitleProvenance(
      originID: try TitleOriginID("apple-ai"), promptRevision: "title-v1",
      osVersion: String(repeating: "x", count: 8_193), modelID: nil)
    await #expect(throws: DiaryEditIssue.invalidCandidate) {
      try await fixture.journal.finalize(fixture.record, candidate: invalid)
    }
    #expect(try await fixture.journal.candidate(fixture.record) == fixture.snippet)
    #expect(try fixture.files.readRecord(fixture.record.id).stage == .accepted)
    var forbidden = fixture.snippet
    forbidden.favorite = true
    await #expect(throws: DiaryEditIssue.changed) {
      try await fixture.journal.finalize(fixture.record, candidate: forbidden)
    }
  }

  @Test func checkedReplacementPreservesAudioAndReconcilesCrashBeforeCheckpoint() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let audioBefore = try Data(contentsOf: fixture.audio)
    let ready = try await fixture.journal.finalize(fixture.record, candidate: fixture.snippet)
    let publication = try await DiaryEditPublicationAdapter.publish(
      ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
      files: fixture.files)
    guard case .verified(let first) = publication else {
      Issue.record("Expected checked publication")
      return
    }
    #expect(first.markdownIdentity != ready.sourceVersion.markdownIdentity)
    #expect(first.audioIdentity == ready.sourceVersion.audioIdentity)
    #expect(try Data(contentsOf: fixture.audio) == audioBefore)
    let retry = try await DiaryEditPublicationAdapter.publish(
      ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
      files: fixture.files)
    guard case .verified(let second) = retry else {
      Issue.record("Expected own-publication adoption after restart")
      return
    }
    #expect(second == first)
    #expect(try fixture.files.readRecord(ready.id).stage == .ready)
  }

  @Test func externalRevisionBeforeSaveIsNotOverwritten() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ready = try await fixture.journal.finalize(fixture.record, candidate: fixture.snippet)
    var external = try DiaryEditFixture.snippet(body: "External edit.")
    external.favorite = true
    let bytes = try DiarySnippetMarkdownCodec().encode(external)
    try bytes.write(to: fixture.markdown, options: .atomic)
    await #expect(throws: DiaryEditIssue.changed) {
      try await DiaryEditPublicationAdapter.publish(
        ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
        files: fixture.files)
    }
    #expect(try Data(contentsOf: fixture.markdown) == bytes)
    #expect(try await fixture.journal.candidate(ready).body.text == "A changed diary.")
  }

  @Test func copiedPublicationMarkerAndBytesCannotAuthorizeAdoption() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ready = try await fixture.journal.finalize(fixture.record, candidate: fixture.snippet)
    _ = try await DiaryEditPublicationAdapter.publish(
      ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
      files: fixture.files)
    let copied = fixture.markdown.deletingLastPathComponent().appending(path: "copied.md")
    try FileManager.default.copyItem(at: fixture.markdown, to: copied)
    try FileManager.default.removeItem(at: fixture.markdown)
    try FileManager.default.moveItem(at: copied, to: fixture.markdown)
    await #expect(throws: DiaryEditIssue.changed) {
      try await DiaryEditPublicationAdapter.publish(
        ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
        files: fixture.files)
    }
    #expect(try await fixture.journal.candidate(ready).body.text == "A changed diary.")
  }

  @Test func providerMetadataChangesRecheckpointOwnedVersionsWithoutRewritingAudio() async throws {
    let fixture = try await fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ready = try await fixture.journal.finalize(fixture.record, candidate: fixture.snippet)
    let audio = try Data(contentsOf: fixture.audio)
    try metadataChange(fixture.audio)
    guard
      case .verified(let first) = try await DiaryEditPublicationAdapter.publish(
        ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
        files: fixture.files)
    else {
      Issue.record("Expected source metadata revalidation")
      return
    }
    var published = ready
    published.stage = .published
    published.publishedVersion = first
    try await fixture.journal.checkpoint(published)
    try metadataChange(fixture.markdown)
    await #expect(throws: DiaryEditIssue.upload) {
      try await DiaryEditPublicationAdapter.verify(
        published, binding: fixture.binding, root: fixture.root, files: fixture.files)
    }
    guard
      case .verified(let current) = try await DiaryEditPublicationAdapter.publish(
        published, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
        files: fixture.files)
    else {
      Issue.record("Expected owned-version recheckpoint")
      return
    }
    #expect(current.markdownDigest == first.markdownDigest)
    #expect(current.markdownIdentity != first.markdownIdentity)
    #expect(try Data(contentsOf: fixture.audio) == audio)
  }

  private func metadataChange(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw DiaryEditIssue.localData }
    defer { close(descriptor) }
    var byte: UInt8 = 1
    guard fsetxattr(descriptor, "com.narihitosdiary.synthetic-metadata", &byte, 1, 0, 0) == 0 else {
      throw DiaryEditIssue.localData
    }
  }
}

// swiftlint:enable opening_brace
