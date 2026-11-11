import CryptoKit
import Foundation
import Testing

@testable import NarihitosDiary

private struct SnapshotTestProtection: DraftFileProtectionPolicy {
  func applyAndVerify(to _: URL) throws {}
  func verify(_: URL) throws {}
}

private struct SnapshotTestAudio: ConflictSnapshotAudioValidator {
  func isPlayable(_: Data) -> Bool { true }
}

private struct SnapshotFixture {
  let pair: DiaryVerifiedExternalPair
  let markdown: Data
  let audio: Data
}

@MainActor
struct DiaryConflictSnapshotTests {
  @Test func exactPrivatePairReopensAndTamperingBlocksRemoval() throws {
    let root = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try FileDiaryConflictSnapshotStore(
      root: root, protection: SnapshotTestProtection(),
      audioValidator: SnapshotTestAudio())
    let fixture = try makePair()
    let snapshot = try store.capture(
      fixture.pair, markdown: fixture.markdown, audio: fixture.audio)

    #expect(snapshot.assetID == fixture.pair.snippet.id.description)
    #expect(try store.read(id: snapshot.id) == snapshot)
    #expect(try store.audioBytes(id: snapshot.id) == fixture.audio)
    #expect(try store.snapshotIDs() == [snapshot.id])
    let file = root.appending(path: snapshot.id.description)
      .appending(path: PrivateArtifactRole.markdownDraft.ownedFilename)
    let backup = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(backup.isExcludedFromBackup == true)
    try Data("changed".utf8).write(to: file)
    #expect(throws: QueueStoreFailure.self) { _ = try store.read(id: snapshot.id) }
    #expect(throws: QueueStoreFailure.self) {
      try store.removeVerified(id: snapshot.id, expected: snapshot)
    }
    #expect(FileManager.default.fileExists(atPath: file.path))
  }

  @Test func cleanupRemovesOnlyExpectedSnapshotAndRetryIsIdempotent() throws {
    let root = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try FileDiaryConflictSnapshotStore(
      root: root, protection: SnapshotTestProtection(),
      audioValidator: SnapshotTestAudio())
    let fixture = try makePair()
    let snapshot = try store.capture(
      fixture.pair, markdown: fixture.markdown, audio: fixture.audio)
    let wrong = DiaryPairVersion(
      markdownIdentity: "other", audioIdentity: snapshot.version.audioIdentity,
      markdownDigest: snapshot.version.markdownDigest,
      audioDigest: snapshot.version.audioDigest)
    #expect(throws: QueueStoreFailure.self) {
      try store.removeVerifiedIfPresent(
        id: snapshot.id, assetID: snapshot.assetID, version: wrong)
    }
    #expect(try store.read(id: snapshot.id) == snapshot)
    try store.removeVerifiedIfPresent(
      id: snapshot.id, assetID: snapshot.assetID, version: snapshot.version)
    try store.removeVerifiedIfPresent(
      id: snapshot.id, assetID: snapshot.assetID, version: snapshot.version)
    #expect(try store.snapshotIDs().isEmpty)
  }

  @Test func pendingRemovalCleansOwnedConflictCopiesAndPreservesOtherSnapshots() throws {
    let root = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try FileDiaryConflictSnapshotStore(
      root: root.appending(path: "Snapshots"), protection: SnapshotTestProtection(),
      audioValidator: SnapshotTestAudio())
    let fixture = try makePair()
    let first = try store.capture(
      fixture.pair, markdown: fixture.markdown, audio: fixture.audio)
    let otherPair = DiaryVerifiedExternalPair(
      snippet: fixture.pair.snippet,
      version: DiaryPairVersion(
        markdownIdentity: "other-markdown", audioIdentity: fixture.pair.version.audioIdentity,
        markdownDigest: fixture.pair.version.markdownDigest,
        audioDigest: fixture.pair.version.audioDigest),
      modifiedAt: fixture.pair.modifiedAt)
    let second = try store.capture(
      otherPair, markdown: fixture.markdown, audio: fixture.audio)
    let unrelated = try store.capture(
      fixture.pair, markdown: fixture.markdown, audio: fixture.audio)
    let receipt = QueueReceipt(
      id: try WorkspaceID.random(), startedAt: Date(), language: .english,
      destinationReference: UUID(), installationBinding: "test",
      inspection: CaptureInspection(
        byteCount: 1_024, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1, codecIdentifier: nil,
        approximateBitRate: 64_000))
    var job = QueueJob(receipt: receipt, state: .readyToSave)
    job.attemptID = UUID()
    job.draftAssetID = fixture.pair.snippet.id.description
    job.conflictResolution = try DiaryConflictResolutionClaim(
      job: job,
      candidates: DiaryConflictCandidates(
        first: first, second: second,
        currentMarkdown: DiaryFileVersion(
          identity: first.version.markdownIdentity, digest: first.version.markdownDigest,
          byteCount: Int64(fixture.markdown.count)),
        currentAudio: DiaryFileVersion(
          identity: first.version.audioIdentity, digest: first.version.audioDigest,
          byteCount: Int64(fixture.audio.count)),
        currentProviderKeys: nil, selection: .userChoice))
    job.state = .removing
    job.attemptGeneration += 1
    let files = CapturePrivateFiles(root: root.appending(path: "Captures"))
    let receipts = CaptureQueueReceiptSource(files: files, snapshots: store)
    // Simulate interruption after the first copy was removed.
    try store.removeVerified(id: first.id, expected: first)
    try receipts.removePrivateCapture(job: job)
    try receipts.removePrivateCapture(job: job)
    #expect(try store.snapshotIDs() == [unrelated.id])
    #expect(try store.read(id: unrelated.id) == unrelated)
  }

  private func makePair() throws -> SnapshotFixture {
    let id = try AssetID.random()
    let created = try SchemaInstant("2026-11-02T12:00:00Z")
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    let initial = DiarySnippetV1(
      id: id, createdAt: created, updatedAt: created, title: "A day",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil,
        osVersion: nil, modelID: nil),
      favorite: false, language: "en-US", audioFilename: layout.audioFilename,
      recordingDurationMilliseconds: 1_000, audioCodec: "aac",
      audioSampleRateHertz: 44_100, audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID(TranscriptionMethodIdentifiers.apple),
        languageHint: "en-US", settingsRevision: 1, modelID: nil,
        modelVersion: nil, runtimeID: "apple-speech-analyzer", conversionID: "test"),
      location: nil, weather: nil, body: try DiaryBody("A day"),
      preservedScalars: [])
    let markdown = try DiarySnippetMarkdownCodec().encode(initial)
    guard case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(markdown) else {
      throw QueueStoreFailure.corrupt
    }
    let audio = Data(repeating: 0x41, count: 1_024)
    let pair = DiaryVerifiedExternalPair(
      snippet: snippet,
      version: DiaryPairVersion(
        markdownIdentity: "markdown-v1", audioIdentity: "audio-v1",
        markdownDigest: digest(markdown), audioDigest: digest(audio)),
      modifiedAt: DiaryPairModificationTimes(
        markdown: Date(timeIntervalSince1970: 10),
        audio: Date(timeIntervalSince1970: 11)))
    return SnapshotFixture(pair: pair, markdown: markdown, audio: audio)
  }

  private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
