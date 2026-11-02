import Foundation
import UIKit

@MainActor
final class RetryingDiaryCommitPayload: DiaryCommitPayloadPort {
  private let root: URL
  private let drafts: any DiaryDraftStore
  private let audio: VerifiedCaptureAudioSource
  private var payload: FileDiaryCommitPayload?

  init(root: URL, drafts: any DiaryDraftStore, audio: VerifiedCaptureAudioSource) {
    self.root = root
    self.drafts = drafts
    self.audio = audio
  }

  func markdown(job: QueueJob, intent: DiaryCommitRecord) throws -> Data {
    try resolved().markdown(job: job, intent: intent)
  }

  func audio(job: QueueJob, intent: DiaryCommitRecord) throws -> Data {
    try resolved().audio(job: job, intent: intent)
  }

  private func resolved() throws -> FileDiaryCommitPayload {
    guard UIApplication.shared.isProtectedDataAvailable else {
      throw AudioFingerprintFailure.protectedDataUnavailable
    }
    if let payload { return payload }
    let created = try FileDiaryCommitPayload(
      root: root, drafts: drafts, audioSource: audio)
    payload = created
    return created
  }
}
