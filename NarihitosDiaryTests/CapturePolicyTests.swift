import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct CapturePolicyTests {
  @Test func capturePolicyKeepsPlatformTypesOutsideApplication() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
      contentsOf: root.appending(path: "NarihitosDiary/Application/CapturePolicy.swift"),
      encoding: .utf8)
    for forbidden in ["AVFAudio", "AVFoundation", "SwiftUI", "UIKit", "URL", "bookmark"] {
      #expect(!source.contains("import \(forbidden)"))
    }
    #expect(!source.contains("URL"))
    #expect(!source.contains("bookmark"))
  }

  @Test func captureInspectionRejectsOverlongAndUnsupportedAudio() {
    let accepted = CaptureInspection(
      byteCount: 64 * 1_024 * 1_024, duration: 301,
      isMonoAAC: true, isPlayable: true)
    #expect(accepted.isAccepted)
    let overlong = CaptureInspection(
      byteCount: accepted.byteCount, duration: 301.001,
      isMonoAAC: true, isPlayable: true)
    #expect(!overlong.isAccepted)
    let unsupported = CaptureInspection(
      byteCount: 1_024, duration: 1, isMonoAAC: false, isPlayable: true)
    #expect(!unsupported.isAccepted)
    let unreadable = CaptureInspection(
      byteCount: 1_024, duration: 1, isMonoAAC: true, isPlayable: false)
    #expect(!unreadable.isAccepted)
  }

  @Test func pendingReviewActionOpensAllRecoveryDestination() {
    let model = AppModel()
    model.reviewPendingRecordings()
    #expect(model.selectedRoot == .all)
    #expect(model.showPendingRecordings)
  }

  @Test func languageButtonsHaveDistinctAccessibleRoutesAndCaptureHasOneAction() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
      contentsOf: root.appending(path: "NarihitosDiary/ContentView.swift"),
      encoding: .utf8)
    #expect(source.contains("language: .english, shortLabel: \"en\""))
    #expect(source.contains("language: .korean, shortLabel: \"ko\""))
    #expect(source.contains("accessibilityLabel: \"Record in English\""))
    #expect(source.contains("accessibilityLabel: \"Record in Korean\""))
    #expect(source.contains("Color(red: 0.08, green: 0.35, blue: 0.70)"))
    #expect(source.contains("Color(red: 0.39, green: 0.21, blue: 0.62)"))
    #expect(source.contains(".frame(width: 56, height: 56)"))
    let recordingStart = try #require(source.range(of: "private struct RecordingView:"))
    let recordingEnd = try #require(source.range(of: "struct CaptureListView:"))
    let recording = String(source[recordingStart.lowerBound..<recordingEnd.lowerBound])
    let controls = try NSRegularExpression(pattern: #"\bButton(?:\s*\(|\s*\{)"#)
    #expect(
      controls.numberOfMatches(
        in: recording, range: NSRange(recording.startIndex..., in: recording)) == 1)
    #expect(recording.contains("Stop & Transcribe"))
    #expect(recording.contains("model.stopCapture()"))
    #expect(!source.contains("languageSelection"))
  }

  @Test func startGateHasNoSideEffects() async throws {
    let port = FakeCaptureEnvironment()
    let coordinator = CaptureCoordinator(environment: port)
    await #expect(throws: CaptureGateFailure.microphone) {
      try await coordinator.start(language: .english)
    }
    #expect(port.events.isEmpty)
    port.microphone = .authorized
    await #expect(throws: CaptureGateFailure.destination) {
      try await coordinator.start(language: .english)
    }
    #expect(port.events.isEmpty)
    port.destination = .verifiedOffline
    port.free = CaptureCoordinator.minimumFreeBytes - 1
    await #expect(throws: CaptureGateFailure.insufficientSpace) {
      try await coordinator.start(language: .english)
    }
    #expect(port.events.isEmpty)
  }

  @Test func durableSettlementOccursOnce() async throws {
    let port = FakeCaptureEnvironment()
    port.microphone = .authorized
    port.destination = .accessible
    port.free = CaptureCoordinator.minimumFreeBytes
    let coordinator = CaptureCoordinator(
      environment: port, now: { Date(timeIntervalSince1970: 10) })
    try await coordinator.start(language: .korean)
    guard case .capturing(let identity) = coordinator.phase else {
      Issue.record("Capture did not start")
      return
    }
    #expect(identity.startedAt == Date(timeIntervalSince1970: 10))
    #expect(identity.language == .korean)
    #expect(identity.destinationReference == port.reference)
    #expect(identity.installationBinding == "test-installation")
    coordinator.end(.user)
    coordinator.end(.timeLimit)
    #expect(coordinator.phase == .pending(identity))
    #expect(port.events == ["snapshot", "marker", "audio", "stop", "receipt"])
  }

  @Test func invalidAudioAndReceiptFailureNeverReportPending() async throws {
    let port = FakeCaptureEnvironment()
    port.microphone = .authorized
    port.destination = .accessible
    port.free = CaptureCoordinator.minimumFreeBytes
    port.inspection = CaptureInspection(
      byteCount: 64 * 1_024 * 1_024 + 1, duration: 20, isMonoAAC: true,
      isPlayable: true)
    let coordinator = CaptureCoordinator(environment: port)
    try await coordinator.start(language: .english)
    coordinator.end(.interruption)
    guard case .failed = coordinator.phase else {
      Issue.record("Oversized audio was accepted")
      return
    }
    let secondPort = FakeCaptureEnvironment()
    secondPort.microphone = .authorized
    secondPort.destination = .accessible
    secondPort.free = CaptureCoordinator.minimumFreeBytes
    secondPort.failReceipt = true
    let second = CaptureCoordinator(environment: secondPort)
    try await second.start(language: .english)
    second.end(.user)
    guard case .paused = second.phase else {
      Issue.record("Receipt failure was lost")
      return
    }
  }

  @Test func deadlineAndSizeLimitSettleWithoutVisibleTimer() async throws {
    let port = FakeCaptureEnvironment()
    port.microphone = .authorized
    port.destination = .accessible
    port.free = CaptureCoordinator.minimumFreeBytes
    var uptime = 1_000.0
    let coordinator = CaptureCoordinator(environment: port, uptime: { uptime })
    try await coordinator.start(language: .english)
    uptime = 1_299.99
    coordinator.poll()
    guard case .capturing = coordinator.phase else {
      Issue.record("Capture ended before five minutes")
      return
    }
    uptime = 1_300
    coordinator.poll()
    guard case .pending = coordinator.phase else {
      Issue.record("Five-minute limit did not settle")
      return
    }
    #expect(port.events.filter { $0 == "stop" }.count == 1)

    let secondPort = FakeCaptureEnvironment()
    secondPort.microphone = .authorized
    secondPort.destination = .accessible
    secondPort.free = CaptureCoordinator.minimumFreeBytes
    let second = CaptureCoordinator(environment: secondPort)
    try await second.start(language: .korean)
    secondPort.bytes = 64 * 1_024 * 1_024 + 1
    secondPort.inspection = CaptureInspection(
      byteCount: secondPort.bytes, duration: 10, isMonoAAC: true, isPlayable: true)
    second.poll()
    guard case .failed = second.phase else {
      Issue.record("Size limit did not stop capture")
      return
    }
  }

  @Test func recorderStartFailureRetainsIdentityForRecovery() async throws {
    let port = FakeCaptureEnvironment()
    port.microphone = .authorized
    port.destination = .accessible
    port.free = CaptureCoordinator.minimumFreeBytes
    port.failAudioStart = true
    let coordinator = CaptureCoordinator(environment: port)
    await #expect(throws: CaptureGateFailure.storage) {
      try await coordinator.start(language: .english)
    }
    guard case .paused(let identity) = coordinator.phase else {
      Issue.record("Start failure lost its durable identity")
      return
    }
    #expect(identity.language == .english)
    #expect(port.events == ["snapshot", "marker", "audio"])
  }

  @Test func failedDestinationSnapshotNeverStartsAudio() async throws {
    let port = FakeCaptureEnvironment()
    port.microphone = .authorized
    port.destination = .accessible
    port.free = CaptureCoordinator.minimumFreeBytes
    port.failSnapshot = true
    let coordinator = CaptureCoordinator(environment: port)
    await #expect(throws: CaptureGateFailure.destination) {
      try await coordinator.start(language: .english)
    }
    #expect(coordinator.phase == .idle)
    #expect(port.events == ["snapshot"])
  }

  @Test func failedFinalizationPausesOnceForRelaunch() async throws {
    let port = FakeCaptureEnvironment()
    port.microphone = .authorized
    port.destination = .accessible
    port.free = CaptureCoordinator.minimumFreeBytes
    port.failStop = true
    let coordinator = CaptureCoordinator(environment: port)
    var settlements = 0
    coordinator.onSettlement = { _ in settlements += 1 }
    try await coordinator.start(language: .english)
    coordinator.end(.user)
    coordinator.end(.interruption)
    guard case .paused = coordinator.phase else {
      Issue.record("Failed finalization was reported as queued")
      return
    }
    #expect(settlements == 1)
    #expect(port.events.filter { $0 == "stop" }.count == 1)
    #expect(!port.events.contains("receipt"))
  }
}

@MainActor
private final class FakeCaptureEnvironment: CaptureEnvironmentPort {
  var microphone: PermissionState = .denied
  var destination: CaptureDestinationState = .unavailable
  var free: Int64?
  let reference = UUID()
  var events: [String] = []
  var failReceipt = false
  var failAudioStart = false
  var failSnapshot = false
  var failStop = false
  var bytes: Int64 = 1_024
  var inspection = CaptureInspection(
    byteCount: 1024, duration: 1, isMonoAAC: true, isPlayable: true)

  func installationBinding() throws -> String { "test-installation" }

  func microphoneState() -> PermissionState { microphone }
  func destinationState() async -> CaptureDestinationState { destination }
  func freeBytes() -> Int64? { free }
  func snapshotDestination() async throws -> UUID {
    events.append("snapshot")
    if failSnapshot { throw CaptureGateFailure.destination }
    return reference
  }
  func persistStart(_: CaptureIdentity) throws { events.append("marker") }
  func startAudio(id _: WorkspaceID) throws {
    events.append("audio")
    if failAudioStart { throw CaptureGateFailure.storage }
  }
  func stopAudio() throws -> CaptureInspection {
    events.append("stop")
    if failStop { throw CaptureGateFailure.storage }
    return inspection
  }
  func currentAudioBytes() -> Int64? { bytes }
  func persistOutcome(_: CaptureIdentity, inspection: CaptureInspection) throws -> Bool {
    events.append("receipt")
    if failReceipt { throw CaptureGateFailure.storage }
    return inspection.isAccepted
  }
}
