import Foundation

/// Schedules saves independently of transcription. The commit owner retains all
/// file/version authority and must settle before another attempt can start.
@MainActor
final class DiarySaveScheduler {
  private let queue: any QueueStorePort
  private let attempt: @MainActor (String) async -> Void
  private let sleep: @MainActor (Duration) async throws -> Void
  private var tasks: [String: Task<Void, Never>] = [:]
  private var attempted: [String: QueueJob] = [:]
  private var retries: [String: Task<Void, Never>] = [:]
  private var retryTokens: [String: UUID] = [:]
  private var retryCounts: [String: Int] = [:]
  private var enabled = false
  var onChange: (@MainActor () -> Void)?
  var hasActiveWork: Bool { !tasks.isEmpty }

  init(
    queue: any QueueStorePort,
    sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    attempt: @escaping @MainActor (String) async -> Void
  ) {
    self.queue = queue
    self.sleep = sleep
    self.attempt = attempt
  }

  func reset() {
    for task in retries.values { task.cancel() }
    retries.removeAll()
    retryTokens.removeAll()
    retryCounts.removeAll()
    attempted.removeAll()
  }

  func pump(enabled: Bool) {
    if !enabled || !self.enabled { reset() }
    self.enabled = enabled
    guard enabled else { return }
    guard let jobs = try? queue.jobs() else {
      self.enabled = false
      reset()
      return
    }
    let ready = jobs.filter { $0.state == .readyToSave }
    let readyIDs = Set(ready.map(\.id))
    for id in Array(retries.keys) where !readyIDs.contains(id) { cancelRetry(id) }
    attempted = attempted.filter { readyIDs.contains($0.key) }
    retryCounts = retryCounts.filter { readyIDs.contains($0.key) }
    for job in ready {
      guard tasks[job.id] == nil else { continue }
      if let previous = attempted[job.id], previous != job {
        cancelRetry(job.id)
        retryCounts[job.id] = nil
      }
      guard retries[job.id] == nil, attempted[job.id] != job else { continue }
      attempted[job.id] = job
      tasks[job.id] = Task { [weak self, attempt] in
        guard !Task.isCancelled, self?.canStart(job) == true else {
          self?.settled(job)
          return
        }
        await attempt(job.id)
        self?.settled(job)
      }
    }
  }

  func retry(_ id: String) {
    cancelRetry(id)
    attempted[id] = nil
    retryCounts[id] = nil
    pump(enabled: enabled)
  }

  func cancel(_ id: String) {
    cancelRetry(id)
    attempted[id] = nil
    retryCounts[id] = nil
    tasks[id]?.cancel()
  }

  private func canStart(_ job: QueueJob) -> Bool {
    enabled && (try? queue.jobs().first(where: { $0.id == job.id })) == job
  }

  private func settled(_ initial: QueueJob) {
    tasks[initial.id] = nil
    defer {
      onChange?()
      pump(enabled: enabled)
    }
    guard let job = try? queue.jobs().first(where: { $0.id == initial.id }),
      job.attemptID == initial.attemptID,
      job.attemptGeneration == initial.attemptGeneration,
      job.destinationReference == initial.destinationReference,
      job.destinationRevision == initial.destinationRevision,
      job.bodyRevision == initial.bodyRevision,
      job.installationBinding == initial.installationBinding
    else { return }
    attempted[job.id] = job
    if enabled, Self.canRetry(job) { scheduleRetry(job) }
  }

  private static func canRetry(_ job: QueueJob) -> Bool {
    job.state == .readyToSave && job.conflictResolution == nil
      && [DiaryCommitWait.upload, .destination, .localData].contains { $0.message == job.reason }
  }

  private func scheduleRetry(_ job: QueueJob) {
    let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)]
    let index = min(retryCounts[job.id] ?? 0, delays.count - 1)
    retryCounts[job.id] = min(index + 1, delays.count - 1)
    let token = UUID()
    retryTokens[job.id] = token
    retries[job.id] = Task { [weak self, sleep] in
      do { try await sleep(delays[index]) } catch { return }
      guard !Task.isCancelled, let self, self.retryTokens[job.id] == token else { return }
      self.retries[job.id] = nil
      self.retryTokens[job.id] = nil
      guard self.enabled else { return }
      if let current = try? self.queue.jobs().first(where: { $0.id == job.id }), current == job {
        self.attempted[job.id] = nil
      }
      self.pump(enabled: self.enabled)
    }
  }

  private func cancelRetry(_ id: String) {
    retries.removeValue(forKey: id)?.cancel()
    retryTokens[id] = nil
  }
}
