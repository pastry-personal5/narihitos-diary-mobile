import Foundation

enum DiaryDraftInspection: Equatable {
  case verified
  case missing
  case invalid
  case protectedDataUnavailable
}

struct VerifiedDiaryDraft: Equatable, Sendable {
  let snippet: DiarySnippetV1
  let sourceDigest: String
  let markdownDigest: String
}

@MainActor
protocol DiaryDraftStore: AnyObject {
  func publish(_ snippet: DiarySnippetV1, candidate: TranscriptionPayload, job: QueueJob) throws
  func inspect(job: QueueJob) throws -> DiaryDraftInspection
  func readVerified(job: QueueJob) throws -> VerifiedDiaryDraft
}
