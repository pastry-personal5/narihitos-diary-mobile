import Foundation

/// Advances verified transcription results into durable local drafts. No iCloud
/// access is required for this stage.
@MainActor
final class DiaryDraftAdoptionCoordinator {
  private let queue: any QueueStorePort
  private let receipts: any QueueReceiptSourcePort
  private let candidates: any TranscriptionCandidateStore
  private let drafts: any DiaryDraftStore
  private let titles: DiaryTitlePolicy
  private let makeAssetID: () throws -> AssetID
  private let factory = DiaryDraftFactory()
  private var activeTask: Task<Void, Never>?
  private var isActive = false
  private var paused = false
  private(set) var pausedReason: String?
  var onChange: (@MainActor () -> Void)?

  init(
    queue: any QueueStorePort, receipts: any QueueReceiptSourcePort,
    candidates: any TranscriptionCandidateStore, drafts: any DiaryDraftStore,
    titles: DiaryTitlePolicy,
    makeAssetID: @escaping () throws -> AssetID = AssetID.random
  ) {
    self.queue = queue
    self.receipts = receipts
    self.candidates = candidates
    self.drafts = drafts
    self.titles = titles
    self.makeAssetID = makeAssetID
  }

  var hasActiveWork: Bool { activeTask != nil || titles.hasActiveWork }
  private var maintenanceSuspended = false

  func suspendForMaintenance() {
    maintenanceSuspended = true
    deactivate()
  }

  func endMaintenance() { maintenanceSuspended = false }

  func activate() {
    guard !maintenanceSuspended else { return }
    isActive = true
    paused = false
    pausedReason = nil
    cleanupAdoptedCandidates()
    pump()
  }

  func deactivate() {
    isActive = false
    activeTask?.cancel()
  }

  func prerequisiteChanged() {
    guard !maintenanceSuspended else { return }
    paused = false
    pausedReason = nil
    cleanupAdoptedCandidates()
    pump()
  }

  private func cleanupAdoptedCandidates() {
    guard let jobs = try? queue.jobs() else { return }
    for job in jobs where job.state == .readyToSave {
      // A candidate is the recovery copy if the draft was lost after transition.
      // Discard checks the exact closed attempt once the draft is verified.
      guard (try? drafts.inspect(job: job)) == .verified else { continue }
      try? candidates.discard(job: job)
    }
  }

  private func pump() {
    guard isActive, !paused, activeTask == nil else { return }
    guard
      let job = try? queue.jobs().filter({ $0.state == .resultReady }).sorted(by: {
        $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt
      }).first
    else {
      return
    }
    activeTask = Task { [weak self] in
      guard let self else { return }
      await self.adopt(job)
      self.activeTask = nil
      self.pump()
    }
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private func adopt(_ initial: QueueJob) async {
    do {
      guard let current = try currentJob(matching: initial), isActive,
        !Task.isCancelled
      else { return }
      switch try drafts.inspect(job: current) {
      case .verified:
        try finish(current)
        return
      case .protectedDataUnavailable:
        pause(reason: TranscriptionWaitReason.protectedDataUnavailable.message)
        return
      case .missing, .invalid: break
      }
      let candidate = try candidates.readVerified(job: current)
      guard let receipt = receipts.receipt(jobID: current.id), current.matches(receipt)
      else { throw DiaryDraftFactoryFailure.mismatchedClaim }
      var reserved = current
      if reserved.draftAssetID == nil {
        reserved.draftAssetID = try makeAssetID().description
        try queue.replace(reserved)
        onChange?()
      }
      guard let confirmed = try currentJob(matching: reserved), isActive,
        !Task.isCancelled
      else { return }
      let body = try DiaryBody(candidate.text)
      let title = await titles.title(
        for: body,
        owner: .recording(
          jobID: confirmed.id, attemptID: confirmed.attemptID,
          attemptGeneration: confirmed.attemptGeneration,
          destinationRevision: confirmed.destinationRevision, bodyRevision: confirmed.bodyRevision))
      guard let latest = try currentJob(matching: confirmed), isActive,
        !Task.isCancelled
      else { return }
      guard let rawID = latest.draftAssetID, let assetID = try? AssetID(rawID) else {
        throw QueueStoreFailure.corrupt
      }
      let snippet = try factory.make(
        job: latest, receipt: receipt, candidate: candidate,
        assetID: assetID, updatedAt: Date(), title: title)
      try drafts.publish(snippet, candidate: candidate, job: latest)
      guard let afterWrite = try currentJob(matching: latest), isActive,
        !Task.isCancelled
      else { return }
      try finish(afterWrite)
    } catch TranscriptionCandidateFailure.protectedDataUnavailable {
      pause(reason: TranscriptionWaitReason.protectedDataUnavailable.message)
    } catch AudioFingerprintFailure.protectedDataUnavailable {
      pause(reason: TranscriptionWaitReason.protectedDataUnavailable.message)
    } catch TranscriptionCandidateFailure.invalidSource {
      failInvalidClaim(initial, reason: TranscriptionFailure.audioUnreadable.message)
    } catch is DiaryDraftFactoryFailure {
      failInvalidClaim(initial, reason: "This recording needs review.")
    } catch {
      // Candidate/draft corruption remains visible with audio retained. The queue
      // reconciler determines the typed recovery state on the next activation.
      pause(reason: ProcessingQueueCoordinator.pausedReason)
    }
  }

  private func failInvalidClaim(_ initial: QueueJob, reason: String) {
    do {
      guard var current = try queue.jobs().first(where: { $0.id == initial.id }),
        current.state == .resultReady,
        current.attemptID == initial.attemptID,
        current.attemptGeneration == initial.attemptGeneration,
        current.destinationRevision == initial.destinationRevision,
        current.bodyRevision == initial.bodyRevision
      else { return }
      current.state = .failed
      current.reason = reason
      try queue.replace(current)
      onChange?()
    } catch {
      pause(reason: ProcessingQueueCoordinator.pausedReason)
    }
  }

  private func pause(reason: String) {
    paused = true
    pausedReason = reason
    onChange?()
  }

  private func currentJob(matching expected: QueueJob) throws -> QueueJob? {
    let found = try queue.jobs().first(where: { $0.id == expected.id })
    guard found == expected, found?.state == .resultReady else { return nil }
    return found
  }

  private func finish(_ job: QueueJob) throws {
    guard let current = try currentJob(matching: job),
      try drafts.inspect(job: current) == .verified
    else { throw QueueStoreFailure.corrupt }
    var ready = current
    ready.state = .readyToSave
    ready.reason = nil
    try queue.replace(ready)
    onChange?()
    try candidates.discard(job: ready)
  }
}
