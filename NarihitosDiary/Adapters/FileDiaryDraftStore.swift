import CryptoKit
import Foundation
import UIKit

private struct DraftBindingRecord: Codable, Equatable {
  let schema: Int
  let jobID: String
  let startedAt: Date
  let language: CaptureLanguage
  let destinationReference: UUID
  let attemptID: UUID
  let generation: Int
  let installationBinding: String
  let assetID: String
  let sourceDigest: String
  let markdownDigest: String
  let methodID: String
  let settings: [String: String]
  let modelIdentity: String?
  let conversionIdentity: String?
  let audioByteCount: Int64
  let audioDuration: TimeInterval
  let destinationRevision: Int
  let bodyRevision: Int

  init(job: QueueJob, sourceDigest: String, markdownDigest: String) throws {
    guard let attemptID = job.attemptID,
      let installationBinding = job.installationBinding,
      let assetID = job.draftAssetID, let methodID = job.selectedMethodID,
      let settings = job.effectiveSettings, job.state == .resultReady
    else { throw QueueStoreFailure.corrupt }
    schema = 1
    jobID = job.id
    startedAt = job.startedAt
    language = job.language
    destinationReference = job.destinationReference
    self.attemptID = attemptID
    generation = job.attemptGeneration
    self.installationBinding = installationBinding
    self.assetID = assetID
    self.sourceDigest = sourceDigest
    self.markdownDigest = markdownDigest
    self.methodID = methodID
    self.settings = settings
    modelIdentity = job.modelIdentity
    conversionIdentity = job.conversionIdentity
    audioByteCount = job.audioByteCount
    audioDuration = job.audioDuration
    destinationRevision = job.destinationRevision
    bodyRevision = job.bodyRevision
  }

  func matches(_ job: QueueJob) -> Bool {
    schema == 1 && jobID == job.id
      && startedAt == job.startedAt && language == job.language
      && destinationReference == job.destinationReference
      && attemptID == job.attemptID
      && generation == job.attemptGeneration
      && installationBinding == job.installationBinding
      && assetID == job.draftAssetID && methodID == job.selectedMethodID
      && settings == job.effectiveSettings
      && modelIdentity == job.modelIdentity
      && conversionIdentity == job.conversionIdentity
      && audioByteCount == job.audioByteCount && audioDuration == job.audioDuration
      && destinationRevision == job.destinationRevision
      && bodyRevision == job.bodyRevision
      && (job.state == .resultReady || job.state == .readyToSave)
  }
}

protocol DraftFileProtectionPolicy: FileProtectionPolicy {
  func verify(_ fileURL: URL) throws
}

struct AppleDraftProtectionPolicy: DraftFileProtectionPolicy {
  func applyAndVerify(to fileURL: URL) throws {
    let manager = FileManager.default
    try manager.setAttributes(
      [.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
    try verify(fileURL)
  }

  func verify(_ fileURL: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    guard attributes[.protectionKey] as? FileProtectionType == .complete else {
      throw PrivateWorkspaceFailureCode.protectionPolicyFailed
    }
  }
}

/// The Markdown and small binding record are confined to the M9 workspace.
/// A draft is usable only after both are reopened and the audio digest matches.
@MainActor
final class FileDiaryDraftStore: DiaryDraftStore {
  private let workspace: any PrivateWorkspacePort
  private let root: URL
  private let audio: any CaptureAudioFingerprintSource
  private let codec = DiarySnippetMarkdownCodec()
  private let protectedDataAvailable: () -> Bool
  private let protection: any DraftFileProtectionPolicy

  init(
    root: URL, audio: any CaptureAudioFingerprintSource,
    protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    workspaceOverride: (any PrivateWorkspacePort)? = nil,
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
  ) throws {
    self.root = root
    self.audio = audio
    self.protection = protection
    self.protectedDataAvailable = protectedDataAvailable
    workspace =
      try workspaceOverride
      ?? LocalPrivateWorkspace(root: root, protectionPolicy: protection)
  }

  func publish(_ snippet: DiarySnippetV1, candidate: TranscriptionPayload, job: QueueJob) throws {
    guard protectedDataAvailable() else {
      throw AudioFingerprintFailure.protectedDataUnavailable
    }
    guard job.draftAssetID == snippet.id.description,
      snippet.body.text == candidate.text,
      snippet.transcription.methodID.description == job.selectedMethodID,
      snippet.language == job.language.rawValue,
      snippet.transcription.languageHint == job.language.rawValue,
      snippet.createdAt == (try SchemaInstant.from(date: job.startedAt)),
      snippet.audioSHA256 == nil || snippet.audioSHA256 == candidate.sourceDigest,
      Self.validDigest(candidate.sourceDigest)
    else { throw QueueStoreFailure.corrupt }
    guard candidate.sourceDigest == (try audio.fingerprint(for: job)) else {
      throw TranscriptionCandidateFailure.invalidSource
    }
    var boundSnippet = snippet
    boundSnippet.audioSHA256 = candidate.sourceDigest
    let markdown = try codec.encode(boundSnippet)
    let record = try DraftBindingRecord(
      job: job, sourceDigest: candidate.sourceDigest,
      markdownDigest: Self.digest(markdown))
    let binding = try JSONEncoder().encode(record)
    guard binding.count <= 64 * 1_024 else { throw QueueStoreFailure.corrupt }
    let id = try WorkspaceID(job.id)
    let handle = try workspace.reopen(id: id)
    let draft = try workspace.artifact(.markdownDraft, in: handle)
    let identity = try workspace.artifact(.draftBinding, in: handle)
    try workspace.replace(draft, with: markdown)
    try workspace.replace(identity, with: binding)
    guard try readVerified(job: job).snippet == boundSnippet else {
      throw PrivateWorkspaceFailureCode.verificationFailed
    }
  }

  func inspect(job: QueueJob) throws -> DiaryDraftInspection {
    guard protectedDataAvailable() else { return .protectedDataUnavailable }
    do {
      _ = try readVerified(job: job)
      return .verified
    } catch PrivateWorkspaceFailureCode.resourceMissing {
      return .missing
    } catch PrivateWorkspaceFailureCode.storageUnavailable {
      throw QueueStoreFailure.unavailable
    } catch QueueStoreFailure.unavailable {
      throw QueueStoreFailure.unavailable
    } catch AudioFingerprintFailure.protectedDataUnavailable {
      return .protectedDataUnavailable
    } catch {
      return protectedDataAvailable() ? .invalid : .protectedDataUnavailable
    }
  }

  func readVerified(job: QueueJob) throws -> VerifiedDiaryDraft {
    guard protectedDataAvailable() else {
      throw AudioFingerprintFailure.protectedDataUnavailable
    }
    let id = try WorkspaceID(job.id)
    let handle = try workspace.reopen(id: id)
    let draft = try workspace.artifact(.markdownDraft, in: handle)
    let identity = try workspace.artifact(.draftBinding, in: handle)
    let markdown = try workspace.read(draft)
    let recordData = try workspace.read(identity)
    guard recordData.count <= 64 * 1_024,
      let record = try? JSONDecoder().decode(DraftBindingRecord.self, from: recordData),
      record.matches(job), Self.validDigest(record.sourceDigest),
      Self.validDigest(record.markdownDigest),
      Self.digest(markdown) == record.markdownDigest,
      try audio.fingerprint(for: job) == record.sourceDigest
    else { throw QueueStoreFailure.corrupt }
    try verifyAttributes(jobID: job.id, role: .markdownDraft)
    try verifyAttributes(jobID: job.id, role: .draftBinding)
    guard case .supported(let snippet) = codec.decode(markdown),
      snippet.id.description == record.assetID,
      snippet.body.text.utf8.count <= DiaryBody.maximumBytes,
      snippet.transcription.methodID.description == record.methodID,
      snippet.createdAt == (try SchemaInstant.from(date: job.startedAt)),
      snippet.language == job.language.rawValue,
      snippet.transcription.languageHint == job.language.rawValue,
      snippet.audioSHA256 == nil || snippet.audioSHA256 == record.sourceDigest
    else { throw QueueStoreFailure.corrupt }
    return VerifiedDiaryDraft(
      snippet: snippet, sourceDigest: record.sourceDigest,
      markdownDigest: record.markdownDigest, markdownByteCount: Int64(markdown.count))
  }

  private func verifyAttributes(jobID: String, role: PrivateArtifactRole) throws {
    let url = root.appending(path: jobID, directoryHint: .isDirectory)
      .appending(path: role.ownedFilename, directoryHint: .notDirectory)
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard values.isExcludedFromBackup == true else {
      throw PrivateWorkspaceFailureCode.backupExclusionFailed
    }
    try protection.verify(url)
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func validDigest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
  }
}
