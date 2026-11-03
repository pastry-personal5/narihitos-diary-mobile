import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
private final class TestAudioSession: AudioSessionConfigurationPort {
  var activations: [AudioSessionRole] = []
  var deactivations = 0
  var failActivation = false
  func activate(_ role: AudioSessionRole) throws {
    activations.append(role)
    if failActivation { throw DiaryEditIssue.unavailable }
  }
  func deactivate() throws { deactivations += 1 }
}

@MainActor
final class TestReplayPlayer: DiaryReplayPort {
  var onEvent: (@MainActor (UUID, DiaryReplayEvent) -> Void)?
  var acquired = DiaryReplayLease(id: UUID(), duration: 60)
  var acquisition: CheckedContinuation<Void, Never>?
  var holdAcquisition = false
  var playCount = 0
  var acquireCount = 0
  var failPlay = false
  var pauseCount = 0
  var releaseCount = 0
  var positions: [Double] = []
  func acquire(_ handle: CatalogItemHandle) async throws -> DiaryReplayLease {
    acquireCount += 1
    if holdAcquisition { await withCheckedContinuation { acquisition = $0 } }
    return acquired
  }
  func play(_ lease: DiaryReplayLease) throws {
    playCount += 1
    if failPlay { throw DiaryEditIssue.unavailable }
  }
  func pause(_ lease: DiaryReplayLease) { pauseCount += 1 }
  func seek(_ lease: DiaryReplayLease, to seconds: Double) throws { positions.append(seconds) }
  func release(_ lease: DiaryReplayLease) async { releaseCount += 1 }
}

@MainActor
struct DiaryReplayTests {
  private var handle: CatalogItemHandle {
    CatalogItemHandle(
      session: CatalogSessionID(), resource: UUID(), version: UUID(), kind: "ndm.diary-snippet")
  }

  @Test func staleReplayReleaseCannotDeactivateCapture() throws {
    let platform = TestAudioSession()
    let ownership = AudioSessionOwnership(platform: platform)
    let replay = try ownership.acquire(.replay)
    ownership.reserveCapture()
    #expect(throws: DiaryEditIssue.busy) { try ownership.acquire(.recording) }
    ownership.release(replay)
    let recording = try ownership.acquire(.recording)
    let count = platform.deactivations
    ownership.release(replay)
    #expect(platform.deactivations == count)
    #expect(ownership.owner == recording)
    #expect(throws: DiaryEditIssue.busy) { try ownership.acquire(.replay) }
    ownership.release(recording)
    #expect(ownership.owner == nil)
  }

  @Test func captureReservationPreventsReplayAndFailureReleasesOwnership() throws {
    let platform = TestAudioSession()
    let ownership = AudioSessionOwnership(platform: platform)
    ownership.reserveCapture()
    #expect(throws: DiaryEditIssue.busy) { try ownership.acquire(.replay) }
    platform.failActivation = true
    #expect(throws: DiaryEditIssue.unavailable) { try ownership.acquire(.recording) }
    #expect(ownership.owner == nil)
    #expect(!ownership.captureReserved)
    platform.failActivation = false
    #expect(try ownership.acquire(.replay).role == .replay)
  }

  @Test func replayStartsOnlyExplicitlyAndRetainsPositionAcrossPause() async {
    let handle = self.handle
    let player = TestReplayPlayer()
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    #expect(replay.state == .idle)
    #expect(player.playCount == 0)
    replay.play(handle)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    #expect(replay.state == .playing)
    replay.seek(to: 75)
    #expect(replay.elapsed == 60)
    #expect(replay.state == .ended)
    replay.seek(to: -20)
    #expect(replay.elapsed == 0)
    #expect(replay.state == .paused)
    replay.seek(to: 20)
    replay.pause()
    #expect(replay.elapsed == 20)
    replay.play(handle)
    #expect(replay.elapsed == 20)
    #expect(player.playCount == 2)
    player.onEvent?(player.acquired.id, .ended)
    #expect(replay.state == .ended)
    replay.play(handle)
    #expect(player.positions.last == 0)
    #expect(replay.elapsed == 0)
    await replay.stop()
    #expect(player.releaseCount == 1)
    #expect(!replay.hasActiveWork)
  }

  @Test func cancelledAcquisitionRetainsOwnershipUntilRelinquishmentAndNeverAutoplays() async {
    let handle = self.handle
    let player = TestReplayPlayer()
    player.holdAcquisition = true
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    replay.play(handle)
    for _ in 0..<1_000 where player.acquisition == nil { await Task.yield() }
    let stop = Task { await replay.stop() }
    for _ in 0..<10 { await Task.yield() }
    #expect(replay.hasActiveWork)
    replay.play(handle)
    #expect(player.playCount == 0)
    player.acquisition?.resume()
    await stop.value
    #expect(player.playCount == 0)
    #expect(player.releaseCount == 1)
    #expect(replay.state == .idle)
    #expect(!replay.hasActiveWork)
  }

  @Test func obsoleteEventsAndNonfiniteSeeksDoNotAffectCurrentReplay() async {
    let player = TestReplayPlayer()
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    replay.play(handle)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    replay.seek(to: .infinity)
    player.onEvent?(UUID(), .position(50))
    #expect(replay.elapsed == 0)
    player.onEvent?(player.acquired.id, .paused)
    #expect(replay.state == .paused)
    #expect(player.playCount == 1)
    replay.deactivate()
    for _ in 0..<1_000 where replay.hasActiveWork { await Task.yield() }
    player.onEvent?(player.acquired.id, .position(50))
    #expect(replay.elapsed == 0)
    #expect(replay.state == .idle)
  }

  @Test func mediaFailureReleasesTheOldPlayerAndRequiresExplicitNewPlay() async {
    let handle = self.handle
    let player = TestReplayPlayer()
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    replay.play(handle)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    let oldID = player.acquired.id
    player.onEvent?(oldID, .unavailable)
    for _ in 0..<1_000 where replay.hasActiveWork { await Task.yield() }
    #expect(replay.state == .unavailable)
    #expect(player.releaseCount == 1)
    #expect(player.acquireCount == 1)
    player.acquired = DiaryReplayLease(id: UUID(), duration: 45)
    replay.play(handle)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    #expect(player.acquireCount == 2)
    #expect(replay.state == .playing)
    player.onEvent?(oldID, .position(40))
    #expect(replay.elapsed == 0)
    await replay.stop()
  }

  @Test func failedFirstPlayDoesNotLeakAnAcquiredLease() async {
    let player = TestReplayPlayer()
    player.failPlay = true
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    replay.play(handle)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    #expect(replay.state == .unavailable)
    #expect(!replay.hasActiveWork)
    #expect(player.releaseCount == 1)
  }

  @Test func oldDetailCannotPlayPauseSeekOrTearDownAnotherDetailsAudio() async {
    let first = handle
    let second = handle
    let player = TestReplayPlayer()
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    replay.play(first)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    #expect(replay.state(for: second) == .idle)
    #expect(replay.duration(for: second) == 0)
    replay.play(second)
    for _ in 0..<1_000 where replay.hasActiveWork { await Task.yield() }
    player.acquired = DiaryReplayLease(id: UUID(), duration: 45)
    replay.play(second)
    for _ in 0..<1_000 where replay.state == .loading { await Task.yield() }
    replay.setVisibleItem(second)
    replay.play(first)
    await replay.stop(for: first)
    replay.pause(for: first)
    replay.seek(to: 30, for: first)
    #expect(replay.state(for: second) == .playing)
    #expect(replay.elapsed(for: second) == 0)
    #expect(player.acquireCount == 2)
    await replay.stop(for: second)
  }

  @Test func captureWaitExpiresWithoutReleasingUnsettledReplayOrStartingDuplicateStops() async {
    let player = TestReplayPlayer()
    player.holdAcquisition = true
    let replay = DiaryReplayCoordinator(player: player)
    replay.activate()
    replay.play(handle)
    for _ in 0..<1_000 where player.acquisition == nil { await Task.yield() }
    #expect(await !replay.stopForCapture(timeout: .milliseconds(1)))
    #expect(replay.hasActiveWork)
    #expect(await !replay.stopForCapture(timeout: .milliseconds(1)))
    #expect(player.acquireCount == 1)
    #expect(player.releaseCount == 0)
    player.acquisition?.resume()
    for _ in 0..<1_000 where replay.hasActiveWork { await Task.yield() }
    #expect(player.releaseCount == 1)
    #expect(await replay.stopForCapture(timeout: .milliseconds(1)))
  }
}
