import AVFAudio
import Foundation
import UIKit

// swift-format's multiline closure and collection layout differs from SwiftLint.
// swiftlint:disable closure_parameter_position trailing_comma

/// Initialization does bounded-file I/O on a utility task. After construction,
/// ownership transfers once to the main actor; the worker never touches it again.
private final class PreparedReplayPlayer: @unchecked Sendable {
  let value: AVAudioPlayer
  init(url: URL) throws { value = try AVAudioPlayer(contentsOf: url) }
}

private final class ReplayPlayerDelegate: NSObject, AVAudioPlayerDelegate {
  let id: UUID
  let event: @Sendable (UUID, DiaryReplayEvent) -> Void
  init(id: UUID, event: @escaping @Sendable (UUID, DiaryReplayEvent) -> Void) {
    self.id = id
    self.event = event
  }
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    event(id, flag ? .ended : .unavailable)
  }
  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    event(id, .unavailable)
  }
}

private final class ReplaySessionObservers {
  var tokens: [NSObjectProtocol] = []
  deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

@MainActor
final class AppleDiaryReplayPlayer: DiaryReplayPort {
  var onEvent: (@MainActor (UUID, DiaryReplayEvent) -> Void)?
  private let catalog: AppleAssetCatalog
  private let destination: AppleDestinationService
  private let ownership: AudioSessionOwnership
  private let cache: DiaryReplayCache
  private var player: AVAudioPlayer?
  private var delegate: ReplayPlayerDelegate?
  private var lease: DiaryReplayLease?
  private var token: AudioSessionToken?
  private var timer: Task<Void, Never>?
  private var acquiring = false
  private let observers = ReplaySessionObservers()

  init(
    catalog: AppleAssetCatalog, destination: AppleDestinationService,
    ownership: AudioSessionOwnership, cache: DiaryReplayCache = DiaryReplayCache()
  ) {
    self.catalog = catalog
    self.destination = destination
    self.ownership = ownership
    self.cache = cache
    observeSession()
  }

  func acquire(_ handle: CatalogItemHandle) async throws -> DiaryReplayLease {
    guard !acquiring, lease == nil, !ownership.captureReserved,
      ownership.owner?.role != .recording, UIApplication.shared.isProtectedDataAvailable
    else { throw DiaryEditIssue.busy }
    acquiring = true
    defer { acquiring = false }
    let id = UUID()
    do {
      try await cache.reconcile()
      let binding = try await catalog.actionBinding(handle)
      let files = cache.files
      let copied = try await destination.withCommittedDestination(binding.destination) { root in
        let facts = try await CommittedDiaryResource.coordinated(binding.resource, root: root) {
          root, control in
          try CommittedDiaryResource.inspect(binding.resource, root: root, control: control)
        }
        let directory = try await cache.prepare(id, bytes: facts.audioBytes)
        _ = try await CommittedDiaryResource.coordinated(binding.resource, root: root) {
          root, control in
          let before = try CommittedDiaryResource.inspect(
            binding.resource, root: root, control: control)
          guard before.version == facts.version else { throw DiaryEditIssue.changed }
          try files.copyAudio(
            root: root, components: facts.audioComponents,
            expected: facts.audioVersion, to: directory, control: control)
          _ = try CommittedDiaryResource.inspect(binding.resource, root: root, control: control)
          return true
        }
        return facts
      }
      let duration = try await cache.validate(
        id, digest: copied.version.audioDigest, maximumDuration: copied.snippet == nil ? 3_600 : 301
      )
      let prepared = try await preparePlayer(id)
      try Task.checkCancellation()
      guard !ownership.captureReserved, ownership.owner?.role != .recording,
        prepared.value.duration.isFinite, abs(prepared.value.duration - duration) < 1
      else { throw DiaryEditIssue.changed }
      let lease = DiaryReplayLease(id: id, duration: duration)
      self.lease = lease
      player = prepared.value
      delegate = ReplayPlayerDelegate(id: id) { [weak self] id, event in
        Task { @MainActor [weak self] in self?.receive(id, event: event) }
      }
      player?.delegate = delegate
      return lease
    } catch {
      try? await cache.remove(id)
      throw error
    }
  }

  private func preparePlayer(_ id: UUID) async throws -> PreparedReplayPlayer {
    let directory = try cache.files.directory(id)
    return try await Task.detached(priority: .utility) {
      try PreparedReplayPlayer(url: directory.appending(path: "audio.m4a"))
    }.value
  }

  func play(_ lease: DiaryReplayLease) throws {
    guard self.lease == lease, let player else { throw DiaryEditIssue.changed }
    if token == nil { token = try ownership.acquire(.replay) }
    guard player.play() else {
      if let token { ownership.release(token) }
      token = nil
      throw DiaryEditIssue.unavailable
    }
    timer?.cancel()
    timer = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        guard let self, self.lease == lease, let player = self.player else { return }
        onEvent?(lease.id, .position(player.currentTime))
      }
    }
  }

  func pause(_ lease: DiaryReplayLease) {
    guard self.lease == lease else { return }
    player?.pause()
    timer?.cancel()
    timer = nil
    if let token { ownership.release(token) }
    token = nil
  }

  func seek(_ lease: DiaryReplayLease, to seconds: Double) throws {
    guard self.lease == lease, let player, seconds.isFinite else { throw DiaryEditIssue.changed }
    let position = min(max(seconds, 0), lease.duration)
    if position == lease.duration {
      // AVAudioPlayer can wrap an exact-duration seek back to zero. Keep the
      // endpoint stopped; only a subsequent explicit Play may restart it.
      pause(lease)
      player.currentTime = 0
      onEvent?(lease.id, .ended)
      return
    }
    player.currentTime = position
    onEvent?(lease.id, .position(player.currentTime))
  }

  func release(_ lease: DiaryReplayLease) async {
    guard self.lease == lease else { return }
    pause(lease)
    player?.stop()
    player?.delegate = nil
    player = nil
    delegate = nil
    self.lease = nil
    try? await cache.remove(lease.id)
  }

  private func receive(_ id: UUID, event: DiaryReplayEvent) {
    guard let lease, lease.id == id else { return }
    if event == .ended || event == .unavailable { pause(lease) }
    onEvent?(id, event)
  }

  private func observeSession() {
    let center = NotificationCenter.default
    for name in [
      AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification,
    ] {
      observers.tokens.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
          let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == 1
          let reset = notification.name == AVAudioSession.mediaServicesWereResetNotification
          guard began || reset else { return }
          MainActor.assumeIsolated { self?.sessionPaused(reset: reset) }
        })
    }
    observers.tokens.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] notification in
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        guard raw != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
        MainActor.assumeIsolated { self?.sessionPaused(reset: false) }
      })
  }

  private func sessionPaused(reset: Bool) {
    guard let lease else { return }
    pause(lease)
    onEvent?(lease.id, reset ? .unavailable : .paused)
  }
}

// swiftlint:enable closure_parameter_position trailing_comma
