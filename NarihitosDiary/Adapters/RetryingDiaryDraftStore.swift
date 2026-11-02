import Foundation
import UIKit

/// A locked launch may make the private workspace temporarily unreadable.
/// Resolve it again after protected data becomes available without dropping the
/// queue's draft port for the rest of the process lifetime.
@MainActor
final class RetryingDiaryDraftStore: DiaryDraftStore {
  private let root: URL
  private let audio: any CaptureAudioFingerprintSource
  private var store: FileDiaryDraftStore?

  init(root: URL, audio: any CaptureAudioFingerprintSource) {
    self.root = root
    self.audio = audio
  }

  func publish(_ snippet: DiarySnippetV1, candidate: TranscriptionPayload, job: QueueJob) throws {
    try resolved().publish(snippet, candidate: candidate, job: job)
  }

  func inspect(job: QueueJob) throws -> DiaryDraftInspection {
    guard UIApplication.shared.isProtectedDataAvailable else {
      return .protectedDataUnavailable
    }
    return try resolved().inspect(job: job)
  }

  func readVerified(job: QueueJob) throws -> VerifiedDiaryDraft {
    try resolved().readVerified(job: job)
  }

  private func resolved() throws -> FileDiaryDraftStore {
    guard UIApplication.shared.isProtectedDataAvailable else {
      throw AudioFingerprintFailure.protectedDataUnavailable
    }
    if let store { return store }
    do {
      let created = try FileDiaryDraftStore(root: root, audio: audio)
      store = created
      return created
    } catch {
      throw QueueStoreFailure.unavailable
    }
  }
}
