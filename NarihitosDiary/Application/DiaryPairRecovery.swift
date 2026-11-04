import Foundation

/// The adapter supplies only fully validated pair candidates to this policy.
/// A later whole pair must have both resources strictly newer.
struct DiaryPairModificationTimes: Codable, Equatable, Sendable {
  let markdown: Date?
  let audio: Date?
}

enum DiaryConflictSelection: Equatable, Sendable {
  case first
  case second
  case userChoice
}

enum DiaryPairConflictPolicy {
  static func select(
    first: DiaryPairModificationTimes, second: DiaryPairModificationTimes
  ) -> DiaryConflictSelection {
    guard let firstMarkdown = first.markdown, let firstAudio = first.audio,
      let secondMarkdown = second.markdown, let secondAudio = second.audio
    else { return .userChoice }
    if firstMarkdown > secondMarkdown && firstAudio > secondAudio { return .first }
    if secondMarkdown > firstMarkdown && secondAudio > firstAudio { return .second }
    return .userChoice
  }
}

enum DiaryIncompleteComponent: String, Equatable, Sendable {
  case markdown
  case audio
}

/// No provider URL or deletion path crosses into the application layer.
/// The diary catalog can enumerate these records; recovery owns choice and removal presentation.
struct DiaryIncompletePairRecovery: Equatable, Sendable {
  let assetID: String
  let missing: DiaryIncompleteComponent
  let survivingMarkdown: DiarySnippetV1?
  let hasPlayableAudio: Bool
  let survivingVersion: DiaryFileVersion
  let reason: String
}

struct DiaryAmbiguousPairRecovery: Equatable, Sendable {
  let assetID: String
  let first: DiaryPairVersion
  let second: DiaryPairVersion
  let firstTimes: DiaryPairModificationTimes
  let secondTimes: DiaryPairModificationTimes
}

struct DiaryConflictSnapshot: Equatable, Sendable {
  let id: WorkspaceID
  let assetID: String
  let snippet: DiarySnippetV1
  let version: DiaryPairVersion
  let modifiedAt: DiaryPairModificationTimes
  let providerKeys: DiaryProviderVersionKeys?

  init(
    id: WorkspaceID, assetID: String, snippet: DiarySnippetV1,
    version: DiaryPairVersion, modifiedAt: DiaryPairModificationTimes,
    providerKeys: DiaryProviderVersionKeys? = nil
  ) {
    self.id = id
    self.assetID = assetID
    self.snippet = snippet
    self.version = version
    self.modifiedAt = modifiedAt
    self.providerKeys = providerKeys
  }
}

struct DiaryProviderVersionKeys: Codable, Equatable, Sendable {
  let markdown: String
  let audio: String
}

struct DiaryConflictCandidates: Equatable, Sendable {
  let first: DiaryConflictSnapshot
  let second: DiaryConflictSnapshot
  let currentMarkdown: DiaryFileVersion
  let currentAudio: DiaryFileVersion
  let currentProviderKeys: DiaryProviderVersionKeys?
  let selection: DiaryConflictSelection
}

struct DiaryConflictResolutionClaim: Codable, Equatable, Sendable {
  let assetID: String
  let attemptID: UUID
  let generation: Int
  let destinationRevision: Int
  let bodyRevision: Int
  let firstSnapshotID: String
  let secondSnapshotID: String
  let firstVersion: DiaryPairVersion
  let secondVersion: DiaryPairVersion
  let expectedMarkdown: DiaryFileVersion
  let expectedAudio: DiaryFileVersion
  let expectedProviderKeys: DiaryProviderVersionKeys?
  let audioCreationToken: UUID
  let markdownCreationToken: UUID
  var selectedSnapshotID: String?
  var publishedAudio: DiaryFileVersion?
  var publishedMarkdown: DiaryFileVersion?
  var pairVerified: Bool?
  var removalConfirmed: Bool?
  var providerCleanupDone: Bool?

  init(job: QueueJob, candidates: DiaryConflictCandidates) throws {
    guard let attemptID = job.attemptID,
      let assetID = job.draftAssetID,
      candidates.first.assetID == assetID,
      candidates.second.assetID == assetID,
      candidates.first.id != candidates.second.id,
      candidates.first.version != candidates.second.version,
      [candidates.first.version, candidates.second.version].contains(where: {
        $0.markdownIdentity == candidates.currentMarkdown.identity
          && $0.markdownDigest == candidates.currentMarkdown.digest
      }),
      [candidates.first.version, candidates.second.version].contains(where: {
        $0.audioIdentity == candidates.currentAudio.identity
          && $0.audioDigest == candidates.currentAudio.digest
      })
    else { throw QueueStoreFailure.corrupt }
    self.assetID = assetID
    self.attemptID = attemptID
    generation = job.attemptGeneration
    destinationRevision = job.destinationRevision
    bodyRevision = job.bodyRevision
    firstSnapshotID = candidates.first.id.description
    secondSnapshotID = candidates.second.id.description
    firstVersion = candidates.first.version
    secondVersion = candidates.second.version
    expectedMarkdown = candidates.currentMarkdown
    expectedAudio = candidates.currentAudio
    expectedProviderKeys = candidates.currentProviderKeys
    audioCreationToken = UUID()
    markdownCreationToken = UUID()
    publishedAudio = nil
    publishedMarkdown = nil
    pairVerified = nil
    providerCleanupDone = nil
    switch candidates.selection {
    case .first:
      selectedSnapshotID = firstSnapshotID
      removalConfirmed = true
    case .second:
      selectedSnapshotID = secondSnapshotID
      removalConfirmed = true
    case .userChoice:
      selectedSnapshotID = nil
      removalConfirmed = false
    }
  }

  func matches(job: QueueJob) -> Bool {
    job.draftAssetID == assetID && job.attemptID == attemptID
      && job.attemptGeneration == generation
      && job.destinationRevision == destinationRevision
      && job.bodyRevision == bodyRevision
  }

  var selectedVersion: DiaryPairVersion? {
    if selectedSnapshotID == firstSnapshotID { return firstVersion }
    if selectedSnapshotID == secondSnapshotID { return secondVersion }
    return nil
  }
}

enum DiaryConflictCandidateStatus: Equatable, Sendable {
  case none
  case candidates(DiaryConflictCandidates)
  case blocked(String)
}

enum DiaryConflictCleanupResult: Equatable, Sendable {
  case done
  case waiting
  case recoveryRequired
}

@MainActor
protocol DiaryConflictInspectionPort: AnyObject {
  func inspectCaptureConflicts(
    reference: UUID, id: AssetID, createdAt: SchemaInstant
  ) async -> DiaryConflictCandidateStatus
  func validateChoice(
    _ claim: DiaryConflictResolutionClaim, snapshotID: String, job: QueueJob
  ) async -> Bool
}

@MainActor
protocol DiaryConflictPairStorePort: AnyObject {
  func ensureAudio(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryFileResult
  func ensureMarkdown(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryFileResult
  func verifyPair(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryPairResult
  func observeUploads(
    _ version: DiaryPairVersion, claim: DiaryConflictResolutionClaim,
    job: QueueJob
  ) async -> DiaryPairUploadObservation
  func verifyUnchanged(
    _ version: DiaryPairVersion, claim: DiaryConflictResolutionClaim,
    job: QueueJob
  ) async -> DiaryFinalPairCheck
  func removeObsolete(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryConflictCleanupResult
}

struct DiaryObservedMarkdown: Equatable, Sendable {
  let bytes: Data
  let version: DiaryFileVersion
  let modifiedAt: Date?
}

struct DiaryObservedAudio: Equatable, Sendable {
  let version: DiaryFileVersion
  let playable: Bool
  let modifiedAt: Date?
}

struct DiaryVerifiedExternalPair: Equatable, Sendable {
  let snippet: DiarySnippetV1
  let version: DiaryPairVersion
  let modifiedAt: DiaryPairModificationTimes
}

enum DiaryExternalPairStatus: Equatable, Sendable {
  case absent
  case complete(DiaryVerifiedExternalPair)
  case incomplete(DiaryIncompletePairRecovery)
  case blocked(String)
}

@MainActor
protocol DiaryRecoveryInspectionPort: AnyObject {
  func inspectActive(id: AssetID, createdAt: SchemaInstant) async -> DiaryExternalPairStatus
  func inspectCapture(
    reference: UUID, id: AssetID, createdAt: SchemaInstant
  ) async -> DiaryExternalPairStatus
}
