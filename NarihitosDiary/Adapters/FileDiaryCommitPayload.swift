import CryptoKit
import Foundation

@MainActor
final class FileDiaryCommitPayload: DiaryCommitPayloadPort {
  private let drafts: any DiaryDraftStore
  private let audioSource: VerifiedCaptureAudioSource
  private let workspace: any PrivateWorkspacePort

  init(root: URL, drafts: any DiaryDraftStore, audioSource: VerifiedCaptureAudioSource) throws {
    self.drafts = drafts
    self.audioSource = audioSource
    workspace = try LocalPrivateWorkspace(
      root: root, protectionPolicy: AppleDraftProtectionPolicy())
  }

  func markdown(job: QueueJob, intent: DiaryCommitRecord) throws -> Data {
    let draft = try drafts.readVerified(job: job)
    guard intent.matches(job: job, draft: draft) else { throw QueueStoreFailure.corrupt }
    let handle = try workspace.reopen(id: WorkspaceID(job.id))
    let artifact = try workspace.artifact(.markdownDraft, in: handle)
    let bytes = try workspace.read(artifact)
    guard Int64(bytes.count) == intent.markdownByteCount,
      Self.digest(bytes) == intent.markdownDigest
    else { throw QueueStoreFailure.corrupt }
    return bytes
  }

  func audio(job: QueueJob, intent: DiaryCommitRecord) throws -> Data {
    let draft = try drafts.readVerified(job: job)
    guard intent.matches(job: job, draft: draft) else { throw QueueStoreFailure.corrupt }
    let lease = try audioSource.open(job: job)
    defer { try? lease.close() }
    guard lease.digest == intent.audioDigest else { throw QueueStoreFailure.corrupt }
    let bytes = try lease.readBytes(maximumBytes: CapturePrivateFiles.maximumAudioBytes)
    guard Int64(bytes.count) == intent.audioByteCount,
      Self.digest(bytes) == intent.audioDigest
    else { throw QueueStoreFailure.corrupt }
    return bytes
  }

  private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
