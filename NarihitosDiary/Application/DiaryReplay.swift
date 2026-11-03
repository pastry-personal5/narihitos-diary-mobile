import Foundation

struct DiaryReplayLease: Equatable, Sendable {
  let id: UUID
  let duration: Double
}

enum DiaryReplayEvent: Equatable, Sendable {
  case position(Double)
  case ended
  case paused
  case unavailable
}

enum DiaryReplayState: Equatable {
  case idle
  case loading
  case paused
  case playing
  case ended
  case unavailable
}

@MainActor
protocol DiaryReplayPort: AnyObject {
  var onEvent: (@MainActor (UUID, DiaryReplayEvent) -> Void)? { get set }
  func acquire(_ handle: CatalogItemHandle) async throws -> DiaryReplayLease
  func play(_ lease: DiaryReplayLease) throws
  func pause(_ lease: DiaryReplayLease)
  func seek(_ lease: DiaryReplayLease, to seconds: Double) throws
  func release(_ lease: DiaryReplayLease) async
}

@MainActor
final class DiaryReplayCoordinator {
  private let player: any DiaryReplayPort
  private var acquisition: Task<Void, Never>?
  private var releaseTask: Task<Void, Never>?
  private var lease: DiaryReplayLease?
  private var item: CatalogItemHandle?
  private var visibleItem: CatalogItemHandle?
  private var visibilityBound = false
  private var generation = UUID()
  private var foreground = false
  private var suspended = false
  private var stoppingCount = 0
  private var teardownPending = false
  private(set) var state: DiaryReplayState = .idle
  private(set) var elapsed: Double = 0
  private(set) var duration: Double = 0
  var onChange: (@MainActor () -> Void)?

  init(player: any DiaryReplayPort) {
    self.player = player
    player.onEvent = { [weak self] id, event in self?.receive(id, event: event) }
  }

  var hasActiveWork: Bool {
    acquisition != nil || releaseTask != nil || lease != nil || stoppingCount > 0 || teardownPending
  }

  func activate() { foreground = true }

  func setVisibleItem(_ handle: CatalogItemHandle?) {
    let changed = !visibilityBound || visibleItem != handle
    visibilityBound = true
    visibleItem = handle
    if changed, let item, item != handle { scheduleStop(for: item) }
  }

  func state(for handle: CatalogItemHandle) -> DiaryReplayState {
    if visibilityBound, visibleItem != handle { return .idle }
    if item == handle { return state }
    return stoppingCount > 0 ? .loading : .idle
  }
  func elapsed(for handle: CatalogItemHandle) -> Double { item == handle ? elapsed : 0 }
  func duration(for handle: CatalogItemHandle) -> Double { item == handle ? duration : 0 }

  func play(_ handle: CatalogItemHandle) {
    guard !visibilityBound || visibleItem == handle else { return }
    guard foreground, !suspended, releaseTask == nil, stoppingCount == 0, !teardownPending else {
      return
    }
    if item != nil, item != handle, lease != nil || acquisition != nil {
      failReplay()
      return
    }
    if let lease {
      resume(lease)
      return
    }
    guard acquisition == nil else { return }
    item = handle
    state = .loading
    onChange?()
    generation = UUID()
    let epoch = generation
    acquisition = Task { [self] in
      defer {
        acquisition = nil
        onChange?()
      }
      await acquire(handle, epoch: epoch)
    }
  }

  private func resume(_ lease: DiaryReplayLease) {
    do {
      if state == .ended {
        try player.seek(lease, to: 0)
        elapsed = 0
      }
      try player.play(lease)
      state = .playing
    } catch { failReplay() }
    onChange?()
  }

  private func acquire(_ handle: CatalogItemHandle, epoch: UUID) async {
    do {
      let acquired = try await player.acquire(handle)
      guard epoch == generation, !Task.isCancelled, foreground, !suspended else {
        await player.release(acquired)
        return
      }
      guard acquired.duration.isFinite, acquired.duration > 0 else {
        await player.release(acquired)
        throw DiaryEditIssue.unsupported
      }
      lease = acquired
      duration = acquired.duration
      elapsed = 0
      try player.play(acquired)
      state = .playing
    } catch {
      guard epoch == generation else { return }
      if let lease {
        self.lease = nil
        await player.release(lease)
      }
      if epoch == generation { state = .unavailable }
    }
  }

  func pause(for handle: CatalogItemHandle? = nil) {
    guard handle == nil || item == handle else { return }
    guard let lease else { return }
    player.pause(lease)
    state = .paused
    onChange?()
  }

  func seek(to seconds: Double, for handle: CatalogItemHandle? = nil) {
    guard handle == nil || item == handle else { return }
    guard let lease, seconds.isFinite, foreground, !suspended else { return }
    let value = min(max(seconds, 0), duration)
    do {
      try player.seek(lease, to: value)
      elapsed = value
      if value == duration {
        state = .ended
      } else if state == .ended {
        state = .paused
      }
    } catch { failReplay() }
    onChange?()
  }

  // swiftlint:disable opening_brace
  func stop(for handle: CatalogItemHandle? = nil, state finalState: DiaryReplayState = .idle) async
  {
    guard handle == nil || item == handle else { return }
    stoppingCount += 1
    defer {
      stoppingCount -= 1
      teardownPending = false
    }
    generation = UUID()
    acquisition?.cancel()
    state = finalState
    if finalState == .idle { item = nil }
    elapsed = 0
    duration = 0
    onChange?()
    if let acquisition { await acquisition.value }
    if let releaseTask {
      await releaseTask.value
      return
    }
    guard let lease else { return }
    self.lease = nil
    let task = Task { [player] in await player.release(lease) }
    releaseTask = task
    await task.value
    releaseTask = nil
    onChange?()
  }
  // swiftlint:enable opening_brace

  func deactivate() {
    foreground = false
    if let lease { player.pause(lease) }
    scheduleStop()
  }

  /// Expiry reports unavailable; it never releases the outstanding player,
  /// decoder, cache accessor, or session owner on the recorder's behalf.
  func stopForCapture(timeout: Duration = .seconds(10)) async -> Bool {
    if !hasActiveWork { return true }
    if stoppingCount == 0 { scheduleStop() }
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while hasActiveWork {
      guard ContinuousClock.now < deadline else { return false }
      do { try await Task.sleep(for: .milliseconds(25)) } catch { return false }
    }
    return true
  }

  func suspendForMaintenance() {
    suspended = true
    foreground = false
  }

  func endMaintenance() { suspended = false }

  private func receive(_ id: UUID, event: DiaryReplayEvent) {
    guard lease?.id == id, foreground, !suspended else { return }
    switch event {
    case .position(let value):
      guard value.isFinite else { return }
      elapsed = min(max(value, 0), duration)
    case .ended:
      elapsed = duration
      state = .ended
    case .paused: state = .paused
    case .unavailable: failReplay()
    }
    onChange?()
  }

  private func failReplay() {
    state = .unavailable
    guard !teardownPending else { return }
    teardownPending = true
    if let lease { player.pause(lease) }
    scheduleStop(state: .unavailable)
  }

  private func scheduleStop(for handle: CatalogItemHandle? = nil, state: DiaryReplayState = .idle) {
    stoppingCount += 1
    Task { [self] in
      await stop(for: handle, state: state)
      stoppingCount -= 1
      onChange?()
    }
  }
}
