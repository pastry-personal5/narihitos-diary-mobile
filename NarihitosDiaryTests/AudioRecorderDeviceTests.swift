import AVFAudio
import AVFoundation
import Foundation
import Testing

@testable import NarihitosDiary

// swift-format and SwiftLint disagree on trailing commas in multiline collections.
// swiftlint:disable trailing_comma

struct AppleAudioRecorderStartTests {
  @Test func protectsOutputBeforePreparingAndRecording() throws {
    var events: [String] = []

    try AppleAudioRecorderStart.run(
      protect: { events.append("protect") },
      prepare: {
        events.append("prepare")
        return true
      },
      record: {
        events.append("record")
        return true
      })

    #expect(events == ["protect", "prepare", "record"])
  }

  @Test func preparationFailureDoesNotStartRecording() {
    var events: [String] = []

    #expect(throws: CaptureGateFailure.storage) {
      try AppleAudioRecorderStart.run(
        protect: { events.append("protect") },
        prepare: {
          events.append("prepare")
          return false
        },
        record: {
          events.append("record")
          return true
        })
    }

    #expect(events == ["protect", "prepare"])
  }
}

// This test is a target-phone diagnostic gate. The simulator has no production
// microphone path, so its normal validation run intentionally has no work here.
@MainActor
struct AudioRecorderDeviceTests {
  @Test func plainAACRecorderProducesMoreThanEncoderPriming() async throws {
    #if targetEnvironment(simulator)
      return
    #else
      #expect(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
      let url = FileManager.default.temporaryDirectory.appending(
        path: "plain-aac-recorder-\(UUID().uuidString).m4a")
      defer { try? FileManager.default.removeItem(at: url) }
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .default)
      try session.setActive(true)
      defer { try? session.setActive(false) }
      let recorder = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 64_000,
        ])
      #expect(recorder.prepareToRecord())
      #expect(recorder.record())
      try await Task.sleep(for: .seconds(2))
      recorder.stop()
      let recorded = try AVAudioFile(forReading: url)
      #expect(recorded.length > 44_100)
    #endif
  }

  @Test func modernAudioTapReceivesFrames() async throws {
    #if targetEnvironment(simulator)
      return
    #else
      #expect(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement)
      try session.setActive(true)
      defer { try? session.setActive(false) }

      let engine = AVAudioEngine()
      let input = engine.inputNode
      let counter = AudioFrameCounter()
      try input.installAudioTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
        counter.add(Int(buffer.frameLength))
      }
      defer { input.removeTap(onBus: 0) }
      engine.prepare()
      try engine.start()
      try await Task.sleep(for: .seconds(2))
      engine.stop()
      #expect(counter.value > 44_100)
    #endif
  }

  @Test func protectedAACRecorderProducesMoreThanEncoderPriming() async throws {
    #if targetEnvironment(simulator)
      return
    #else
      #expect(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
      let directory = FileManager.default.temporaryDirectory.appending(
        path: "protected-aac-recorder-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: directory) }
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: directory.path)
      let url = directory.appending(path: "recording.m4a")
      #expect(FileManager.default.createFile(atPath: url.path, contents: nil))

      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      defer { try? session.setActive(false) }

      let recorder = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 64_000,
        ])
      try AppleAudioRecorderStart.run(
        protect: {
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          var mutableURL = url
          try mutableURL.setResourceValues(values)
          try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        },
        prepare: recorder.prepareToRecord,
        record: recorder.record)
      try await Task.sleep(for: .seconds(2))
      recorder.stop()

      let recorded = try AVAudioFile(forReading: url)
      #expect(recorded.length > 44_100)
      #expect(
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      #expect(
        (attributes[.protectionKey] as? FileProtectionType) == .completeUnlessOpen)
    #endif
  }

  @Test func productionWorkspaceAACRecorderProducesMoreThanEncoderPriming() async throws {
    #if targetEnvironment(simulator)
      return
    #else
      let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "capture-device-test-\(UUID().uuidString)", directoryHint: .isDirectory)
      defer { try? FileManager.default.removeItem(at: root) }
      let files = CapturePrivateFiles(root: root)
      let reference = try files.saveSnapshot(
        StoredDestinationRecord(
          id: DestinationID.make().rawValue, displayName: "Synthetic",
          bookmark: Data([1]), identityArchive: Data([2]), disclosureAcknowledged: true))
      let identity = CaptureIdentity(
        id: try WorkspaceID.random(), startedAt: Date(), language: .english,
        destinationReference: reference)
      try files.createWorkspace(identity)
      let url = try files.createProtectedAudio(id: identity.id)

      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      defer { try? session.setActive(false) }
      let recorder = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 64_000,
        ])
      recorder.isMeteringEnabled = true
      try AppleAudioRecorderStart.run(
        protect: { try files.verifyOpenAudio(id: identity.id) },
        prepare: recorder.prepareToRecord,
        record: recorder.record)
      try await Task.sleep(for: .milliseconds(100))
      _ = files.reconcile()
      for _ in 0..<8 {
        try await Task.sleep(for: .milliseconds(250))
        recorder.updateMeters()
        _ = recorder.averagePower(forChannel: 0)
        _ = files.audioBytes(id: identity.id)
      }
      recorder.stop()
      let inspection = try files.inspectAudio(id: identity.id)
      #expect(inspection.duration > 1)
    #endif
  }
}

private final class AudioFrameCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var frames = 0

  func add(_ count: Int) {
    lock.lock()
    frames += count
    lock.unlock()
  }

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return frames
  }
}

// swiftlint:enable trailing_comma
