import Foundation

/// A submitted edit has no iCloud modification time. External snapshots retain
/// only observed provider times; neither updated_at nor device time orders them.
struct DiaryEditRecoverySnapshot: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let transactionID: UUID
  let assetID: String
  let version: DiaryPairVersion
  let modifiedAt: DiaryPairModificationTimes
  let sharesSubmittedAudio: Bool
  let hasAdditionalProviderVersions: Bool
}

@MainActor
protocol DiaryEditRecoveryPort: AnyObject {
  func recoverySnapshots(for recordID: UUID) async throws -> [DiaryEditRecoverySnapshot]
  func recoveryCandidate(recordID: UUID, snapshotID: UUID?) async throws -> DiarySnippetV1
}
