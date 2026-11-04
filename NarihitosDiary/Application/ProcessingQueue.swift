import Foundation

// Queue models and their coordinator stay together so transition invariants remain inspectable.
// swiftlint:disable file_length

enum InstallationIdentityResult: Equatable, Sendable {
  case available(String)
  case missing
  case temporarilyUnavailable
}

@MainActor
protocol InstallationIdentityPort {
  func currentOrCreate() -> InstallationIdentityResult
  func current() -> InstallationIdentityResult
}

struct QueueReceipt: Equatable, Sendable {
  let id: WorkspaceID
  let startedAt: Date
  let language: CaptureLanguage
  let destinationReference: UUID
  let installationBinding: String?
  let inspection: CaptureInspection
}

enum QueueJobState: String, Codable, Sendable {
  case ready
  case waiting
  case transcribing
  case resultReady
  case readyToSave
  case saved
  case failed
  case reviewRequired
  case cancelling
  case removing
}

struct QueueJob: Codable, Equatable, Sendable {
  static let schemaVersion = 1

  let schema: Int
  let id: String
  let startedAt: Date
  let language: CaptureLanguage
  let destinationReference: UUID
  let sourceInstallationBinding: String?
  var installationBinding: String?
  let audioByteCount: Int64
  let audioDuration: TimeInterval
  let audioSampleRate: Double?
  let audioChannelCount: Int?
  var state: QueueJobState
  var reason: String?
  var attemptGeneration: Int
  var attemptID: UUID?
  var selectedMethodID: String?
  var effectiveSettings: [String: String]?
  var modelIdentity: String?
  var conversionIdentity: String?
  var destinationRevision: Int
  var bodyRevision: Int
  /// Assigned once before the first draft write; nil in older queue records without draft-asset identity.
  var draftAssetID: String?
  /// Absent in older records without commit tracking. An intent never implies upload success.
  var commit: DiaryCommitRecord?
  var commitCleanupDone: Bool?
  var commitNoticeDelivered: Bool?
  var conflictResolution: DiaryConflictResolutionClaim?

  init(receipt: QueueReceipt, state: QueueJobState, reason: String? = nil) {
    schema = Self.schemaVersion
    id = receipt.id.description
    startedAt = receipt.startedAt
    language = receipt.language
    destinationReference = receipt.destinationReference
    sourceInstallationBinding = receipt.installationBinding
    installationBinding = receipt.installationBinding
    audioByteCount = receipt.inspection.byteCount
    audioDuration = receipt.inspection.duration
    audioSampleRate = receipt.inspection.sampleRate
    audioChannelCount = receipt.inspection.channelCount
    self.state = state
    self.reason = reason
    attemptGeneration = 0
    destinationRevision = 0
    bodyRevision = 0
    draftAssetID = nil
    commit = nil
    commitCleanupDone = nil
    commitNoticeDelivered = nil
    conflictResolution = nil
  }

  func matches(_ receipt: QueueReceipt) -> Bool {
    id == receipt.id.description && startedAt == receipt.startedAt
      && language == receipt.language && destinationReference == receipt.destinationReference
      && sourceInstallationBinding == receipt.installationBinding
      && audioByteCount == receipt.inspection.byteCount
      && abs(audioDuration - receipt.inspection.duration) < 0.25
  }
}

enum QueueStoreFailure: Error, Equatable {
  case unavailable
  case corrupt
  case unsafeResource
}

@MainActor
protocol QueueStorePort: AnyObject {
  func jobs() throws -> [QueueJob]
  func createIfAbsent(_ job: QueueJob) throws -> QueueJob
  func replace(_ job: QueueJob) throws
  func remove(jobID: String) throws
}

@MainActor
protocol QueueReceiptSourcePort: AnyObject {
  func pendingReceipts() -> [QueueReceipt]
  func receipt(jobID: String) -> QueueReceipt?
  func removePrivateCapture(job: QueueJob) throws
}

@MainActor
protocol QueueSaveWork: AnyObject {
  func isWorking(jobID: String) -> Bool
}

enum TranscriptionWaitReason: Equatable, Sendable {
  case appleNotReady
  case protectedDataUnavailable
  case cohereNotInstalled
  case cohereQ5MemoryUnsupported
  case methodUnavailable

  var message: String {
    switch self {
    case .appleNotReady: "Apple transcription isn’t ready for this language."
    case .protectedDataUnavailable: "Recording is waiting for protected data."
    case .cohereNotInstalled: "Cohere model isn’t installed."
    case .cohereQ5MemoryUnsupported:
      "Cohere Q5 needs more memory than this iPhone can safely use. Choose another ready method."
    case .methodUnavailable: "The selected transcription method isn’t ready."
    }
  }

  func message(for language: CaptureLanguage) -> String {
    guard self == .appleNotReady else { return message }
    let name = language == .english ? "English" : "Korean"
    return "Apple transcription isn’t ready for \(name)."
  }
}

enum TranscriptionReadiness: Equatable, Sendable {
  case ready
  case waiting(TranscriptionWaitReason)
}

struct TranscriptionDescriptor: Equatable, Sendable {
  let id: String
  let supportedLanguages: Set<CaptureLanguage>
  let requiresMonoAAC: Bool
}

enum TranscriptionMethodIdentifiers {
  static let apple = "ndm.transcription.apple"
  static let cohere = "ndm.transcription.cohere"
}

struct EffectiveTranscriptionSettings: Equatable, Sendable {
  let values: [String: String]
  let modelIdentity: String?
  let conversionIdentity: String
}

struct TranscriptionRequest: Equatable, Sendable {
  let jobID: String
  let attemptID: UUID
  let generation: Int
  let language: CaptureLanguage
  let settings: EffectiveTranscriptionSettings
  let destinationRevision: Int
  let bodyRevision: Int
}

enum TranscriptionFailure: Equatable, Sendable {
  case unusableText
  case audioUnreadable
  case outputTooLarge
  case inference
  case cancelled

  var message: String {
    switch self {
    case .unusableText: "No usable diary text was found."
    case .audioUnreadable: "This recording can’t be read."
    case .outputTooLarge: "The transcription is too long."
    case .inference: "Transcription couldn’t finish."
    case .cancelled: "Transcription was cancelled."
    }
  }
}

enum TranscriptionResult: Equatable, Sendable {
  case success(TranscriptionPayload)
  case waiting(TranscriptionWaitReason)
  case failure(TranscriptionFailure)
}

@MainActor
protocol TranscriptionWork: AnyObject {
  func cancel()
}

@MainActor
protocol TranscriptionMethodAdapter: AnyObject {
  var descriptor: TranscriptionDescriptor { get }
  func readiness(for language: CaptureLanguage) -> TranscriptionReadiness
  func start(
    _ request: TranscriptionRequest,
    completion: @escaping @MainActor (TranscriptionResult) -> Void
  ) -> any TranscriptionWork
}

struct TranscriptionPreflight: Sendable {
  let readiness: TranscriptionReadiness
  let effectiveValues: [String: String]
}

@MainActor
protocol AsynchronousTranscriptionReadiness: TranscriptionMethodAdapter {
  func preflight(for language: CaptureLanguage) async -> TranscriptionPreflight
}

@MainActor
protocol TranscriptionSettingsPort: AnyObject {
  func selectedMethodID(for language: CaptureLanguage) -> String?
  func effectiveSettings(methodID: String, language: CaptureLanguage)
    -> EffectiveTranscriptionSettings
}

@MainActor
final class TranscriptionMethodRegistry {
  private var adapters: [String: any TranscriptionMethodAdapter] = [:]

  func register(_ adapter: any TranscriptionMethodAdapter) {
    precondition(adapters[adapter.descriptor.id] == nil)
    adapters[adapter.descriptor.id] = adapter
  }

  func adapter(id: String) -> (any TranscriptionMethodAdapter)? { adapters[id] }

  func refreshReadiness() {
    for adapter in adapters.values {
      _ = adapter.readiness(for: .english)
      _ = adapter.readiness(for: .korean)
    }
  }
}

struct QueueProjection: Identifiable, Equatable, Sendable {
  let id: String
  let startedAt: Date
  let language: CaptureLanguage
  let state: QueueJobState
  let reason: String?
}

@MainActor
// swiftlint:disable:next type_body_length
final class ProcessingQueueCoordinator {
  static let timeoutReason = "Transcription stopped after 10 minutes."
  static let reviewReason = "This recording was restored and needs review."
  static let pausedReason = "Pending work is paused because local storage isn’t available."

  private let store: any QueueStorePort
  private let receipts: any QueueReceiptSourcePort
  private let identity: any InstallationIdentityPort
  private let settings: any TranscriptionSettingsPort
  private let registry: TranscriptionMethodRegistry
  private let candidates: any TranscriptionCandidateStore
  private let drafts: (any DiaryDraftStore)?
  var saveWork: (any QueueSaveWork)?
  private let timeout: Duration
  private struct ActiveAttempt {
    let jobID: String
    let generation: Int
    let work: any TranscriptionWork
    var invalidated = false
  }

  private var activeWork: ActiveAttempt?
  private var readinessGeneration = 0
  private var readinessTasks: [String: Task<Void, Never>] = [:]
  private var timeoutTask: Task<Void, Never>?
  var onChange: (@MainActor () -> Void)?
  private(set) var isActive = false
  private(set) var pausedReason: String?

  init(
    store: any QueueStorePort, receipts: any QueueReceiptSourcePort,
    identity: any InstallationIdentityPort, settings: any TranscriptionSettingsPort,
    registry: TranscriptionMethodRegistry,
    candidates: any TranscriptionCandidateStore = UnavailableTranscriptionCandidateStore(),
    drafts: (any DiaryDraftStore)? = nil,
    timeout: Duration = .seconds(600)
  ) {
    self.store = store
    self.receipts = receipts
    self.identity = identity
    self.settings = settings
    self.registry = registry
    self.candidates = candidates
    self.drafts = drafts
    self.timeout = timeout
  }

  private(set) var maintenanceSuspended = false
  var hasActiveWork: Bool { activeWork != nil }

  func suspendForMaintenance() {
    maintenanceSuspended = true
    deactivate()
  }

  func endMaintenance() { maintenanceSuspended = false }

  func activate() {
    guard !maintenanceSuspended else { return }
    invalidateReadiness()
    isActive = true
    registry.refreshReadiness()
    reconcile()
    reconsiderWaitingJobs()
  }

  func deactivate() {
    isActive = false
    invalidateReadiness()
  }

  func settingsEntered() {
    guard !maintenanceSuspended else { return }
    invalidateReadiness()
    registry.refreshReadiness()
    reconsiderWaitingJobs()
  }

  func prerequisiteChanged() {
    guard !maintenanceSuspended else { return }
    invalidateReadiness()
    registry.refreshReadiness()
    reconsiderWaitingJobs()
  }

  func captureSettled() {
    guard !maintenanceSuspended else { return }
    reconcile()
    processNext()
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func reconcile() {
    guard !maintenanceSuspended else { return }
    let current: String
    switch identity.currentOrCreate() {
    case .available(let value): current = value
    case .missing, .temporarilyUnavailable:
      pauseQueue()
      return
    }
    do {
      let existing = try store.jobs()
      for receipt in receipts.pendingReceipts() {
        if let job = existing.first(where: { $0.id == receipt.id.description }) {
          if !job.matches(receipt) || job.installationBinding != current {
            var quarantined = job
            quarantined.state = .reviewRequired
            quarantined.reason = Self.reviewReason
            try store.replace(quarantined)
          }
          continue
        }
        let matches = receipt.installationBinding == current
        let job = QueueJob(
          receipt: receipt, state: matches ? .ready : .reviewRequired,
          reason: matches ? nil : Self.reviewReason)
        _ = try store.createIfAbsent(job)
      }
      // swiftlint:disable opening_brace
      for var job in try store.jobs()
      where job.installationBinding != current && job.state != .removing
        && job.state != .cancelling
      {
        job.state = .reviewRequired
        job.reason = Self.reviewReason
        try store.replace(job)
      }
      // swiftlint:enable opening_brace
      // swiftlint:disable opening_brace
      for var job in try store.jobs()
      where (job.state == .transcribing && activeWork?.jobID != job.id)
        || job.state == .resultReady
      {
        if job.state == .resultReady, let drafts {
          switch try drafts.inspect(job: job) {
          case .verified:
            job.state = .readyToSave
            job.reason = nil
            try store.replace(job)
            continue
          case .protectedDataUnavailable: continue
          case .missing, .invalid: break
          }
        }
        let inspection = try candidates.inspect(job: job)
        switch inspection {
        case .verified:
          if job.state == .transcribing {
            job.state = .resultReady
            job.reason = nil
            try store.replace(job)
          }
        case .protectedDataUnavailable:
          continue
        case .missing, .invalid:
          let needsReview = job.state == .resultReady || inspection == .invalid
          job.attemptGeneration += 1
          job.attemptID = nil
          job.state = .failed
          job.reason =
            needsReview
            ? "This recording needs review."
            : "Transcription was interrupted. Retry when ready."
          try store.replace(job)
        }
      }
      // swiftlint:enable opening_brace
      if let drafts {
        for var job in try store.jobs() where job.state == .readyToSave {
          switch try drafts.inspect(job: job) {
          case .verified, .protectedDataUnavailable: continue
          case .missing, .invalid:
            switch try candidates.inspect(job: job) {
            case .verified:
              job.state = .resultReady
              job.reason = nil
            case .protectedDataUnavailable: continue
            case .missing, .invalid:
              job.state = .failed
              job.reason = "This diary draft needs review."
            }
            try store.replace(job)
          }
        }
      }
      for job in try store.jobs() where job.state == .removing {
        guard finishRemoval(jobID: job.id) else { return }
      }
      for var job in try store.jobs() {
        guard job.state == .cancelling, activeWork?.jobID != job.id,
          saveWork?.isWorking(jobID: job.id) != true
        else { continue }
        job.state = .removing
        try store.replace(job)
        guard finishRemoval(jobID: job.id) else { return }
      }
      pausedReason = nil
      onChange?()
    } catch {
      pauseQueue()
    }
  }

  func manualRetry(jobID: String) {
    guard !maintenanceSuspended else { return }
    do {
      // swiftlint:disable opening_brace
      if let job = try store.jobs().first(where: { $0.id == jobID }),
        job.state == .failed || job.state == .waiting
      {
        try candidates.discard(job: job)
      }
      // swiftlint:enable opening_brace
    } catch {
      pauseQueue()
      return
    }
    mutate(jobID: jobID) { job in
      guard job.state == .failed || job.state == .waiting else { return }
      job.attemptGeneration += 1
      job.attemptID = nil
      job.state = .ready
      job.reason = nil
      job.selectedMethodID = nil
      job.effectiveSettings = nil
      job.modelIdentity = nil
      job.conversionIdentity = nil
    }
    processNext()
  }

  func resumeRestored(jobID: String) {
    guard !maintenanceSuspended else { return }
    guard let receipt = receipts.receipt(jobID: jobID), receipt.inspection.isAccepted else {
      return
    }
    guard case .available(let current) = identity.current() else {
      pauseQueue()
      return
    }
    mutate(jobID: jobID) { job in
      guard job.state == .reviewRequired, job.matches(receipt) else { return }
      job.installationBinding = current
      job.attemptGeneration += 1
      job.state = .ready
      job.reason = nil
      job.selectedMethodID = nil
      job.effectiveSettings = nil
      job.modelIdentity = nil
      job.conversionIdentity = nil
    }
    processNext()
  }

  func remove(jobID: String) {
    guard !maintenanceSuspended else { return }
    guard (try? store.jobs().first(where: { $0.id == jobID }))?.state != .saved else {
      return
    }
    if saveWork?.isWorking(jobID: jobID) == true {
      _ = mutate(jobID: jobID) { job in
        job.attemptGeneration += 1
        job.state = .cancelling
        job.reason = nil
      }
      return
    }
    if let activeWork, activeWork.jobID == jobID {
      self.activeWork?.invalidated = true
      guard
        mutate(
          jobID: jobID,
          body: { job in
            job.attemptGeneration += 1
            job.state = .cancelling
            job.reason = nil
          })
      else {
        activeWork.work.cancel()
        return
      }
      activeWork.work.cancel()
      return
    }
    guard
      mutate(
        jobID: jobID,
        body: { job in
          job.attemptGeneration += 1
          job.state = .removing
          job.reason = nil
        })
    else { return }
    finishRemoval(jobID: jobID)
  }

  func saveAttemptSettled(jobID: String) {
    guard saveWork?.isWorking(jobID: jobID) != true else { return }
    do {
      guard var job = try store.jobs().first(where: { $0.id == jobID }),
        job.state == .cancelling
      else { return }
      job.state = .removing
      try store.replace(job)
      _ = finishRemoval(jobID: jobID)
    } catch { pauseQueue() }
  }

  func projections() -> [QueueProjection] {
    (try? store.jobs())?.map {
      QueueProjection(
        id: $0.id, startedAt: $0.startedAt, language: $0.language,
        state: $0.state, reason: $0.reason)
    }.sorted { lhs, rhs in
      lhs.startedAt == rhs.startedAt ? lhs.id < rhs.id : lhs.startedAt < rhs.startedAt
    } ?? []
  }

  private func reconsiderWaitingJobs() {
    guard pausedReason == nil else { return }
    guard let jobs = try? store.jobs() else {
      pauseQueue()
      return
    }
    for var job in jobs where job.state == .waiting {
      guard let methodID = settings.selectedMethodID(for: job.language),
        let adapter = registry.adapter(id: methodID)
      else { continue }
      guard
        adapter is any AsynchronousTranscriptionReadiness
          || adapter.readiness(for: job.language) == .ready
      else { continue }
      job.state = .ready
      job.reason = nil
      do { try store.replace(job) } catch {
        pauseQueue()
        return
      }
    }
    processNext()
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func processNext() {
    guard isActive, pausedReason == nil, activeWork == nil else { return }
    let jobs: [QueueJob]
    do { jobs = try store.jobs() } catch {
      pauseQueue()
      return
    }
    let ready = jobs.filter { $0.state == .ready }.sorted {
      $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt
    }
    for var job in ready {
      guard let methodID = settings.selectedMethodID(for: job.language),
        let adapter = registry.adapter(id: methodID)
      else {
        job.state = .waiting
        job.reason = "Choose an available transcription method."
        if !persist(job) { return }
        continue
      }
      guard adapter.descriptor.supportedLanguages.contains(job.language),
        !adapter.descriptor.requiresMonoAAC || job.audioChannelCount == 1
      else {
        job.state = .failed
        job.reason = "This recording isn’t compatible with the selected method."
        if !persist(job) { return }
        continue
      }
      if let asynchronous = adapter as? any AsynchronousTranscriptionReadiness {
        beginPreflight(job: job, methodID: methodID, adapter: asynchronous)
        continue
      }
      switch adapter.readiness(for: job.language) {
      case .waiting(let reason):
        job.state = .waiting
        job.reason = reason.message(for: job.language)
        if !persist(job) { return }
        continue
      case .ready: break
      }
      claim(job: job, methodID: methodID, adapter: adapter, effectiveValues: [:])
      return
    }
  }

  private func invalidateReadiness() {
    readinessGeneration += 1
    for task in readinessTasks.values { task.cancel() }
    readinessTasks.removeAll()
  }

  private func beginPreflight(
    job: QueueJob, methodID: String, adapter: any AsynchronousTranscriptionReadiness
  ) {
    let key = preflightKey(methodID: methodID, language: job.language)
    // Readiness is a property of the method/language, not of an individual
    // recording. Six queued recordings must not start six model verifications.
    guard readinessTasks[key] == nil else { return }
    let waitingJobs: [QueueJob]
    do {
      waitingJobs = try store.jobs().filter {
        $0.state == .ready && $0.language == job.language
          && settings.selectedMethodID(for: $0.language) == methodID
      }
    } catch {
      pauseQueue()
      return
    }
    let generation = readinessGeneration
    readinessTasks[key] = Task { [weak self] in
      let result = await adapter.preflight(for: job.language)
      guard let self, !Task.isCancelled, self.readinessGeneration == generation else { return }
      self.readinessTasks[key] = nil
      if case .waiting(let reason) = result.readiness {
        // Fan out only a negative result to the unchanged jobs that requested it.
        // A positive result is consumed by one claim and is never cached across attempts.
        for original in waitingJobs {
          guard self.isActive, self.pausedReason == nil,
            self.readinessGeneration == generation
          else { return }
          guard let current = try? self.store.jobs().first(where: { $0.id == original.id }),
            current == original,
            self.settings.selectedMethodID(for: current.language) == methodID
          else { continue }
          var waiting = current
          waiting.state = .waiting
          waiting.reason = reason.message(for: waiting.language)
          guard self.persist(waiting) else { return }
        }
        self.processNext()
        return
      }
      self.finishPreflight(job: job, methodID: methodID, adapter: adapter, result: result)
    }
  }

  private func preflightKey(methodID: String, language: CaptureLanguage) -> String {
    "\(methodID)|\(language.rawValue)"
  }

  private func finishPreflight(
    job: QueueJob, methodID: String, adapter: any AsynchronousTranscriptionReadiness,
    result: TranscriptionPreflight
  ) {
    guard isActive, pausedReason == nil else { return }
    guard settings.selectedMethodID(for: job.language) == methodID else {
      processNext()
      return
    }
    let current: QueueJob
    do {
      guard let found = try store.jobs().first(where: { $0.id == job.id }), found == job else {
        processNext()
        return
      }
      current = found
    } catch {
      pauseQueue()
      return
    }
    switch result.readiness {
    case .waiting(let reason):
      var waiting = current
      waiting.state = .waiting
      waiting.reason = reason.message(for: waiting.language)
      guard persist(waiting) else { return }
      processNext()
    case .ready:
      guard activeWork == nil else { return }
      claim(
        job: current, methodID: methodID, adapter: adapter, effectiveValues: result.effectiveValues)
    }
  }

  private func claim(
    job initial: QueueJob, methodID: String, adapter: any TranscriptionMethodAdapter,
    effectiveValues: [String: String]
  ) {
    var job = initial
    let base = settings.effectiveSettings(methodID: methodID, language: job.language)
    let snapshot = EffectiveTranscriptionSettings(
      values: base.values.merging(effectiveValues) { _, current in current },
      modelIdentity: base.modelIdentity, conversionIdentity: base.conversionIdentity)
    job.attemptGeneration += 1
    let attemptID = UUID()
    job.attemptID = attemptID
    job.selectedMethodID = methodID
    job.effectiveSettings = snapshot.values
    job.modelIdentity = snapshot.modelIdentity
    job.conversionIdentity = snapshot.conversionIdentity
    job.state = .transcribing
    job.reason = nil
    guard persist(job) else { return }
    let request = TranscriptionRequest(
      jobID: job.id, attemptID: attemptID, generation: job.attemptGeneration,
      language: job.language, settings: snapshot,
      destinationRevision: job.destinationRevision, bodyRevision: job.bodyRevision)
    let lease = TranscriptionWorkLease()
    activeWork = ActiveAttempt(
      jobID: job.id, generation: job.attemptGeneration, work: lease)
    let work = adapter.start(request) { [weak self] result in
      self?.settle(request: request, result: result)
    }
    lease.attach(work)
    guard activeWork?.jobID == job.id, activeWork?.generation == job.attemptGeneration else {
      return
    }
    timeoutTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: self.timeout)
      guard !Task.isCancelled else { return }
      self.timeoutReached(jobID: request.jobID, generation: request.generation)
    }
  }

  private func timeoutReached(jobID: String, generation: Int) {
    guard let activeWork, activeWork.jobID == jobID, activeWork.generation == generation else {
      return
    }
    self.activeWork?.invalidated = true
    mutate(jobID: jobID) { job in
      guard job.attemptGeneration == generation, job.state == .transcribing else { return }
      job.attemptGeneration += 1
      job.state = .failed
      job.reason = Self.timeoutReason
    }
    activeWork.work.cancel()
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private func settle(request: TranscriptionRequest, result: TranscriptionResult) {
    guard let activeWork, activeWork.jobID == request.jobID,
      activeWork.generation == request.generation
    else { return }
    timeoutTask?.cancel()
    timeoutTask = nil
    guard let job = try? store.jobs().first(where: { $0.id == request.jobID }) else {
      self.activeWork = nil
      pauseQueue()
      return
    }
    if job.state == .cancelling {
      self.activeWork = nil
      finishRemoval(jobID: request.jobID)
      processNext()
      return
    }
    if activeWork.invalidated {
      self.activeWork = nil
      processNext()
      return
    }
    // swiftlint:disable opening_brace
    if job.attemptGeneration == request.generation && job.attemptID == request.attemptID
      && job.state == .transcribing && job.language == request.language
      && job.effectiveSettings == request.settings.values
      && job.modelIdentity == request.settings.modelIdentity
      && job.conversionIdentity == request.settings.conversionIdentity
      && job.destinationRevision == request.destinationRevision
      && job.bodyRevision == request.bodyRevision
    {
      var settled = job
      switch result {
      case .success(let payload):
        do {
          try candidates.publish(payload, request: request, job: job)
        } catch TranscriptionCandidateFailure.invalidSource {
          do {
            try candidates.discard(job: job)
          } catch {
            self.activeWork = nil
            pauseQueue()
            return
          }
          settled.attemptID = nil
          settled.state = .failed
          settled.reason = TranscriptionFailure.audioUnreadable.message
          guard persist(settled) else {
            self.activeWork = nil
            return
          }
          self.activeWork = nil
          processNext()
          return
        } catch {
          self.activeWork = nil
          pauseQueue()
          return
        }
        settled.state = .resultReady
        settled.reason = nil
      case .failure(let reason):
        settled.attemptID = nil
        settled.state = .failed
        settled.reason = reason.message
      case .waiting(let reason):
        settled.attemptID = nil
        settled.state = .waiting
        settled.reason = reason.message(for: settled.language)
      }
      guard persist(settled) else {
        self.activeWork = nil
        return
      }
    } else {
      self.activeWork = nil
      reconcile()
      processNext()
      return
    }
    // swiftlint:enable opening_brace
    self.activeWork = nil
    processNext()
  }

  @discardableResult
  private func finishRemoval(jobID: String) -> Bool {
    do {
      guard let job = try store.jobs().first(where: { $0.id == jobID }),
        job.state == .removing || job.state == .cancelling
      else { return false }
      try receipts.removePrivateCapture(job: job)
      try store.remove(jobID: jobID)
      onChange?()
      return true
    } catch {
      pauseQueue()
      return false
    }
  }

  @discardableResult
  private func mutate(jobID: String, body: (inout QueueJob) -> Void) -> Bool {
    do {
      guard var job = try store.jobs().first(where: { $0.id == jobID }) else { return false }
      body(&job)
      try store.replace(job)
      onChange?()
      return true
    } catch {
      pauseQueue()
      return false
    }
  }

  private func persist(_ job: QueueJob) -> Bool {
    do {
      try store.replace(job)
      onChange?()
      return true
    } catch {
      pauseQueue()
      return false
    }
  }

  private func pauseQueue() {
    pausedReason = Self.pausedReason
    isActive = false
    onChange?()
  }
}

@MainActor
private final class TranscriptionWorkLease: TranscriptionWork {
  private var underlying: (any TranscriptionWork)?
  private var cancellationRequested = false

  func attach(_ work: any TranscriptionWork) {
    underlying = work
    if cancellationRequested { work.cancel() }
  }

  func cancel() {
    cancellationRequested = true
    underlying?.cancel()
  }
}

// swiftlint:enable file_length
