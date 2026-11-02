import CryptoKit
import Darwin
import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable file_length

@MainActor
private final class PairTestDestinationStore: DestinationSettingsStore {
  var record: StoredDestinationRecord
  init(_ record: StoredDestinationRecord) { self.record = record }
  func loadDestination() -> StoredDestinationRecord? { record }
  func saveDestination(_: StoredDestinationRecord) throws {}
}

@MainActor
private final class PairTestDestinationPlatform: DestinationPlatform {
  let url: URL
  var alternateURL: URL?
  var identity = Data([0x44])
  var scopeCount = 0

  init(url: URL) { self.url = url }

  func startAccessing(_: URL) -> Bool {
    scopeCount += 1
    return true
  }
  func stopAccessing(_: URL) { scopeCount -= 1 }
  func inspect(_: URL) throws -> DestinationCandidateInspection {
    DestinationCandidateInspection(
      facts: DestinationCandidateFacts(
        isDirectory: true, isSymbolicLink: false, isUbiquitousItem: true,
        hasICloudIdentity: true),
      displayName: "Diary")
  }
  func makeBookmark(for _: URL) throws -> Data { Data([0x33]) }
  func resolveBookmark(_ bookmark: Data) throws -> ResolvedDestinationBookmark {
    ResolvedDestinationBookmark(
      url: bookmark == Data([0x99]) ? alternateURL ?? url : url, isStale: false)
  }
  func currentIdentityArchive() throws -> Data { identity }
  func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool {
    stored == current
  }
}

@MainActor
private final class PairTestPayload: DiaryCommitPayloadPort {
  let markdownBytes: Data
  let audioBytes: Data
  init(markdown: Data, audio: Data) {
    markdownBytes = markdown
    audioBytes = audio
  }
  func markdown(job _: QueueJob, intent _: DiaryCommitRecord) throws -> Data { markdownBytes }
  func audio(job _: QueueJob, intent _: DiaryCommitRecord) throws -> Data { audioBytes }
}

@MainActor
private final class PairCheckpointDrafts: DiaryDraftStore {
  let draft: VerifiedDiaryDraft
  init(_ draft: VerifiedDiaryDraft) { self.draft = draft }
  func publish(_: DiarySnippetV1, candidate _: TranscriptionPayload, job _: QueueJob) throws {}
  func inspect(job _: QueueJob) throws -> DiaryDraftInspection { .verified }
  func readVerified(job _: QueueJob) throws -> VerifiedDiaryDraft { draft }
}

@MainActor
private final class PairCheckpointCleanup: DiaryCommitCleanupPort {
  var calls = 0
  func removeOwnedStaging(job _: QueueJob) throws { calls += 1 }
}

private struct PairConflictVersions: DiaryExternalVersionSourcePort {
  let markdown: [DiaryExternalVersion]
  let audio: [DiaryExternalVersion]

  func versions(at url: URL) -> [DiaryExternalVersion] {
    url.pathExtension == "md" ? markdown : audio
  }
}

private struct PairConflictProtection: DraftFileProtectionPolicy {
  func applyAndVerify(to _: URL) throws {}
  func verify(_: URL) throws {}
}

private struct PairConflictAudioValidator: ConflictSnapshotAudioValidator {
  func isPlayable(_: Data) -> Bool { true }
}

private struct PairUploadedObserver: DiaryFileObserverPort {
  private let base = AppleDiaryFileObserver()

  func observe(_ url: URL, maximumBytes: Int64) throws -> DiaryFileObservation {
    uploaded(try base.observe(url, maximumBytes: maximumBytes))
  }

  func observeBounded(
    _ url: URL, maximumBytes: Int64, timeout: Duration
  ) async throws -> DiaryFileObservation {
    uploaded(
      try await base.observeBounded(
        url, maximumBytes: maximumBytes, timeout: timeout))
  }

  private func uploaded(_ value: DiaryFileObservation) -> DiaryFileObservation {
    DiaryFileObservation(
      identity: value.identity, digest: value.digest, byteCount: value.byteCount,
      uploaded: true, modifiedAt: value.modifiedAt,
      hasUnresolvedConflict: value.hasUnresolvedConflict)
  }
}

/// A third read simulates a provider becoming unavailable after the verified
/// observation. Interrupted-publication adoption must return that observation.
private final class PairTwoReadObserver: DiaryFileObserverPort, @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  private let base = AppleDiaryFileObserver()

  func observe(_ url: URL, maximumBytes: Int64) throws -> DiaryFileObservation {
    try base.observe(url, maximumBytes: maximumBytes)
  }

  func observeBounded(
    _ url: URL, maximumBytes: Int64, timeout: Duration
  ) async throws -> DiaryFileObservation {
    let allowed = lock.withLock {
      reads += 1
      return reads <= 2
    }
    guard allowed else { throw DiaryFileObservationFailure.unavailable }
    return try await base.observeBounded(url, maximumBytes: maximumBytes, timeout: timeout)
  }
}

@MainActor
private final class PairVersionCleaner: DiaryConflictVersionCleanerPort {
  var cleaned: [URL] = []
  func removeObsolete(
    at url: URL, current _: DiaryFileVersion,
    knownVersions _: [DiaryObsoleteFileVersion]
  ) async -> DiaryConflictCleanupResult {
    cleaned.append(url)
    return .done
  }
}

@MainActor
private struct PairStoreFixture {
  let root: URL
  let external: URL
  let store: AppleDiaryPairStore
  let platform: PairTestDestinationPlatform
  let job: QueueJob
  let intent: DiaryCommitRecord
  let markdownBytes: Data
  let repository: PairTestDestinationStore
  let destination: AppleDestinationService
  let captures: CapturePrivateFiles
  let draft: VerifiedDiaryDraft
}

@MainActor
// swiftlint:disable:next type_body_length
struct AppleDiaryPairStoreTests {
  @Test func publishesAudioBeforeMarkdownAndReopensExactPair() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var intent = fixture.intent
    var job = fixture.job

    guard case .verified(let audio) = await fixture.store.ensureAudio(intent, job: job) else {
      Issue.record("Audio was not created")
      return
    }
    let paths = paths(for: intent, root: fixture.external)
    #expect(FileManager.default.fileExists(atPath: paths.audio.path))
    #expect(!FileManager.default.fileExists(atPath: paths.markdown.path))
    intent.audioVersion = audio
    job.commit = intent

    guard case .verified(let markdown) = await fixture.store.ensureMarkdown(intent, job: job)
    else {
      Issue.record("Markdown was not created")
      return
    }
    intent.markdownVersion = markdown
    job.commit = intent
    guard case .verified(let pair) = await fixture.store.verifyPair(intent, job: job) else {
      Issue.record("Pair verification failed")
      return
    }
    #expect(pair.audioIdentity == audio.identity)
    #expect(pair.markdownIdentity == markdown.identity)
    #expect(try Data(contentsOf: paths.markdown) == fixture.markdownBytes)
    #expect(await fixture.store.verifyUnchanged(pair, intent: intent) == .unchanged)
    let upload = await fixture.store.observeUploads(pair, intent: intent)
    #expect(upload.markdown == nil)
    #expect(upload.audio == nil)
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func metadataOnlyChangesDoNotInvalidatePublishedPair() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var pair = try #require(await createPair(fixture))
    let paths = paths(for: pair.intent, root: fixture.external)
    guard case .verified(let version) = await fixture.store.verifyPair(pair.intent, job: pair.job)
    else {
      Issue.record("Expected published pair")
      return
    }

    try changeProviderMetadata(paths.audio)
    try changeProviderMetadata(paths.markdown)

    #expect(await fixture.store.verifyPair(pair.intent, job: pair.job) == .waiting(.upload))
    #expect(await fixture.store.verifyUnchanged(version, intent: pair.intent) == .waiting)
    guard case .repaired(let audio) = await fixture.store.ensureAudio(pair.intent, job: pair.job)
    else {
      Issue.record("Expected owned audio recheckpoint")
      return
    }
    pair.intent.audioVersion = audio
    pair.job.commit = pair.intent
    guard
      case .repaired(let markdown) = await fixture.store.ensureMarkdown(pair.intent, job: pair.job)
    else {
      Issue.record("Expected owned Markdown recheckpoint")
      return
    }
    pair.intent.markdownVersion = markdown
    pair.job.commit = pair.intent
    guard case .verified(let refreshed) = await fixture.store.verifyPair(pair.intent, job: pair.job)
    else {
      Issue.record("Expected reverified pair")
      return
    }
    #expect(await fixture.store.verifyUnchanged(refreshed, intent: pair.intent) == .unchanged)
    #expect(
      await fixture.store.observeUploads(refreshed, intent: pair.intent)
        == DiaryPairUploadObservation(markdown: nil, audio: nil))
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func reopenedSaveAfterMetadataChangeWaitsForBothUploads() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let queue = MemoryQueueStore()
    queue.values[fixture.job.id] = fixture.job
    let cleanup = PairCheckpointCleanup()
    let coordinator = DiaryCommitCoordinator(
      queue: queue, drafts: PairCheckpointDrafts(fixture.draft),
      pairs: fixture.store, cleanup: cleanup)
    await coordinator.attempt(jobID: fixture.job.id)
    let published = try #require(queue.values[fixture.job.id])
    #expect(published.reason == DiaryCommitWait.upload.message)
    let paths = paths(for: fixture.intent, root: fixture.external)
    try changeProviderMetadata(paths.audio)
    try changeProviderMetadata(paths.markdown)

    let reopened = DiaryCommitCoordinator(
      queue: queue, drafts: PairCheckpointDrafts(fixture.draft),
      pairs: fixture.store, cleanup: cleanup)
    await reopened.attempt(jobID: fixture.job.id)
    #expect(queue.values[fixture.job.id]?.reason == DiaryCommitWait.upload.message)
    #expect(queue.values[fixture.job.id]?.commit?.audioVersion != published.commit?.audioVersion)
    #expect(
      queue.values[fixture.job.id]?.commit?.markdownVersion != published.commit?.markdownVersion)
    #expect(cleanup.calls == 0)
    let uploadedStore = AppleDiaryPairStore(
      destination: fixture.destination, captures: fixture.captures,
      payload: PairTestPayload(
        markdown: fixture.markdownBytes, audio: Data(repeating: 0x41, count: 512)),
      observer: PairUploadedObserver())
    let uploaded = DiaryCommitCoordinator(
      queue: queue, drafts: PairCheckpointDrafts(fixture.draft), pairs: uploadedStore,
      cleanup: cleanup)
    await uploaded.attempt(jobID: fixture.job.id)
    #expect(queue.values[fixture.job.id]?.state == .saved)
    #expect(cleanup.calls == 1)
    #expect(try Data(contentsOf: paths.markdown) == fixture.markdownBytes)
    #expect(try Data(contentsOf: paths.audio) == Data(repeating: 0x41, count: 512))
  }

  @Test(arguments: ["changed-bytes", "replaced-inode", "missing-marker"])
  func metadataRecoveryRejectsUnownedOrChangedAudio(change: String) async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let pair = try #require(await createPair(fixture))
    let audio = paths(for: pair.intent, root: fixture.external).audio
    if change == "changed-bytes" {
      let modified = try audio.resourceValues(forKeys: [.contentModificationDateKey])
      let handle = try FileHandle(forWritingTo: audio)
      try handle.write(contentsOf: Data(repeating: 0x42, count: 512))
      try handle.close()
      try FileManager.default.setAttributes(
        [.modificationDate: try #require(modified.contentModificationDate)],
        ofItemAtPath: audio.path)
    } else if change == "replaced-inode" {
      let copy = audio.appendingPathExtension("copy")
      try FileManager.default.copyItem(at: audio, to: copy)
      try FileManager.default.removeItem(at: audio)
      try FileManager.default.moveItem(at: copy, to: audio)
    } else {
      #expect(removexattr(audio.path, "com.narihitosdiary.commit-creation", 0) == 0)
    }
    #expect(await fixture.store.ensureAudio(pair.intent, job: pair.job) == .recoveryRequired)
    #expect(await fixture.store.verifyPair(pair.intent, job: pair.job) == .recoveryRequired)
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func missingFileRepairsAfterSurvivorMetadataChanges() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let pair = try #require(await createPair(fixture))
    let paths = paths(for: pair.intent, root: fixture.external)
    try changeProviderMetadata(paths.markdown)
    try FileManager.default.removeItem(at: paths.audio)
    guard case .repaired = await fixture.store.ensureAudio(pair.intent, job: pair.job)
    else {
      Issue.record("Expected owned pair repair")
      return
    }
    #expect(try Data(contentsOf: paths.audio) == Data(repeating: 0x41, count: 512))
  }

  @Test func preexistingExactBytesWithoutRecordedVersionAreCollision() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let paths = paths(for: fixture.intent, root: fixture.external)
    try FileManager.default.createDirectory(
      at: paths.audio.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x41, count: 512).write(to: paths.audio)
    #expect(
      await fixture.store.ensureAudio(fixture.intent, job: fixture.job)
        == .recoveryRequired)
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func interruptedVersionCheckpointAdoptsOnlyMarkedExactFile() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    guard
      case .verified(let created) = await fixture.store.ensureAudio(
        fixture.intent, job: fixture.job)
    else {
      Issue.record("Expected first audio creation")
      return
    }
    #expect(
      await fixture.store.ensureAudio(fixture.intent, job: fixture.job)
        == .verified(created))
    let paths = paths(for: fixture.intent, root: fixture.external)
    try Data(repeating: 0x42, count: 512).write(to: paths.audio)
    #expect(
      await fixture.store.ensureAudio(fixture.intent, job: fixture.job)
        == .recoveryRequired)
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func copiedCreationMarkerCannotClaimDifferentFile() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    guard
      case .verified = await fixture.store.ensureAudio(
        fixture.intent, job: fixture.job)
    else {
      Issue.record("Expected marked audio creation")
      return
    }
    let original = paths(for: fixture.intent, root: fixture.external).audio
    let copy = original.appendingPathExtension("copy")
    let markerName = "com.narihitosdiary.commit-creation"
    let size = getxattr(original.path, markerName, nil, 0, 0, 0)
    #expect(size > 0)
    var marker = [UInt8](repeating: 0, count: max(0, size))
    let markerCount = marker.count
    let read = marker.withUnsafeMutableBytes { raw in
      getxattr(original.path, markerName, raw.baseAddress, markerCount, 0, 0)
    }
    #expect(read == size)
    try FileManager.default.copyItem(at: original, to: copy)
    let set = marker.withUnsafeBytes { raw in
      setxattr(copy.path, markerName, raw.baseAddress, markerCount, 0, 0)
    }
    #expect(set == 0)
    try FileManager.default.removeItem(at: original)
    try FileManager.default.moveItem(at: copy, to: original)
    #expect(
      await fixture.store.ensureAudio(fixture.intent, job: fixture.job)
        == .recoveryRequired)
  }

  @Test func queueCheckpointFailureRetriesSameAudioWithoutDuplicateWrite() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let queue = MemoryQueueStore()
    queue.values[fixture.job.id] = fixture.job
    let coordinator = DiaryCommitCoordinator(
      queue: queue, drafts: PairCheckpointDrafts(fixture.draft),
      pairs: fixture.store, cleanup: PairCheckpointCleanup())
    queue.shouldFailReplace = { job in
      job.commit?.audioVersion != nil && job.commit?.markdownVersion == nil
    }
    await coordinator.attempt(jobID: fixture.job.id)
    let interrupted = try #require(queue.values[fixture.job.id])
    #expect(interrupted.commit?.audioVersion == nil)
    let audioURL = paths(for: fixture.intent, root: fixture.external).audio
    let first = try Data(contentsOf: audioURL)
    queue.shouldFailReplace = nil
    await coordinator.attempt(jobID: fixture.job.id)
    let retried = try #require(queue.values[fixture.job.id])
    #expect(retried.commit?.audioVersion != nil)
    #expect(retried.commit?.markdownVersion != nil)
    #expect(retried.reason == DiaryCommitWait.upload.message)
    #expect(try Data(contentsOf: audioURL) == first)
  }

  @Test func symlinkAtMarkdownNameDoesNotOverwriteAnotherFile() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var intent = fixture.intent
    var job = fixture.job
    guard case .verified(let audio) = await fixture.store.ensureAudio(intent, job: job)
    else {
      Issue.record("Expected audio creation")
      return
    }
    intent.audioVersion = audio
    job.commit = intent
    let target = fixture.root.appending(path: "unrelated.md")
    try Data("keep".utf8).write(to: target)
    let path = paths(for: intent, root: fixture.external).markdown
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)

    #expect(await fixture.store.ensureMarkdown(intent, job: job) == .recoveryRequired)
    #expect(try Data(contentsOf: target) == Data("keep".utf8))
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func missingMarkdownRepairsOnlyWhileAudioVersionMatches() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    guard var pair = await createPair(fixture) else {
      Issue.record("Expected complete pair")
      return
    }
    let paths = paths(for: pair.intent, root: fixture.external)
    try FileManager.default.removeItem(at: paths.markdown)
    let outcome = await fixture.store.ensureMarkdown(pair.intent, job: pair.job)
    guard case .repaired(let replacement) = outcome else {
      Issue.record("Expected version-checked repair")
      return
    }
    #expect(replacement.identity != pair.intent.markdownVersion?.identity)
    pair.intent.markdownVersion = replacement
    pair.job.commit = pair.intent
    guard case .verified = await fixture.store.verifyPair(pair.intent, job: pair.job)
    else {
      Issue.record("Repaired pair did not verify")
      return
    }

    try FileManager.default.removeItem(at: paths.markdown)
    try Data("changed".utf8).write(to: paths.audio)
    #expect(await fixture.store.ensureMarkdown(pair.intent, job: pair.job) == .recoveryRequired)
    #expect(!FileManager.default.fileExists(atPath: paths.markdown.path))
  }

  @Test func independentlyFoundIncompletePairHasTypedSurvivor() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let id = try AssetID(fixture.intent.assetID)
    let created = try SchemaInstant.from(date: fixture.job.startedAt)
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    let markdown = DiaryObservedMarkdown(
      bytes: fixture.markdownBytes,
      version: DiaryFileVersion(
        identity: "markdown-version", digest: digest(fixture.markdownBytes),
        byteCount: Int64(fixture.markdownBytes.count)),
      modifiedAt: Date(timeIntervalSince1970: 20))
    let audio = DiaryObservedAudio(
      version: DiaryFileVersion(
        identity: "audio-version", digest: fixture.intent.audioDigest,
        byteCount: fixture.intent.audioByteCount),
      playable: true, modifiedAt: Date(timeIntervalSince1970: 21))
    let classifier = DiaryExternalPairClassifier()
    let markdownOnly = classifier.classify(
      layout: layout, assetID: id, markdown: markdown, audio: nil)
    guard case .incomplete(let missingAudio) = markdownOnly else {
      Issue.record("Expected Markdown survivor")
      return
    }
    #expect(missingAudio.missing == .audio)
    #expect(missingAudio.survivingMarkdown?.body.text == "A day")
    let audioOnly = classifier.classify(
      layout: layout, assetID: id, markdown: nil, audio: audio)
    guard case .incomplete(let missingMarkdown) = audioOnly else {
      Issue.record("Expected audio survivor")
      return
    }
    #expect(missingMarkdown.missing == .markdown)
    #expect(missingMarkdown.hasPlayableAudio)
    let both = classifier.classify(
      layout: layout, assetID: id, markdown: markdown, audio: audio)
    guard case .complete(let complete) = both else {
      Issue.record("Expected complete pair")
      return
    }
    #expect(complete.version.markdownIdentity == "markdown-version")
    #expect(complete.modifiedAt.audio == audio.modifiedAt)
    let wrongID = try AssetID.random()
    #expect(
      classifier.classify(layout: layout, assetID: wrongID, markdown: markdown, audio: audio)
        == .blocked("The Markdown needs review."))
  }

  @Test func activeFolderInspectorFindsMarkdownWithoutLocalDraft() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let id = try AssetID(fixture.intent.assetID)
    let created = try SchemaInstant.from(date: fixture.job.startedAt)
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    let day = layout.directoryComponents.reduce(fixture.external) {
      $0.appending(path: $1, directoryHint: .isDirectory)
    }
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try fixture.markdownBytes.write(to: day.appending(path: layout.markdownFilename))
    let inspector = AppleDiaryRecoveryInspector(
      destination: fixture.destination, repository: fixture.repository,
      captures: fixture.captures)

    guard
      case .incomplete(let recovery) = await inspector.inspectActive(
        id: id, createdAt: created)
    else {
      Issue.record("Expected typed incomplete pair")
      return
    }
    #expect(recovery.missing == .audio)
    #expect(recovery.survivingMarkdown?.body.text == "A day")
    #expect(fixture.platform.scopeCount == 0)
  }

  @Test func captureInspectorFindsPartialInOriginalFolderAfterSettingsChange() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let id = try AssetID(fixture.intent.assetID)
    let created = try SchemaInstant.from(date: fixture.job.startedAt)
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    let day = layout.directoryComponents.reduce(fixture.external) {
      $0.appending(path: $1, directoryHint: .isDirectory)
    }
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try fixture.markdownBytes.write(to: day.appending(path: layout.markdownFilename))
    let alternate = fixture.root.appending(path: "OtherPickedFolder")
    try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
    fixture.platform.alternateURL = alternate
    fixture.repository.record = StoredDestinationRecord(
      id: DestinationID.make().rawValue, displayName: "Different active folder",
      bookmark: Data([0x99]), identityArchive: Data([0x44]),
      disclosureAcknowledged: true)
    let inspector = AppleDiaryRecoveryInspector(
      destination: fixture.destination, repository: fixture.repository,
      captures: fixture.captures)

    #expect(await inspector.inspectActive(id: id, createdAt: created) == .absent)

    guard
      case .incomplete(let recovery) = await inspector.inspectCapture(
        reference: fixture.job.destinationReference, id: id, createdAt: created)
    else {
      Issue.record("Expected the original folder's Markdown survivor")
      return
    }
    #expect(recovery.missing == .audio)
    #expect(recovery.survivingVersion.digest == fixture.intent.markdownDigest)
    #expect(fixture.platform.scopeCount == 0)
  }

  // swiftlint:disable:next function_body_length
  @Test func completeConflictVersionsBecomeTwoStableWholePairSnapshots() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let id = try AssetID(fixture.intent.assetID)
    let created = try SchemaInstant.from(date: fixture.job.startedAt)
    let paths = paths(for: fixture.intent, root: fixture.external)
    try FileManager.default.createDirectory(
      at: paths.audio.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
      case .supported(var firstSnippet) = DiarySnippetMarkdownCodec().decode(
        fixture.markdownBytes)
    else { throw QueueStoreFailure.corrupt }
    let firstAudio = Data(repeating: 0x41, count: 512)
    let secondAudio = Data(repeating: 0x42, count: 512)
    firstSnippet.audioSHA256 = digest(firstAudio)
    var secondSnippet = firstSnippet
    secondSnippet.audioSHA256 = digest(secondAudio)
    secondSnippet.body = try DiaryBody("A different day")
    let codec = DiarySnippetMarkdownCodec()
    let firstMarkdown = try codec.encode(firstSnippet)
    let secondMarkdown = try codec.encode(secondSnippet)
    try firstMarkdown.write(to: paths.markdown)
    try firstAudio.write(to: paths.audio)
    let otherMarkdown = fixture.root.appending(path: "other.md")
    let otherAudio = fixture.root.appending(path: "other.m4a")
    try secondMarkdown.write(to: otherMarkdown)
    try secondAudio.write(to: otherAudio)
    // swiftlint:disable trailing_comma
    let versions = PairConflictVersions(
      markdown: [
        DiaryExternalVersion(
          contentsURL: paths.markdown, modifiedAt: Date(timeIntervalSince1970: 10),
          providerKey: "markdown-current"),
        DiaryExternalVersion(
          contentsURL: otherMarkdown, modifiedAt: Date(timeIntervalSince1970: 20),
          providerKey: "markdown-other"),
      ],
      audio: [
        DiaryExternalVersion(
          contentsURL: paths.audio, modifiedAt: Date(timeIntervalSince1970: 11),
          providerKey: "audio-current"),
        DiaryExternalVersion(
          contentsURL: otherAudio, modifiedAt: Date(timeIntervalSince1970: 21),
          providerKey: "audio-other"),
      ])
    // swiftlint:enable trailing_comma
    let snapshots = try FileDiaryConflictSnapshotStore(
      root: fixture.root.appending(path: "Snapshots"),
      protection: PairConflictProtection(),
      audioValidator: PairConflictAudioValidator())
    let inspector = AppleDiaryConflictInspector(
      destination: fixture.destination, captures: fixture.captures,
      snapshots: snapshots, versions: versions)
    guard
      case .candidates(let found) = await inspector.inspectCaptureConflicts(
        reference: fixture.job.destinationReference,
        id: id, createdAt: created)
    else {
      Issue.record("Expected two validated pair snapshots")
      return
    }
    #expect(found.selection == .second)
    #expect(found.first.snippet.body.text == "A day")
    #expect(found.second.snippet.body.text == "A different day")
    #expect(try snapshots.snapshotIDs().count == 2)
    let claim = try DiaryConflictResolutionClaim(job: fixture.job, candidates: found)
    #expect(
      await inspector.validateChoice(
        claim, snapshotID: found.second.id.description, job: fixture.job))
    #expect(
      await inspector.inspectCaptureConflicts(
        reference: fixture.job.destinationReference,
        id: id, createdAt: created) == .candidates(found))
    #expect(try snapshots.snapshotIDs().count == 2)
    let publisher = AppleDiaryConflictPairStore(
      destination: fixture.destination, captures: fixture.captures,
      snapshots: snapshots, versions: versions)
    var publishing = claim
    guard
      case .verified(let publishedAudio) = await publisher.ensureAudio(
        publishing, job: fixture.job)
    else {
      Issue.record("Expected checked audio replacement")
      return
    }
    let resuming = AppleDiaryConflictPairStore(
      destination: fixture.destination, captures: fixture.captures,
      snapshots: snapshots, observer: PairTwoReadObserver(), versions: versions)
    #expect(await resuming.ensureAudio(claim, job: fixture.job) == .verified(publishedAudio))
    publishing.publishedAudio = publishedAudio
    guard
      case .verified(let publishedMarkdown) = await publisher.ensureMarkdown(
        publishing, job: fixture.job)
    else {
      Issue.record("Expected checked Markdown replacement")
      return
    }
    publishing.publishedMarkdown = publishedMarkdown
    guard
      case .verified(let chosenVersion) = await publisher.verifyPair(
        publishing, job: fixture.job)
    else {
      Issue.record("Expected chosen pair verification")
      return
    }
    #expect(try Data(contentsOf: paths.audio) == secondAudio)
    #expect(try Data(contentsOf: paths.markdown) == secondMarkdown)
    #expect(
      await publisher.verifyUnchanged(
        chosenVersion, claim: publishing, job: fixture.job) == .unchanged)
    #expect(
      await publisher.observeUploads(
        chosenVersion, claim: publishing, job: fixture.job)
        == DiaryPairUploadObservation(markdown: nil, audio: nil))
    publishing.pairVerified = true
    #expect(await publisher.removeObsolete(publishing, job: fixture.job) == .waiting)
    let cleaner = PairVersionCleaner()
    let uploadedPublisher = AppleDiaryConflictPairStore(
      destination: fixture.destination, captures: fixture.captures,
      snapshots: snapshots, observer: PairUploadedObserver(),
      versions: versions, cleaner: cleaner)
    #expect(
      await uploadedPublisher.removeObsolete(publishing, job: fixture.job) == .done)
    #expect(cleaner.cleaned == [paths.audio, paths.markdown])
    #expect(try snapshots.snapshotIDs().count == 2)
    try Data("changed".utf8).write(to: paths.markdown)
    #expect(
      await inspector.validateChoice(
        claim, snapshotID: found.second.id.description, job: fixture.job) == false)
    #expect(
      await publisher.verifyUnchanged(
        chosenVersion, claim: publishing, job: fixture.job) == .changed)
  }

  @Test(arguments: [false, true])
  // swiftlint:disable:next function_body_length
  func sharedAudioConflictRequiresUniqueAudioVersion(duplicateAudio: Bool) async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let id = try AssetID(fixture.intent.assetID)
    let created = try SchemaInstant.from(date: fixture.job.startedAt)
    let paths = paths(for: fixture.intent, root: fixture.external)
    try FileManager.default.createDirectory(
      at: paths.audio.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
      case .supported(var snippet) = DiarySnippetMarkdownCodec().decode(fixture.markdownBytes)
    else { throw QueueStoreFailure.corrupt }
    let audio = Data(repeating: 0x41, count: 512)
    snippet.audioSHA256 = digest(audio)
    let firstMarkdown = try DiarySnippetMarkdownCodec().encode(snippet)
    snippet.body = try DiaryBody("A different day")
    let secondMarkdown = try DiarySnippetMarkdownCodec().encode(snippet)
    try audio.write(to: paths.audio)
    try firstMarkdown.write(to: paths.markdown)
    let otherMarkdown = fixture.root.appending(path: "shared-audio.md")
    try secondMarkdown.write(to: otherMarkdown)
    let audioTime = Date(timeIntervalSince1970: 10)
    var audioVersions = [
      DiaryExternalVersion(
        contentsURL: paths.audio, modifiedAt: audioTime, providerKey: "audio-current")
    ]
    if duplicateAudio {
      let otherAudio = fixture.root.appending(path: "duplicate.m4a")
      try audio.write(to: otherAudio)
      audioVersions.append(
        DiaryExternalVersion(
          contentsURL: otherAudio, modifiedAt: audioTime, providerKey: "audio-other"))
    }
    let currentMarkdown = DiaryExternalVersion(
      contentsURL: paths.markdown, modifiedAt: audioTime, providerKey: "markdown-current")
    let otherMarkdownVersion = DiaryExternalVersion(
      contentsURL: otherMarkdown, modifiedAt: Date(timeIntervalSince1970: 20),
      providerKey: "markdown-other")
    var markdownVersions = [currentMarkdown]
    markdownVersions.append(otherMarkdownVersion)
    let versions = PairConflictVersions(markdown: markdownVersions, audio: audioVersions)
    let snapshots = try FileDiaryConflictSnapshotStore(
      root: fixture.root.appending(path: "Snapshots"),
      protection: PairConflictProtection(),
      audioValidator: PairConflictAudioValidator())
    let inspector = AppleDiaryConflictInspector(
      destination: fixture.destination, captures: fixture.captures,
      snapshots: snapshots, versions: versions)
    let result = await inspector.inspectCaptureConflicts(
      reference: fixture.job.destinationReference, id: id, createdAt: created)
    if duplicateAudio {
      guard case .blocked = result else {
        Issue.record("Duplicate audio digest matches must remain blocked")
        return
      }
      #expect(try snapshots.snapshotIDs().isEmpty)
      return
    }
    guard case .candidates(let found) = result else {
      Issue.record("Expected two selectable text versions sharing verified audio")
      return
    }
    #expect(found.selection == .userChoice)
    #expect(found.first.version.audioIdentity == found.second.version.audioIdentity)
    #expect(found.first.snippet.body.text == "A day")
    #expect(found.second.snippet.body.text == "A different day")
    #expect(try snapshots.snapshotIDs().count == 2)
    var claim = try DiaryConflictResolutionClaim(job: fixture.job, candidates: found)
    #expect(
      await inspector.validateChoice(
        claim, snapshotID: found.second.id.description, job: fixture.job))
    claim.selectedSnapshotID = found.second.id.description
    let publisher = AppleDiaryConflictPairStore(
      destination: fixture.destination, captures: fixture.captures,
      snapshots: snapshots, versions: versions)
    let originalAudio = try AppleDiaryConflictPairStore.fingerprint(
      paths.audio, maximumBytes: Int64(audio.count))
    #expect(
      await publisher.ensureAudio(claim, job: fixture.job) == .verified(originalAudio))
    #expect(
      try AppleDiaryConflictPairStore.fingerprint(
        paths.audio, maximumBytes: Int64(audio.count)) == originalAudio)
  }

  private func changeProviderMetadata(_ url: URL) throws {
    var before = stat()
    #expect(lstat(url.path, &before) == 0)
    var value: UInt8 = 1
    #expect(setxattr(url.path, "com.narihitosdiary.test-provider", &value, 1, 0, 0) == 0)
    var after = stat()
    #expect(lstat(url.path, &after) == 0)
    #expect(before.st_ino == after.st_ino && before.st_size == after.st_size)
    #expect(before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec)
    #expect(before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec)
    #expect(!DiaryFileIdentity.sameVersion(before, after))
  }

  private func createPair(_ fixture: PairStoreFixture) async -> (
    intent: DiaryCommitRecord, job: QueueJob
  )? {
    var intent = fixture.intent
    var job = fixture.job
    guard case .verified(let audio) = await fixture.store.ensureAudio(intent, job: job)
    else { return nil }
    intent.audioVersion = audio
    job.commit = intent
    guard case .verified(let markdown) = await fixture.store.ensureMarkdown(intent, job: job)
    else { return nil }
    intent.markdownVersion = markdown
    job.commit = intent
    return (intent, job)
  }

  // swiftlint:disable:next function_body_length
  private func makeFixture() throws -> PairStoreFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let external = root.appending(path: "PickedFolder")
    let privateRoot = root.appending(path: "Captures")
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    let captures = CapturePrivateFiles(
      root: privateRoot, protection: NoCaptureProtectionPolicy())
    let record = StoredDestinationRecord(
      id: DestinationID.make().rawValue, displayName: "Diary",
      bookmark: Data([0x33]), identityArchive: Data([0x44]),
      disclosureAcknowledged: true)
    let snapshot = try captures.saveSnapshot(record)
    let audioBytes = Data(repeating: 0x41, count: 512)
    let receipt = QueueReceipt(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 1_762_000_000),
      language: .english, destinationReference: snapshot,
      installationBinding: "installation",
      inspection: CaptureInspection(
        byteCount: 512, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1, codecIdentifier: nil,
        approximateBitRate: 64_000))
    let id = try AssetID.random()
    var job = QueueJob(receipt: receipt, state: .readyToSave)
    job.attemptID = UUID()
    job.draftAssetID = id.description
    let created = try SchemaInstant.from(date: receipt.startedAt)
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    let snippet = DiarySnippetV1(
      id: id, createdAt: created, updatedAt: created, title: "A day",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil,
        osVersion: nil, modelID: nil),
      favorite: false, language: "en-US", audioFilename: layout.audioFilename,
      recordingDurationMilliseconds: 1_000, audioCodec: "aac",
      audioSampleRateHertz: 44_100, audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID(TranscriptionMethodIdentifiers.apple),
        languageHint: "en-US", settingsRevision: 1, modelID: nil, modelVersion: nil,
        runtimeID: "apple-speech-analyzer", conversionID: "test"),
      location: nil, weather: nil, body: try DiaryBody("A day"),
      preservedScalars: [])
    let markdownBytes = try DiarySnippetMarkdownCodec().encode(snippet)
    let draft = VerifiedDiaryDraft(
      snippet: snippet, sourceDigest: digest(audioBytes),
      markdownDigest: digest(markdownBytes),
      markdownByteCount: Int64(markdownBytes.count))
    let intent = try DiaryCommitRecord(job: job, draft: draft)
    job.commit = intent
    let platform = PairTestDestinationPlatform(url: external)
    let repository = PairTestDestinationStore(record)
    let destination = AppleDestinationService(
      repository: repository, platform: platform)
    let store = AppleDiaryPairStore(
      destination: destination, captures: captures,
      payload: PairTestPayload(markdown: markdownBytes, audio: audioBytes))
    return PairStoreFixture(
      root: root, external: external, store: store, platform: platform,
      job: job, intent: intent, markdownBytes: markdownBytes,
      repository: repository, destination: destination, captures: captures,
      draft: draft)
  }

  private func paths(for intent: DiaryCommitRecord, root: URL) -> (
    markdown: URL, audio: URL
  ) {
    let day = intent.directoryComponents.reduce(root) { $0.appending(path: $1) }
    let audio = day.appending(path: intent.assetsDirectoryName)
      .appending(path: intent.audioFilename)
    return (
      markdown: day.appending(path: intent.markdownFilename),
      audio: audio
    )
  }

  private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
