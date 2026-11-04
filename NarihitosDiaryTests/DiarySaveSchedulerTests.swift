import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct DiarySaveSchedulerTests {
  @Test(arguments: [DiaryCommitWait.upload, .destination, .localData])
  func transientSaveWaitsRetryWithoutRetranscription(_ reason: DiaryCommitWait) async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    let clock = SaveRetryClock()
    var calls = 0
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      calls += 1
      if calls == 1 {
        queue.values[id]?.reason = reason.message
      } else {
        queue.values[id]?.state = .saved
      }
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 1 }
    clock.fireNext()
    await waitFor { queue.values[job.id]?.state == .saved && !scheduler.hasActiveWork }
    #expect(calls == 2)
    #expect(clock.delays == [.seconds(2)])
  }

  @Test func repeatedWaitsBackOffAndDoNotBlockAnotherJob() async throws {
    let queue = MemoryQueueStore()
    let waiting = try makeJob()
    let other = try makeJob()
    queue.values = [waiting.id: waiting, other.id: other]
    let clock = SaveRetryClock()
    var calls: [String: Int] = [:]
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      calls[id, default: 0] += 1
      if id == waiting.id {
        queue.values[id]?.reason = DiaryCommitWait.upload.message
      } else {
        queue.values[id]?.state = .saved
      }
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 1 && queue.values[other.id]?.state == .saved }
    #expect(!scheduler.hasActiveWork)
    for count in 2...6 {
      clock.fireNext()
      await waitFor { clock.delays.count == count }
    }
    #expect(clock.delays == [2, 5, 15, 30, 60, 60].map { .seconds($0) })
    #expect(calls[waiting.id] == 6)
    #expect(calls[other.id] == 1)
    #expect(queue.values[waiting.id]?.state == .readyToSave)
  }

  @Test func manualRetryBypassesDelayAndFencesTheOldTimer() async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    let clock = SaveRetryClock()
    var calls = 0
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      calls += 1
      queue.values[id]?.reason = DiaryCommitWait.upload.message
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 1 }
    scheduler.retry(job.id)
    await waitFor { clock.delays.count == 2 }
    #expect(calls == 2)
    clock.fireNext()  // The cancelled timer deliberately ignores cancellation.
    await drainTasks()
    #expect(calls == 2)
    #expect(clock.delays == [.seconds(2), .seconds(2)])
    clock.fireNext()
    await waitFor { calls == 3 }
  }

  @Test func inactivityAndMaintenanceStopTimersAndResumeFreshVerification() async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    let clock = SaveRetryClock()
    var calls = 0
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      calls += 1
      queue.values[id]?.reason = DiaryCommitWait.destination.message
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 1 }
    scheduler.pump(enabled: false)
    clock.fireNext()
    await drainTasks()
    #expect(calls == 1)
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 2 }
    #expect(calls == 2)
    scheduler.pump(enabled: false)
    clock.fireNext()
    await drainTasks()
    #expect(calls == 2)
  }

  @Test func inFlightOwnerPreventsOverlapsAcrossManualRetryAndReactivation() async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    var calls = 0
    var held: CheckedContinuation<Void, Never>?
    let scheduler = DiarySaveScheduler(queue: queue) { id in
      calls += 1
      await withCheckedContinuation { held = $0 }
      queue.values[id]?.state = .saved
    }
    scheduler.pump(enabled: true)
    await waitFor { held != nil }
    scheduler.retry(job.id)
    scheduler.pump(enabled: false)
    #expect(scheduler.hasActiveWork)
    scheduler.pump(enabled: true)
    scheduler.reset()
    scheduler.pump(enabled: true)
    await drainTasks()
    #expect(calls == 1)
    held?.resume()
    await waitFor { !scheduler.hasActiveWork }
    #expect(queue.values[job.id]?.state == .saved)
    scheduler.pump(enabled: false)
  }

  @Test func removingJobCannotBeRestartedByAStaleTimer() async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    let clock = SaveRetryClock()
    var calls = 0
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      calls += 1
      queue.values[id]?.reason = DiaryCommitWait.upload.message
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 1 }
    queue.values[job.id]?.state = .removing
    scheduler.cancel(job.id)
    clock.fireNext()
    scheduler.pump(enabled: true)
    await drainTasks()
    #expect(calls == 1)
    #expect(queue.values[job.id]?.state == .removing)
  }

  @Test func changedRevisionCancelsOldDelayAndUsesTheFreshJob() async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    let clock = SaveRetryClock()
    var revisions: [Int] = []
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      revisions.append(queue.values[id]?.destinationRevision ?? -1)
      queue.values[id]?.reason = DiaryCommitWait.upload.message
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 1 }
    queue.values[job.id]?.destinationRevision += 1
    scheduler.pump(enabled: true)
    await waitFor { clock.delays.count == 2 }
    clock.fireNext()
    await drainTasks()
    #expect(revisions == [job.destinationRevision, job.destinationRevision + 1])
    #expect(clock.delays == [.seconds(2), .seconds(2)])
  }

  @Test func recoveryAndFailedJobsNeverEnterAutomaticRetryLoops() async throws {
    let queue = MemoryQueueStore()
    var job = try makeJob()
    job.state = .failed
    queue.values[job.id] = job
    let clock = SaveRetryClock()
    var calls = 0
    let scheduler = DiarySaveScheduler(queue: queue, sleep: clock.sleep) { id in
      calls += 1
      queue.values[id]?.reason = "This diary pair needs review."
    }
    defer {
      scheduler.pump(enabled: false)
      clock.releaseAll()
    }
    scheduler.pump(enabled: true)
    await drainTasks()
    #expect(calls == 0)
    queue.values[job.id]?.state = .readyToSave
    scheduler.pump(enabled: true)
    await waitFor { calls == 1 && !scheduler.hasActiveWork }
    for _ in 0..<10 { scheduler.pump(enabled: true) }
    await drainTasks()
    #expect(calls == 1)
    #expect(clock.delays.isEmpty)
  }

  @Test func suspensionBeforeQueuedAttemptStartsPreventsProviderWork() async throws {
    let queue = MemoryQueueStore()
    let job = try makeJob()
    queue.values[job.id] = job
    var calls = 0
    let scheduler = DiarySaveScheduler(queue: queue) { _ in calls += 1 }
    scheduler.pump(enabled: true)
    scheduler.pump(enabled: false)
    await waitFor { !scheduler.hasActiveWork }
    #expect(calls == 0)
  }

  private func makeJob() throws -> QueueJob {
    QueueJob(
      receipt: QueueReceipt(
        id: try WorkspaceID.random(), startedAt: .now, language: .english,
        destinationReference: UUID(), installationBinding: "synthetic-installation",
        inspection: CaptureInspection(
          byteCount: 512, duration: 1, isMonoAAC: true, isPlayable: true,
          sampleRate: 44_100, channelCount: 1, codecIdentifier: nil,
          approximateBitRate: 64_000)),
      state: .readyToSave)
  }

  private func waitFor(_ predicate: () -> Bool) async {
    for _ in 0..<1_000 where !predicate() { await Task.yield() }
    #expect(predicate())
  }

  private func drainTasks() async {
    for _ in 0..<100 { await Task.yield() }
  }
}

/// Deliberately permits a cancelled sleeper to return so tests exercise the
/// scheduler's cancellation/identity fences independently of Task.sleep.
@MainActor
private final class SaveRetryClock {
  private var pending: [CheckedContinuation<Void, Never>] = []
  private(set) var delays: [Duration] = []

  func sleep(_ duration: Duration) async throws {
    delays.append(duration)
    await withCheckedContinuation { pending.append($0) }
  }

  func fireNext() {
    if !pending.isEmpty { pending.removeFirst().resume() }
  }

  func releaseAll() {
    while !pending.isEmpty { fireNext() }
  }
}
