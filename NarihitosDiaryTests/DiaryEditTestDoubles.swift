import Foundation

@testable import NarihitosDiary

// swift-format places braces after multiline result types.
// swiftlint:disable opening_brace

enum DiaryEditFixture {
  static func snippet(body: String = "Original diary.") throws -> DiarySnippetV1 {
    let id = try AssetID("123e4567-e89b-42d3-a456-426614174000")
    let instant = try SchemaInstant("2026-11-01T12:34:56Z")
    return DiarySnippetV1(
      id: id, createdAt: instant, updatedAt: instant, title: "Original diary",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("apple-ai"), promptRevision: "title-v1",
        osVersion: "27.0.1", modelID: "synthetic-title-model"),
      favorite: false, language: "en-US", audioFilename: "\(id).m4a",
      recordingDurationMilliseconds: 1_000, audioCodec: "aac", audioSampleRateHertz: 44_100,
      audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID("ndm.transcription.cohere"), languageHint: "en-US",
        settingsRevision: 2, modelID: "cohere", modelVersion: "pinned-q5",
        runtimeID: "transcribe.cpp", conversionID: "pcm16"),
      location: nil, weather: nil, body: try DiaryBody(body),
      preservedScalars: [
        PreservedScalar(key: "custom_value", rawValue: "\"kept\"", sourceOrder: 30)
      ])
  }

  static let version = DiaryPairVersion(
    markdownIdentity: "markdown-version", audioIdentity: "audio-version",
    markdownDigest: String(repeating: "a", count: 64),
    audioDigest: String(repeating: "b", count: 64))

  static func session(key: String = "resource") throws -> DiaryEditSession {
    DiaryEditSession(
      id: UUID(), resourceKey: key, bindingID: UUID(), sourceVersion: version,
      snippet: try snippet())
  }
}

@MainActor
final class EditTitleModel: DiaryTitleModelPort {
  var isAvailable = true
  var modelIdentifier: String? { "synthetic-title-model" }
  var calls = 0
  var hold = false
  var continuation: CheckedContinuation<TitleModelReply, Never>?

  func chunks(for text: String, maximumTokens: Int, maximumChunks: Int) async throws -> [String]? {
    [text]
  }

  func summarize(_ text: String, language: String, maximumOutputTokens: Int) async throws
    -> TitleModelReply
  {
    calls += 1
    if hold { return await withCheckedContinuation { continuation = $0 } }
    return TitleModelReply(text: "A peaceful afternoon", outputTokens: 5)
  }
}

@MainActor
struct EditLanguageDetector: DiaryTitleLanguageDetector {
  func assess(_ text: String) -> TitleLanguageAssessment? {
    TitleLanguageAssessment(language: "en", confidence: 1)
  }
}

@MainActor
final class MemoryDiaryEditStore: DiaryEditStorePort {
  let destinationID = DestinationID.make().rawValue
  var records: [UUID: DiaryEditRecord] = [:]
  var candidates: [UUID: DiarySnippetV1] = [:]
  var submissions: [UUID: DiaryEditSubmission] = [:]
  var publication = DiaryEditPublication.waiting(.unavailable)
  var publishCount = 0
  var cleanupCount = 0
  var acceptCount = 0
  var failAcceptance = false
  var failLookup = false
  var failAfterAcceptance = false
  var failLookupAfterAcceptance = false
  var failCheckpoint = false
  var failCleanup = false
  var retireBeforeCleanupFailure = false
  var retiredRecords: Set<UUID> = []
  var checkpointsAfterRetirement = 0
  var holdAcceptance = false
  var acceptanceContinuation: CheckedContinuation<Void, Never>?
  var uploadedMarkdown = false
  var uploadedAudio = false
  var unchanged = true
  var sessionsInvalidated = 0
  var isolatedCount = 0

  func open(_ handle: CatalogItemHandle) async throws -> DiaryEditSession {
    try DiaryEditFixture.session()
  }

  func accepted(
    _ submission: DiaryEditSubmission, session: DiaryEditSession
  ) async throws -> DiaryEditRecord? {
    if failLookup { throw DiaryEditIssue.localData }
    if let existing = submissions[submission.id], existing != submission {
      throw DiaryEditIssue.submissionMismatch
    }
    return records[submission.id]
  }

  func accept(
    _ submission: DiaryEditSubmission, session: DiaryEditSession, candidate: DiarySnippetV1
  ) async throws -> DiaryEditAcceptance {
    acceptCount += 1
    if holdAcceptance { await withCheckedContinuation { acceptanceContinuation = $0 } }
    if failAcceptance { throw DiaryEditIssue.storage }
    if candidate == session.snippet { return .unchanged }
    let record = DiaryEditRecord(
      schema: 1, id: submission.id, installationBinding: "installation",
      resourceKey: session.resourceKey,
      bindingID: session.bindingID, sourceVersion: session.sourceVersion,
      regeneratesTitle: { if case .body = submission.change { true } else { false } }(),
      destinationID: destinationID, assetID: candidate.id.description,
      stage: .accepted, candidateDigest: "candidate", candidateByteCount: 1,
      publishedVersion: nil, markdownUploaded: false, audioUploaded: false, issue: nil)
    records[record.id] = record
    candidates[record.id] = candidate
    submissions[record.id] = submission
    if failLookupAfterAcceptance { failLookup = true }
    if failAfterAcceptance { throw DiaryEditIssue.storage }
    return .accepted(record)
  }

  func inventory(after cursor: String?) async throws -> DiaryEditInventory {
    DiaryEditInventory(
      records: Array(records.values), continuation: nil, isolatedCount: isolatedCount)
  }

  func candidate(for record: DiaryEditRecord) async throws -> DiarySnippetV1 {
    guard records[record.id] == record else { throw DiaryEditIssue.changed }
    guard let value = candidates[record.id] else { throw DiaryEditIssue.invalidCandidate }
    return value
  }

  func finalize(_ record: DiaryEditRecord, candidate: DiarySnippetV1) async throws
    -> DiaryEditRecord
  {
    _ = try DiarySnippetMarkdownCodec().encode(candidate)
    var ready = record
    ready.stage = .ready
    records[record.id] = ready
    candidates[record.id] = candidate
    return ready
  }

  func checkpoint(_ record: DiaryEditRecord) async throws {
    if retiredRecords.contains(record.id) {
      checkpointsAfterRetirement += 1
      throw DiaryEditIssue.changed
    }
    if failCheckpoint { throw DiaryEditIssue.storage }
    records[record.id] = record
  }

  func publish(_ record: DiaryEditRecord) async -> DiaryEditPublication {
    publishCount += 1
    return publication
  }

  func uploads(for record: DiaryEditRecord) async throws -> DiaryPairUploadObservation {
    guard records[record.id] == record else { throw DiaryEditIssue.changed }
    let version = record.publishedVersion ?? DiaryEditFixture.version
    return DiaryPairUploadObservation(
      markdown: uploadedMarkdown
        ? DiaryFileUploadProof(identity: version.markdownIdentity, digest: version.markdownDigest)
        : nil,
      audio: uploadedAudio
        ? DiaryFileUploadProof(identity: version.audioIdentity, digest: version.audioDigest) : nil)
  }

  func verifyUnchanged(_ record: DiaryEditRecord) async throws -> Bool {
    guard records[record.id] == record else { throw DiaryEditIssue.changed }
    return unchanged
  }

  func cleanup(_ record: DiaryEditRecord) async throws {
    cleanupCount += 1
    if failCleanup && retireBeforeCleanupFailure {
      records[record.id] = nil
      retiredRecords.insert(record.id)
      throw DiaryEditIssue.changed
    }
    if failCleanup { throw DiaryEditIssue.storage }
    records[record.id] = nil
    candidates[record.id] = nil
  }

  func invalidateSessions() { sessionsInvalidated += 1 }
}

// swiftlint:enable opening_brace
