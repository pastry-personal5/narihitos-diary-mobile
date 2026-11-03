import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

@MainActor
struct PurgeCompletedHistoryTests {
  @Test func folderPurgeAllowsOnlyFullyCompletedQueueHistory() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("icloud/diary.md")
    let job = try completedJob()
    let root = fixture.support.appending(path: "ProcessingQueue")
    let store = FileQueueStore(root: root)
    _ = try store.createIfAbsent(job)
    let service = fixture.service()
    let transaction = try await service.prepare(.activeFolder)
    try service.begin(transaction)
    try await service.perform(transaction) { _ in }
    try service.finish()
    #expect(try PurgeFileTree.isEmpty(fixture.platform.url))
    #expect(try store.jobs() == [job])

    for state in QueueJobState.allPurgeTestStates {
      var unfinished = job
      unfinished.state = state
      try store.replace(unfinished)
      await #expect(throws: PurgeFailure.self) { try await service.prepare(.activeFolder) }
    }
    var uncleaned = job
    uncleaned.commitCleanupDone = false
    var unannounced = job
    unannounced.commitNoticeDelivered = false
    var noCommit = job
    noCommit.commit = nil
    var noVersion = job
    noVersion.commit?.audioVersion = nil
    var mismatchedClaim = job
    mismatchedClaim.destinationRevision += 1
    for invalid in [uncleaned, unannounced, noCommit, noVersion, mismatchedClaim] {
      try store.replace(invalid)
      await #expect(throws: PurgeFailure.self) { try await service.prepare(.activeFolder) }
    }
    try store.replace(job)
    try fixture.write("ProcessingQueue/unrecognized")
    await #expect(throws: PurgeFailure.self) { try await service.prepare(.activeFolder) }
    try FileManager.default.removeItem(at: root.appending(path: "unrecognized"))
    try Data("invalid".utf8).write(to: root.appending(path: "\(job.id).json"))
    await #expect(throws: (any Error).self) { try await service.prepare(.activeFolder) }
    try FileManager.default.removeItem(at: root.appending(path: "\(job.id).json"))
    try fixture.write("outside/\(job.id).json")
    try JSONEncoder().encode(job).write(
      to: fixture.support.appending(path: "outside/\(job.id).json"))
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "\(job.id).json"),
      withDestinationURL: fixture.support.appending(path: "outside/\(job.id).json"))
    await #expect(throws: PurgeFailure.self) { try await service.prepare(.activeFolder) }
  }

  private func completedJob() throws -> QueueJob {
    let id = try AssetID.random()
    let instant = try SchemaInstant.from(date: Date(timeIntervalSince1970: 1_762_000_000))
    let layout = DiarySnippetLayout(id: id, createdAt: instant)
    let receipt = QueueReceipt(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 1_762_000_000),
      language: .english, destinationReference: UUID(), installationBinding: "synthetic",
      inspection: CaptureInspection(byteCount: 512, duration: 1, isMonoAAC: true, isPlayable: true))
    var job = QueueJob(receipt: receipt, state: .readyToSave)
    job.attemptID = UUID()
    job.draftAssetID = id.description
    let snippet = DiarySnippetV1(
      id: id, createdAt: instant, updatedAt: instant, title: "Synthetic",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil,
        osVersion: nil, modelID: nil),
      favorite: false, language: "en-US", audioFilename: layout.audioFilename,
      recordingDurationMilliseconds: 1_000, audioCodec: "aac", audioSampleRateHertz: 44_100,
      audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID(TranscriptionMethodIdentifiers.apple),
        languageHint: "en-US", settingsRevision: 1, modelID: nil, modelVersion: nil,
        runtimeID: "synthetic", conversionID: "synthetic"),
      location: nil, weather: nil, body: try DiaryBody("Synthetic"), preservedScalars: [])
    let draft = VerifiedDiaryDraft(
      snippet: snippet, sourceDigest: String(repeating: "a", count: 64),
      markdownDigest: String(repeating: "b", count: 64), markdownByteCount: 512)
    job.commit = try DiaryCommitRecord(job: job, draft: draft)
    job.commit?.audioVersion = DiaryFileVersion(
      identity: "synthetic-audio", digest: draft.sourceDigest, byteCount: 512)
    job.commit?.markdownVersion = DiaryFileVersion(
      identity: "synthetic-markdown", digest: draft.markdownDigest, byteCount: 512)
    job.state = .saved
    job.commitCleanupDone = true
    job.commitNoticeDelivered = true
    return job
  }

}

extension QueueJobState {
  fileprivate static let allPurgeTestStates: [Self] = [
    .ready, .waiting, .transcribing, .resultReady, .readyToSave,
    .failed, .reviewRequired, .cancelling, .removing,
  ]
}

// swiftlint:enable trailing_comma
