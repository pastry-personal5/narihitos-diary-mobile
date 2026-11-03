import AVFAudio
import Foundation
import Testing

@testable import NarihitosDiary

// swift-format wraps async result declarations and multiline collections.
// swiftlint:disable opening_brace trailing_comma

@MainActor
@Suite(.serialized)
struct DiaryNativeReplayTests {
  @Test func nativePlaybackUsesProtectedLeaseAndNeverModifiesLegacySource() async throws {
    let fixture = try await NativeReplayFixture.make()
    defer { fixture.close() }
    let originalAudio = try Data(contentsOf: fixture.audio)
    let originalMarkdown = try Data(contentsOf: fixture.markdown)
    let files = await fixture.cache.files
    let lease = try await fixture.player.acquire(fixture.handle)
    do {
      #expect(lease.duration > 1.9 && lease.duration < 2.2)
      #expect(fixture.ownership.owner == nil)
      let audio = try files.directory(lease.id).appending(path: "audio.m4a")
      try DiaryFixtureProtection().verify(audio)
      #expect(
        try audio.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
      try await exercisePlayback(fixture, lease: lease)
    } catch {
      await fixture.player.release(lease)
      throw error
    }
    await fixture.player.release(lease)
    #expect(fixture.ownership.owner == nil)
    #expect(try PurgeFileTree.isEmpty(files.root))
    #expect(try Data(contentsOf: fixture.audio) == originalAudio)
    #expect(try Data(contentsOf: fixture.markdown) == originalMarkdown)
  }

  private func exercisePlayback(_ fixture: NativeReplayFixture, lease: DiaryReplayLease)
    async throws
  {
    let events = NativeReplayEvents()
    fixture.player.onEvent = { id, event in if id == lease.id { events.values.append(event) } }
    try fixture.player.play(lease)
    #expect(fixture.ownership.owner?.role == .replay)
    try await wait { events.lastPosition > 0 }
    fixture.player.pause(lease)
    #expect(fixture.ownership.owner == nil)
    let pausedPosition = events.lastPosition
    try await Task.sleep(for: .milliseconds(300))
    #expect(events.lastPosition == pausedPosition)
    try fixture.player.seek(lease, to: lease.duration + 10)
    #expect(events.values.last == .ended)
    #expect(fixture.ownership.owner == nil)
    events.values.removeAll()
    try fixture.player.seek(lease, to: -10)
    #expect(events.lastPosition == 0)
    try fixture.player.play(lease)
    try await wait { events.values.contains(.ended) }
    #expect(fixture.ownership.owner == nil)
  }

  @Test func injectedNativeNotificationsPauseAndNeverAutomaticallyResume() async throws {
    let fixture = try await NativeReplayFixture.make()
    defer { fixture.close() }
    let lease = try await fixture.player.acquire(fixture.handle)
    do {
      let events = NativeReplayEvents()
      fixture.player.onEvent = { _, event in events.values.append(event) }
      try fixture.player.play(lease)
      NotificationCenter.default.post(
        name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
        userInfo: [AVAudioSessionInterruptionTypeKey: UInt(1)])
      #expect(events.values.last == .paused)
      #expect(fixture.ownership.owner == nil)
      NotificationCenter.default.post(
        name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
        userInfo: [AVAudioSessionInterruptionTypeKey: UInt(0)])
      #expect(fixture.ownership.owner == nil)
      try fixture.player.play(lease)
      NotificationCenter.default.post(
        name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
        userInfo: [
          AVAudioSessionRouteChangeReasonKey:
            AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        ])
      #expect(events.values.last == .paused)
      #expect(fixture.ownership.owner == nil)
      try fixture.player.play(lease)
      NotificationCenter.default.post(
        name: AVAudioSession.mediaServicesWereResetNotification,
        object: AVAudioSession.sharedInstance())
      #expect(events.values.last == .unavailable)
      #expect(fixture.ownership.owner == nil)
    } catch {
      await fixture.player.release(lease)
      throw error
    }
    await fixture.player.release(lease)
  }

  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw DiaryEditIssue.unavailable }
      try await Task.sleep(for: .milliseconds(25))
    }
  }
}

@MainActor
private final class NativeReplayEvents {
  var values: [DiaryReplayEvent] = []
  var lastPosition: Double {
    values.compactMap { if case .position(let value) = $0 { value } else { nil } }.last ?? 0
  }
}

@MainActor
private struct NativeReplayFixture {
  let disk: PurgeDiskFixture
  let catalog: AppleAssetCatalog
  let cache: DiaryReplayCache
  let ownership: AudioSessionOwnership
  let player: AppleDiaryReplayPlayer
  let handle: CatalogItemHandle
  let audio: URL
  let markdown: URL

  static func make() async throws -> NativeReplayFixture {
    let disk = try PurgeDiskFixture()
    do {
      let source = try DiaryCatalogHandlerTests().makeLegacy()
      defer { try? FileManager.default.removeItem(at: source.root) }
      try writeSilence(source.audio)
      try FileManager.default.copyItem(
        at: source.root.appending(path: "2026"), to: disk.platform.url.appending(path: "2026"))
      var registry = CatalogAssetRegistry()
      registry.register(DiaryCatalogHandler())
      let catalog = AppleAssetCatalog(destination: disk.destination, registry: registry)
      guard case .ready(_, let cursor) = await catalog.begin() else {
        throw DiaryEditIssue.unavailable
      }
      let handle = try await firstHandle(catalog, cursor: cursor)
      let cache = DiaryReplayCache(
        root: disk.support.appending(path: "PrivateWorkspaces/DiaryReplay"),
        protection: DiaryFixtureProtection())
      let ownership = AudioSessionOwnership(platform: AppleAudioSessionConfiguration())
      let player = AppleDiaryReplayPlayer(
        catalog: catalog, destination: disk.destination, ownership: ownership, cache: cache)
      let directory = source.candidate.components.dropLast().reduce(disk.platform.url) {
        $0.appendingPathComponent($1)
      }
      let markdown = directory.appending(path: source.markdown.lastPathComponent)
      let audio = markdown.deletingPathExtension().appendingPathExtension("assets")
        .appending(path: "synthetic.m4a")
      return NativeReplayFixture(
        disk: disk, catalog: catalog, cache: cache, ownership: ownership, player: player,
        handle: handle, audio: audio, markdown: markdown)
    } catch {
      disk.close()
      throw error
    }
  }

  private static func firstHandle(_ catalog: AppleAssetCatalog, cursor: CatalogCursor) async throws
    -> CatalogItemHandle
  {
    var next: CatalogCursor? = cursor
    while let cursor = next {
      let page = try await catalog.page(cursor)
      if let handle = page.summaries.first?.handle { return handle }
      next = page.continuation
    }
    throw DiaryEditIssue.unavailable
  }

  private static func writeSilence(_ url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    buffer.floatChannelData?[0].initialize(repeating: 0, count: 44_100)
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
      ])
    for _ in 0..<2 { try writer.write(from: buffer) }
  }

  func close() {
    catalog.end()
    disk.close()
  }
}

// swiftlint:enable opening_brace trailing_comma
