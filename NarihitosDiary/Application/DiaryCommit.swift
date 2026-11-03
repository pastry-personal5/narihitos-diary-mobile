import Foundation

// swiftlint:disable file_length

/// Durable ownership claim for one capture-time destination and one exact pair.
/// Provider observations are deliberately excluded: a retry must verify afresh.
struct DiaryCommitRecord: Codable, Equatable, Sendable {
  let schema: Int
  let jobID: String
  let attemptID: UUID
  let generation: Int
  let installationBinding: String
  let destinationReference: UUID
  let destinationRevision: Int
  let bodyRevision: Int
  let assetID: String
  let markdownDigest: String
  let audioDigest: String
  let markdownByteCount: Int64
  let audioByteCount: Int64
  let markdownFilename: String
  let assetsDirectoryName: String
  let audioFilename: String
  let directoryComponents: [String]
  /// Random creation markers allow a retry to recognize a file written after
  /// this intent but before its provider version reached the queue record.
  /// Older records have no marker and retain collision-only recovery.
  let audioCreationToken: UUID?
  let markdownCreationToken: UUID?
  var audioVersion: DiaryFileVersion?
  var markdownVersion: DiaryFileVersion?

  init(job: QueueJob, draft: VerifiedDiaryDraft) throws {
    guard job.state == .readyToSave,
      let attemptID = job.attemptID,
      let binding = job.installationBinding,
      job.draftAssetID == draft.snippet.id.description,
      Self.isDigest(draft.markdownDigest), Self.isDigest(draft.sourceDigest),
      draft.markdownByteCount > 0, draft.markdownByteCount <= 2 * 1_024 * 1_024,
      job.audioByteCount > 0, job.audioByteCount <= 64 * 1_024 * 1_024
    else { throw QueueStoreFailure.corrupt }
    let layout = DiarySnippetLayout(id: draft.snippet.id, createdAt: draft.snippet.createdAt)
    guard layout.validates(audioReference: draft.snippet.audioFilename) else {
      throw QueueStoreFailure.corrupt
    }
    schema = 1
    jobID = job.id
    self.attemptID = attemptID
    generation = job.attemptGeneration
    installationBinding = binding
    destinationReference = job.destinationReference
    destinationRevision = job.destinationRevision
    bodyRevision = job.bodyRevision
    assetID = draft.snippet.id.description
    markdownDigest = draft.markdownDigest
    audioDigest = draft.sourceDigest
    markdownByteCount = draft.markdownByteCount
    audioByteCount = job.audioByteCount
    markdownFilename = layout.markdownFilename
    assetsDirectoryName = layout.assetsDirectoryName
    audioFilename = layout.audioFilename
    directoryComponents = layout.directoryComponents
    audioCreationToken = UUID()
    markdownCreationToken = UUID()
    audioVersion = nil
    markdownVersion = nil
  }

  func matches(job: QueueJob, draft: VerifiedDiaryDraft) -> Bool {
    guard let expected = try? Self(job: job, draft: draft) else { return false }
    return schema == expected.schema && jobID == expected.jobID
      && attemptID == expected.attemptID && generation == expected.generation
      && installationBinding == expected.installationBinding
      && destinationReference == expected.destinationReference
      && destinationRevision == expected.destinationRevision
      && bodyRevision == expected.bodyRevision && assetID == expected.assetID
      && markdownDigest == expected.markdownDigest && audioDigest == expected.audioDigest
      && markdownByteCount == expected.markdownByteCount
      && audioByteCount == expected.audioByteCount
      && markdownFilename == expected.markdownFilename
      && assetsDirectoryName == expected.assetsDirectoryName
      && audioFilename == expected.audioFilename
      && directoryComponents == expected.directoryComponents
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

struct DiaryFileVersion: Codable, Equatable, Sendable {
  let identity: String
  let digest: String
  let byteCount: Int64
}

struct DiaryPairVersion: Codable, Equatable, Sendable {
  let markdownIdentity: String
  let audioIdentity: String
  let markdownDigest: String
  let audioDigest: String
}

enum DiaryCommitWait: Equatable, Sendable {
  case destination
  case upload
  case localData

  var message: String {
    switch self {
    case .destination: "Waiting for access to the recording’s iCloud folder."
    case .upload: "Waiting for iCloud upload verification."
    case .localData: "Recording is waiting for protected local data."
    }
  }
}

enum DiaryPairResult: Equatable, Sendable {
  case verified(DiaryPairVersion)
  case waiting(DiaryCommitWait)
  case recoveryRequired
}

enum DiaryFileResult: Equatable, Sendable {
  case verified(DiaryFileVersion)
  case repaired(DiaryFileVersion)
  case waiting(DiaryCommitWait)
  case recoveryRequired
}

struct DiaryFileUploadProof: Equatable, Sendable {
  let identity: String
  let digest: String
}

struct DiaryPairUploadObservation: Equatable, Sendable {
  let markdown: DiaryFileUploadProof?
  let audio: DiaryFileUploadProof?

  func proves(_ version: DiaryPairVersion) -> Bool {
    markdown
      == DiaryFileUploadProof(
        identity: version.markdownIdentity, digest: version.markdownDigest)
      && audio
        == DiaryFileUploadProof(
          identity: version.audioIdentity, digest: version.audioDigest)
  }
}

enum DiaryFinalPairCheck: Equatable, Sendable {
  case unchanged
  case waiting
  case changed
}

/// The adapter owns security scopes, coordination and exact resource checks.
/// It must return only after coordinated work has relinquished its resources.
@MainActor
protocol DiaryPairStorePort: AnyObject {
  func ensureAudio(_ intent: DiaryCommitRecord, job: QueueJob) async -> DiaryFileResult
  func ensureMarkdown(_ intent: DiaryCommitRecord, job: QueueJob) async -> DiaryFileResult
  func verifyPair(_ intent: DiaryCommitRecord, job: QueueJob) async -> DiaryPairResult
  func observeUploads(
    _ version: DiaryPairVersion, intent: DiaryCommitRecord
  ) async -> DiaryPairUploadObservation
  func verifyUnchanged(
    _ version: DiaryPairVersion, intent: DiaryCommitRecord
  ) async -> DiaryFinalPairCheck
}

@MainActor
protocol DiaryCommitCleanupPort: AnyObject {
  func removeOwnedStaging(job: QueueJob) throws
}

@MainActor
protocol DiaryCommitPayloadPort: AnyObject {
  func markdown(job: QueueJob, intent: DiaryCommitRecord) throws -> Data
  func audio(job: QueueJob, intent: DiaryCommitRecord) throws -> Data
}

/// One job claim is held throughout an active attempt. Waiting attempts settle
/// before returning, leaving other ready jobs free to advance.
@MainActor
final class DiaryCommitCoordinator: QueueSaveWork {
  private let queue: any QueueStorePort
  private let drafts: any DiaryDraftStore
  private let pairs: any DiaryPairStorePort
  private let cleanup: any DiaryCommitCleanupPort
  private let conflicts: (any DiaryConflictInspectionPort)?
  private let conflictPairs: (any DiaryConflictPairStorePort)?
  private var activeJobIDs: Set<String> = []
  var hasActiveWork: Bool { !activeJobIDs.isEmpty }
  private var maintenanceSuspended = false
  func suspendForMaintenance() { maintenanceSuspended = true }
  func endMaintenance() { maintenanceSuspended = false }
  var onChange: (@MainActor () -> Void)?
  var onSettled: (@MainActor (String) -> Void)?
  var onSaved: (@MainActor (QueueJob) -> Void)?

  init(
    queue: any QueueStorePort, drafts: any DiaryDraftStore,
    pairs: any DiaryPairStorePort, cleanup: any DiaryCommitCleanupPort,
    conflicts: (any DiaryConflictInspectionPort)? = nil,
    conflictPairs: (any DiaryConflictPairStorePort)? = nil
  ) {
    self.queue = queue
    self.drafts = drafts
    self.pairs = pairs
    self.cleanup = cleanup
    self.conflicts = conflicts
    self.conflictPairs = conflictPairs
  }

  func attempt(jobID: String) async {
    guard !maintenanceSuspended, activeJobIDs.insert(jobID).inserted else { return }
    defer {
      activeJobIDs.remove(jobID)
      onSettled?(jobID)
    }
    do {
      guard var job = try queue.jobs().first(where: { $0.id == jobID }),
        job.state == .readyToSave
      else { return }
      let draft = try drafts.readVerified(job: job)
      let fresh = try DiaryCommitRecord(job: job, draft: draft)
      guard job.commit?.matches(job: job, draft: draft) != false else {
        try setRecovery(job)
        return
      }
      let intent = job.commit ?? fresh
      if job.commit == nil {
        job.commit = intent
        try queue.replace(job)
        onChange?()
      }
      if let resolution = job.conflictResolution {
        try await resolveConflict(resolution, expected: job)
        return
      }
      guard let withAudio = await ensureAudio(intent, expected: job),
        let withMarkdown = await ensureMarkdown(withAudio),
        let finalIntent = withMarkdown.commit
      else { return }
      switch await pairs.verifyPair(finalIntent, job: withMarkdown) {
      case .waiting(let reason):
        try setWaiting(finalIntent, expected: withMarkdown, reason: reason.message)
      case .recoveryRequired:
        try await recordConflict(withMarkdown)
      case .verified(let version):
        try await finishVerified(version, intent: finalIntent, expected: withMarkdown)
      }
    } catch {
      recordPreflightFailure(jobID: jobID, error: error)
    }
  }

  private func recordPreflightFailure(jobID: String, error: Error) {
    guard var job = try? queue.jobs().first(where: { $0.id == jobID }),
      job.state == .readyToSave
    else { return }
    switch error {
    case AudioFingerprintFailure.protectedDataUnavailable,
      QueueStoreFailure.unavailable,
      PrivateWorkspaceFailureCode.storageUnavailable:
      job.reason = DiaryCommitWait.localData.message
    default:
      job.reason = "This diary draft needs review."
    }
    try? queue.replace(job)
    onChange?()
  }

  func isWorking(jobID: String) -> Bool { activeJobIDs.contains(jobID) }

  private func ensureAudio(
    _ intent: DiaryCommitRecord, expected: QueueJob
  ) async -> QueueJob? {
    guard (try? current(intent, expected: expected)) != nil else { return nil }
    let result = await pairs.ensureAudio(intent, job: expected)
    if case .recoveryRequired = result {
      try? await recordConflict(expected)
      return nil
    }
    return persistFileResult(
      result, intent: intent, expected: expected, audio: true)
  }

  private func ensureMarkdown(_ expected: QueueJob) async -> QueueJob? {
    guard let intent = expected.commit,
      (try? current(intent, expected: expected)) != nil
    else { return nil }
    let result = await pairs.ensureMarkdown(intent, job: expected)
    if case .recoveryRequired = result {
      try? await recordConflict(expected)
      return nil
    }
    return persistFileResult(
      result, intent: intent, expected: expected, audio: false)
  }

  private func persistFileResult(
    _ result: DiaryFileResult, intent: DiaryCommitRecord,
    expected: QueueJob, audio: Bool
  ) -> QueueJob? {
    do {
      guard var job = try current(intent, expected: expected) else { return nil }
      switch result {
      case .waiting(let reason):
        try setWaiting(intent, expected: expected, reason: reason.message)
        return nil
      case .recoveryRequired:
        try setRecovery(expected)
        return nil
      case .verified(let version), .repaired(let version):
        let digest = audio ? intent.audioDigest : intent.markdownDigest
        let count = audio ? intent.audioByteCount : intent.markdownByteCount
        let prior = audio ? intent.audioVersion : intent.markdownVersion
        let repaired: Bool
        if case .repaired = result { repaired = true } else { repaired = false }
        let permitted =
          repaired
          ? prior != nil && prior != version : prior == nil || prior == version
        guard version.digest == digest, version.byteCount == count, permitted
        else {
          try setRecovery(expected)
          return nil
        }
        guard prior == nil || repaired else { return job }
        var updated = intent
        if audio { updated.audioVersion = version } else { updated.markdownVersion = version }
        job.commit = updated
        try queue.replace(job)
        onChange?()
        return job
      }
    } catch { return nil }
  }

  private func finishVerified(
    _ version: DiaryPairVersion, intent: DiaryCommitRecord, expected: QueueJob
  ) async throws {
    guard version.markdownDigest == intent.markdownDigest,
      version.audioDigest == intent.audioDigest,
      version.markdownIdentity == intent.markdownVersion?.identity,
      version.audioIdentity == intent.audioVersion?.identity
    else {
      try setRecovery(expected)
      return
    }
    guard try current(intent, expected: expected) != nil else { return }
    let observations = await pairs.observeUploads(version, intent: intent)
    guard observations.proves(version) else {
      try setWaiting(intent, expected: expected, reason: DiaryCommitWait.upload.message)
      return
    }
    guard try current(intent, expected: expected) != nil else { return }
    switch await pairs.verifyUnchanged(version, intent: intent) {
    case .waiting:
      try setWaiting(intent, expected: expected, reason: DiaryCommitWait.upload.message)
      return
    case .changed:
      try setRecovery(expected)
      return
    case .unchanged: break
    }
    guard var latest = try current(intent, expected: expected) else { return }
    latest.state = .saved
    latest.reason = nil
    try queue.replace(latest)
    onChange?()
    let announced = try deliverSavedNotice(latest)
    try finishCleanup(announced)
  }

  func resumeCleanup() {
    guard !maintenanceSuspended else { return }
    guard let jobs = try? queue.jobs() else { return }
    for job in jobs {
      guard job.state == .saved, job.commit != nil else { continue }
      guard let announced = try? deliverSavedNotice(job) else { continue }
      if announced.commitCleanupDone != true { try? finishCleanup(announced) }
    }
  }

  private func deliverSavedNotice(_ expected: QueueJob) throws -> QueueJob {
    guard expected.state == .saved, expected.commitNoticeDelivered != true else {
      return expected
    }
    var job = expected
    job.commitNoticeDelivered = true
    try queue.replace(job)
    onChange?()
    onSaved?(job)
    return job
  }

  private func finishCleanup(_ expected: QueueJob) throws {
    guard var job = try queue.jobs().first(where: { $0.id == expected.id }),
      job == expected, job.state == .saved, job.commit != nil,
      job.commitCleanupDone != true
    else { return }
    try cleanup.removeOwnedStaging(job: job)
    job.commitCleanupDone = true
    try queue.replace(job)
    onChange?()
  }

  private func current(_ intent: DiaryCommitRecord, expected: QueueJob) throws -> QueueJob? {
    guard let found = try queue.jobs().first(where: { $0.id == expected.id }),
      found == expected, found.state == .readyToSave, found.commit == intent
    else { return nil }
    return found
  }

  private func setWaiting(
    _ intent: DiaryCommitRecord, expected: QueueJob, reason: String
  ) throws {
    guard var job = try current(intent, expected: expected) else { return }
    job.reason = reason
    try queue.replace(job)
    onChange?()
  }

  private func setRecovery(_ expected: QueueJob) throws {
    guard var job = try queue.jobs().first(where: { $0.id == expected.id }),
      job == expected
    else { return }
    job.reason = "This diary pair needs review."
    try queue.replace(job)
    onChange?()
  }
}

extension DiaryCommitCoordinator {
  fileprivate func resolveConflict(
    _ claim: DiaryConflictResolutionClaim, expected: QueueJob
  ) async throws {
    guard let conflictPairs, claim.matches(job: expected),
      let selected = claim.selectedVersion
    else { return }
    let audioResult = await conflictPairs.ensureAudio(claim, job: expected)
    guard
      let withAudio = try persistConflictFile(
        audioResult, expected: expected, audio: true),
      let audioClaim = withAudio.conflictResolution
    else { return }
    let markdownResult = await conflictPairs.ensureMarkdown(audioClaim, job: withAudio)
    guard
      let withMarkdown = try persistConflictFile(
        markdownResult, expected: withAudio, audio: false),
      let finalClaim = withMarkdown.conflictResolution,
      let commit = withMarkdown.commit
    else { return }
    guard try current(commit, expected: withMarkdown) != nil else { return }
    switch await conflictPairs.verifyPair(finalClaim, job: withMarkdown) {
    case .waiting(let wait):
      try setWaiting(commit, expected: withMarkdown, reason: wait.message)
    case .recoveryRequired:
      try setRecovery(withMarkdown)
    case .verified(let version):
      try await finishConflictPair(
        version, selected: selected, claim: finalClaim,
        expected: withMarkdown, commit: commit)
    }
  }

  fileprivate func finishConflictPair(
    _ version: DiaryPairVersion, selected: DiaryPairVersion,
    claim: DiaryConflictResolutionClaim, expected: QueueJob,
    commit: DiaryCommitRecord
  ) async throws {
    guard let conflictPairs,
      version.markdownDigest == selected.markdownDigest,
      version.audioDigest == selected.audioDigest,
      version.markdownIdentity == claim.publishedMarkdown?.identity,
      version.audioIdentity == claim.publishedAudio?.identity
    else {
      try setRecovery(expected)
      return
    }
    let proof = await conflictPairs.observeUploads(
      version, claim: claim, job: expected)
    guard try current(commit, expected: expected) != nil else { return }
    guard proof.proves(version) else {
      try setWaiting(commit, expected: expected, reason: DiaryCommitWait.upload.message)
      return
    }
    switch await conflictPairs.verifyUnchanged(version, claim: claim, job: expected) {
    case .waiting:
      try setWaiting(commit, expected: expected, reason: DiaryCommitWait.upload.message)
    case .changed:
      try setRecovery(expected)
    case .unchanged:
      guard var latest = try current(commit, expected: expected),
        var resolution = latest.conflictResolution
      else { return }
      resolution.pairVerified = true
      latest.conflictResolution = resolution
      latest.reason =
        resolution.removalConfirmed == true
        ? "Conflicting versions are waiting for cleanup."
        : "Waiting for confirmation to remove the other version."
      try queue.replace(latest)
      onChange?()
      if resolution.removalConfirmed == true {
        try await completeConflictCleanup(latest)
      }
    }
  }

  fileprivate func completeConflictCleanup(_ expected: QueueJob) async throws {
    guard let conflictPairs, let claim = expected.conflictResolution,
      claim.matches(job: expected), claim.pairVerified == true,
      claim.removalConfirmed == true, let commit = expected.commit,
      try current(commit, expected: expected) != nil
    else { return }
    let result = await conflictPairs.removeObsolete(claim, job: expected)
    guard var latest = try current(commit, expected: expected),
      var resolution = latest.conflictResolution
    else { return }
    switch result {
    case .waiting:
      try setWaiting(
        commit, expected: expected, reason: "Waiting for iCloud conflict cleanup.")
    case .recoveryRequired:
      try setRecovery(expected)
    case .done:
      resolution.providerCleanupDone = true
      latest.conflictResolution = resolution
      try queue.replace(latest)
      onChange?()
      latest.state = .saved
      latest.reason = nil
      try queue.replace(latest)
      onChange?()
      let announced = try deliverSavedNotice(latest)
      try finishCleanup(announced)
    }
  }

  fileprivate func persistConflictFile(
    _ result: DiaryFileResult, expected: QueueJob, audio: Bool
  ) throws -> QueueJob? {
    guard var job = try queue.jobs().first(where: { $0.id == expected.id }),
      job == expected, var claim = job.conflictResolution,
      let selected = claim.selectedVersion, let commit = job.commit,
      claim.matches(job: job)
    else { return nil }
    switch result {
    case .waiting(let wait):
      try setWaiting(commit, expected: expected, reason: wait.message)
      return nil
    case .recoveryRequired:
      try setRecovery(expected)
      return nil
    case .verified(let version), .repaired(let version):
      let expectedDigest = audio ? selected.audioDigest : selected.markdownDigest
      let prior = audio ? claim.publishedAudio : claim.publishedMarkdown
      guard version.digest == expectedDigest, version.byteCount > 0,
        prior == nil || prior == version
      else {
        try setRecovery(expected)
        return nil
      }
      guard prior == nil else { return job }
      if audio { claim.publishedAudio = version } else { claim.publishedMarkdown = version }
      job.conflictResolution = claim
      try queue.replace(job)
      onChange?()
      return job
    }
  }

  /// M17 calls this only after the user chooses an ambiguous complete pair.
  /// Selection is durable; publication must recheck the same external versions.
  func chooseConflict(jobID: String, snapshotID: String) async -> Bool {
    guard !maintenanceSuspended, activeJobIDs.insert(jobID).inserted else { return false }
    defer {
      activeJobIDs.remove(jobID)
      onSettled?(jobID)
    }
    guard let conflicts,
      let expected = try? queue.jobs().first(where: { $0.id == jobID }),
      expected.state == .readyToSave,
      let claim = expected.conflictResolution,
      claim.matches(job: expected), claim.selectedSnapshotID == nil,
      snapshotID == claim.firstSnapshotID || snapshotID == claim.secondSnapshotID,
      await conflicts.validateChoice(claim, snapshotID: snapshotID, job: expected),
      var latest = try? queue.jobs().first(where: { $0.id == jobID }),
      latest == expected
    else { return false }
    var selected = claim
    selected.selectedSnapshotID = snapshotID
    latest.conflictResolution = selected
    do {
      try queue.replace(latest)
      onChange?()
      return true
    } catch { return false }
  }

  /// M17 calls this after the user confirms removal of the unchosen version.
  /// The provider adapter still requires verified publication and fresh checks.
  func confirmConflictRemoval(jobID: String) -> Bool {
    guard !maintenanceSuspended, !activeJobIDs.contains(jobID),
      var job = try? queue.jobs().first(where: { $0.id == jobID }),
      job.state == .readyToSave,
      var claim = job.conflictResolution,
      claim.matches(job: job), claim.selectedSnapshotID != nil,
      claim.removalConfirmed != true
    else { return false }
    claim.removalConfirmed = true
    job.conflictResolution = claim
    do {
      try queue.replace(job)
      onChange?()
      return true
    } catch { return false }
  }

  fileprivate func recordConflict(_ expected: QueueJob) async throws {
    guard let conflicts, let asset = expected.draftAssetID,
      let id = try? AssetID(asset),
      let created = try? SchemaInstant.from(date: expected.startedAt)
    else {
      try setRecovery(expected)
      return
    }
    let result = await conflicts.inspectCaptureConflicts(
      reference: expected.destinationReference, id: id, createdAt: created)
    guard case .candidates(let candidates) = result,
      var job = try queue.jobs().first(where: { $0.id == expected.id }),
      job == expected,
      let claim = try? DiaryConflictResolutionClaim(job: job, candidates: candidates)
    else {
      try setRecovery(expected)
      return
    }
    if let previous = job.conflictResolution {
      guard previous.matches(job: job),
        previous.firstSnapshotID == claim.firstSnapshotID,
        previous.secondSnapshotID == claim.secondSnapshotID,
        previous.firstVersion == claim.firstVersion,
        previous.secondVersion == claim.secondVersion,
        previous.expectedMarkdown == claim.expectedMarkdown,
        previous.expectedAudio == claim.expectedAudio
      else {
        try setRecovery(expected)
        return
      }
      job.conflictResolution = previous
    } else {
      job.conflictResolution = claim
    }
    job.reason = "Conflicting diary versions are preserved for review."
    try queue.replace(job)
    onChange?()
  }
}
