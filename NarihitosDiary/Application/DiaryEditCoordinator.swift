import Foundation

enum DiaryEditSubmissionResult: Equatable {
  case accepted(UUID)
  case unchanged
  case rejected(DiaryEditIssue)
  case uncertain(DiaryEditIssue)
}

/// Submitted edits outlive their editor. Scheduling stores only small records;
/// bodies/audio are loaded through the journal on demand, never as queue jobs.
@MainActor
final class DiaryEditCoordinator {
  private struct Request {
    let submission: DiaryEditSubmission
    let task: Task<DiaryEditSubmissionResult, Never>
  }

  private let store: any DiaryEditStorePort
  private let titles: DiaryTitlePolicy
  private let now: () -> Date
  private var requests: [UUID: Request] = [:]
  private var claimedResources: Set<String> = []
  private var work: [UUID: Task<Void, Never>] = [:]
  private var discovery: Task<Void, Never>?
  private var records: [UUID: DiaryEditRecord] = [:]
  private var attempted: Set<UUID> = []
  private var active = false
  private var suspended = false
  private var reconciled = false
  private var generation = UUID()
  private var retryTask: Task<Void, Never>?
  private var retryIndex = 0
  private let retrySleep: @MainActor (Duration) async throws -> Void
  private var openingCount = 0
  private var deleting = false
  private var uncertainSubmissions: Set<UUID> = []
  private(set) var isolatedCount = 0
  private(set) var discoveryIssue: DiaryEditIssue?
  var onChange: (@MainActor () -> Void)?
  var onPublished: (@MainActor (DiaryEditRecord) -> Void)?
  var onAccepted: (@MainActor (DiaryEditRecord) -> Void)?

  init(
    store: any DiaryEditStorePort, titles: DiaryTitlePolicy,
    now: @escaping () -> Date = Date.init,
    retrySleep: @escaping @MainActor (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) {
    self.store = store
    self.titles = titles
    self.now = now
    self.retrySleep = retrySleep
  }

  var hasActiveWork: Bool {
    deleting || discovery != nil || openingCount > 0 || !requests.isEmpty || !work.isEmpty
      || titles.hasActiveWork
  }

  var pending: [DiaryEditRecord] {
    records.values.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  func activate() {
    guard !suspended else { return }
    active = true
    retryTask?.cancel()
    retryTask = nil
    retryIndex = 0
    attempted.removeAll()
    if !reconciled { discover() } else { pump() }
  }

  func deactivate() {
    active = false
    retryTask?.cancel()
    retryTask = nil
    generation = UUID()
    store.pauseSessions()
    // Accepted work is not discarded or retargeted by view/scene departure.
    // Active accessors retain ownership until their operation actually returns.
  }

  func prerequisiteChanged() {
    guard active, !suspended else { return }
    attempted.removeAll()
    retryTask?.cancel()
    retryTask = nil
    if !reconciled { discover() } else { pump() }
  }

  func suspendForMaintenance() {
    suspended = true
    deactivate()
    store.invalidateSessions()
  }

  func closeSession(_ id: UUID) { store.closeSession(id) }

  func endMaintenance() {
    guard !hasActiveWork else { return }
    generation = UUID()
    records.removeAll()
    attempted.removeAll()
    reconciled = false
    suspended = false
  }

  func open(_ handle: CatalogItemHandle) async throws -> DiaryEditSession {
    guard active, !suspended, reconciled, !deleting else { throw DiaryEditIssue.busy }
    openingCount += 1
    defer { openingCount -= 1 }
    let epoch = generation
    let session = try await store.open(handle)
    guard active, !suspended, epoch == generation else {
      store.closeSession(session.id)
      throw DiaryEditIssue.changed
    }
    return session
  }

  func submit(
    _ submission: DiaryEditSubmission, session: DiaryEditSession
  ) async -> DiaryEditSubmissionResult {
    if let existing = requests[submission.id] {
      guard existing.submission == submission else { return .rejected(.changed) }
      return await existing.task.value
    }
    guard active, !suspended, reconciled, !deleting, submission.sessionID == session.id
    else {
      return uncertainSubmissions.contains(submission.id) ? .uncertain(.busy) : .rejected(.busy)
    }
    let task = Task { [self] in
      await accept(submission, session: session)
    }
    requests[submission.id] = Request(submission: submission, task: task)
    let result = await task.value
    requests[submission.id] = nil
    pump()
    return result
  }

  private func accept(
    _ submission: DiaryEditSubmission, session: DiaryEditSession
  ) async -> DiaryEditSubmissionResult {
    do {
      if let record = try await store.accepted(submission, session: session) {
        uncertainSubmissions.remove(submission.id)
        records[record.id] = record
        onAccepted?(record)
        onChange?()
        return .accepted(record.id)
      }
      guard active, !suspended, !claimedResources.contains(session.resourceKey),
        !records.values.contains(where: { $0.resourceKey == session.resourceKey })
      else { return .rejected(.busy) }
      claimedResources.insert(session.resourceKey)
      defer { claimedResources.remove(session.resourceKey) }
      let candidate = try DiaryEditRevision.make(
        source: session.snippet, change: submission.change, now: now())
      switch try await store.accept(submission, session: session, candidate: candidate) {
      case .unchanged:
        uncertainSubmissions.remove(submission.id)
        return .unchanged
      case .accepted(let record):
        uncertainSubmissions.remove(submission.id)
        records[record.id] = record
        onAccepted?(record)
        onChange?()
        return .accepted(record.id)
      }
    } catch is AssetValueError {
      return .rejected(.invalidCandidate)
    } catch {
      let issue = (error as? DiaryEditIssue) ?? .storage
      if issue == .submissionMismatch { return .rejected(.changed) }
      do {
        if let record = try await store.accepted(submission, session: session) {
          uncertainSubmissions.remove(submission.id)
          records[record.id] = record
          onAccepted?(record)
          onChange?()
          return .accepted(record.id)
        }
        uncertainSubmissions.remove(submission.id)
        return .rejected(issue)
      } catch {
        uncertainSubmissions.insert(submission.id)
        reconciled = false
        discoveryIssue = .localData
        onChange?()
        return .uncertain(issue)
      }
    }
  }

  private func discover() {
    guard discovery == nil, active, !suspended else { return }
    let epoch = generation
    discovery = Task { [self] in
      defer {
        discovery = nil
        onChange?()
        if active, !suspended, epoch != generation { discover() } else { pump() }
      }
      do {
        records.removeAll()
        isolatedCount = 0
        var cursor: String?
        repeat {
          let page = try await store.inventory(after: cursor)
          guard epoch == generation, active, !suspended else { return }
          for record in page.records { records[record.id] = record }
          isolatedCount += page.isolatedCount
          cursor = page.continuation
          await Task.yield()
        } while cursor != nil
        reconciled = true
        discoveryIssue = nil
      } catch {
        discoveryIssue = (error as? DiaryEditIssue) ?? .localData
      }
    }
  }

  private func pump() {
    guard active, !suspended, !deleting else { return }
    guard reconciled else {
      scheduleRetry()
      return
    }
    // A stalled resource cannot monopolize edits of other resources. Bound the
    // concurrent accessors without imposing a retained-transaction count cap.
    for record in pending where work.count < 2 {
      guard !attempted.contains(record.id), !claimedResources.contains(record.resourceKey),
        record.stage != .recovery, record.stage != .quarantined
      else { continue }
      attempted.insert(record.id)
      claimedResources.insert(record.resourceKey)
      work[record.id] = Task { [self] in
        await advance(record)
        work[record.id] = nil
        claimedResources.remove(record.resourceKey)
        onChange?()
        pump()
      }
    }
    scheduleRetry()
  }

  private func scheduleRetry() {
    guard active, !suspended, retryTask == nil, discovery == nil, work.count < 2,
      !reconciled
        || pending.contains(where: {
          work[$0.id] == nil && $0.issue?.canRetryAutomatically == true
            && $0.stage != .recovery && $0.stage != .quarantined
        })
    else { return }
    let delays: [Duration] = [.seconds(5), .seconds(15), .seconds(30), .seconds(60)]
    let delay = delays[min(retryIndex, delays.count - 1)]
    retryIndex = min(retryIndex + 1, delays.count - 1)
    let epoch = generation
    retryTask = Task { [weak self, retrySleep] in
      do { try await retrySleep(delay) } catch { return }
      guard let self, !Task.isCancelled, epoch == generation, active, !suspended else { return }
      retryTask = nil
      for record in pending
      where work[record.id] == nil && record.issue?.canRetryAutomatically == true {
        attempted.remove(record.id)
      }
      if reconciled { pump() } else { discover() }
    }
  }
}

extension DiaryEditCoordinator {
  func beginDeletion() -> Bool {
    guard active, !suspended, reconciled, !hasActiveWork, pending.isEmpty,
      isolatedCount == 0, discoveryIssue == nil, uncertainSubmissions.isEmpty
    else { return false }
    deleting = true
    store.invalidateSessions()
    return true
  }
  func endDeletion() {
    deleting = false
    onChange?()
    pump()
  }
  private func advance(_ initial: DiaryEditRecord) async {
    var record = initial
    do {
      record = try await finalize(record)
      guard active, !suspended else { return }
      if record.stage == .ready || record.stage == .published {
        guard let published = try await publish(record) else { return }
        record = published
      }
      if record.stage == .published {
        guard let complete = try await verifyUploads(record) else { return }
        record = complete
      }
      if record.stage == .completed {
        try await store.cleanup(record)
        records[record.id] = nil
      }
    } catch {
      guard reconciled else { return }
      if record.stage == .completed {
        // Retirement may already have moved/deleted the journal. Reconcile its
        // durable receipt instead of checkpointing into the old directory.
        reconciled = false
        discoveryIssue = .localData
        onChange?()
        return
      }
      let issue = (error as? DiaryEditIssue) ?? .localData
      if issue == .changed || issue == .conflict || issue == .invalidCandidate {
        record.stage = .recovery
      }
      try? await retain(&record, issue: issue)
    }
  }

  private func retain(_ record: inout DiaryEditRecord, issue: DiaryEditIssue) async throws {
    record.issue = issue
    try await persist(record)
  }

  private func finalize(_ record: DiaryEditRecord) async throws -> DiaryEditRecord {
    guard record.stage == .accepted else { return record }
    var candidate = try await store.candidate(for: record)
    if record.regeneratesTitle {
      let title = await titles.title(for: candidate.body, owner: .edit(submissionID: record.id))
      candidate.title = title.text
      candidate.titleProvenance = title.provenance
    }
    let finalized = try await store.finalize(record, candidate: candidate)
    records[record.id] = finalized
    return finalized
  }

  private func publish(_ initial: DiaryEditRecord) async throws -> DiaryEditRecord? {
    var record = initial
    switch await store.publish(record) {
    case .verified(let version):
      record.publishedVersion = version
      record.stage = .published
      record.issue = nil
      try await persist(record)
      if initial.stage != .published || initial.publishedVersion != version { onPublished?(record) }
      return record
    case .waiting(let issue):
      try await retain(&record, issue: issue)
    case .recovery(let issue):
      record.stage = .recovery
      try await retain(&record, issue: issue)
    }
    return nil
  }

  private func verifyUploads(_ initial: DiaryEditRecord) async throws -> DiaryEditRecord? {
    var record = initial
    guard let version = record.publishedVersion else { throw DiaryEditIssue.changed }
    let proof = try await store.uploads(for: record)
    record.markdownUploaded =
      proof.markdown
      == DiaryFileUploadProof(identity: version.markdownIdentity, digest: version.markdownDigest)
    record.audioUploaded =
      proof.audio
      == DiaryFileUploadProof(identity: version.audioIdentity, digest: version.audioDigest)
    guard proof.proves(version) else {
      try await retain(&record, issue: .upload)
      return nil
    }
    record.issue = nil
    // Adapter operations require the exact journal checkpoint they consume.
    // Persist both reports before the final pair check, then record completion.
    try await persist(record)
    guard try await store.verifyUnchanged(record) else { throw DiaryEditIssue.changed }
    record.stage = .completed
    try await persist(record)
    return record
  }

  private func persist(_ record: DiaryEditRecord) async throws {
    do {
      try await store.checkpoint(record)
      records[record.id] = record
    } catch {
      reconciled = false
      discoveryIssue = .localData
      onChange?()
      throw error
    }
  }
}
