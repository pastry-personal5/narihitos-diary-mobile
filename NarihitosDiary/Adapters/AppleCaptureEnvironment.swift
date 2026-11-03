import AVFAudio
import Foundation
import UIKit

// swift-format's multiline collections conflict with SwiftLint's trailing-comma rule.
// swiftlint:disable trailing_comma

enum AppleAudioRecorderStart {
  static func run(
    protect: () throws -> Void,
    prepare: () -> Bool,
    record: () -> Bool
  ) throws {
    try protect()
    guard prepare() else { throw CaptureGateFailure.storage }
    guard record() else { throw CaptureGateFailure.storage }
  }
}

@MainActor
final class AppleCaptureEnvironment: CaptureEnvironmentPort {
  private let microphone: any MicrophoneAuthorizationPort
  private let destination: AppleDestinationService
  private let files: CapturePrivateFiles
  private let installationIdentity: any InstallationIdentityPort
  private var recorder: AVAudioRecorder?
  private var currentID: WorkspaceID?
  private let sessionOwnership: AudioSessionOwnership
  private var sessionToken: AudioSessionToken?

  init(
    microphone: any MicrophoneAuthorizationPort,
    destination: AppleDestinationService,
    files: CapturePrivateFiles = CapturePrivateFiles(),
    installationIdentity: any InstallationIdentityPort = KeychainInstallationIdentity(),
    sessionOwnership: AudioSessionOwnership? = nil
  ) {
    self.microphone = microphone
    self.destination = destination
    self.files = files
    self.installationIdentity = installationIdentity
    self.sessionOwnership =
      sessionOwnership
      ?? AudioSessionOwnership(platform: AppleAudioSessionConfiguration())
  }

  func installationBinding() throws -> String {
    switch installationIdentity.currentOrCreate() {
    case .available(let value): value
    case .missing, .temporarilyUnavailable: throw CaptureGateFailure.storage
    }
  }

  func microphoneState() -> PermissionState { microphone.currentState() }

  func destinationState() async -> CaptureDestinationState {
    (try? await destination.captureSnapshotRecord().1) ?? .unavailable
  }

  func freeBytes() -> Int64? {
    guard
      let attributes = try? FileManager.default.attributesOfFileSystem(
        forPath: files.root.path),
      let number = attributes[.systemFreeSize] as? NSNumber
    else { return nil }
    return number.int64Value
  }

  func snapshotDestination() async throws -> UUID {
    let record = try await destination.captureSnapshotRecord().0
    return try files.saveSnapshot(record)
  }

  func persistStart(_ identity: CaptureIdentity) throws {
    try files.createWorkspace(identity)
  }

  func startAudio(id: WorkspaceID) throws {
    let url = try files.createProtectedAudio(id: id)
    do {
      sessionToken = try sessionOwnership.acquire(.recording)
      let candidate = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 64_000,
        ])
      candidate.isMeteringEnabled = true
      try AppleAudioRecorderStart.run(
        protect: { try files.verifyOpenAudio(id: id) },
        prepare: candidate.prepareToRecord,
        record: candidate.record)
      recorder = candidate
      currentID = id
    } catch {
      recorder = nil
      currentID = nil
      if let sessionToken { sessionOwnership.release(sessionToken) }
      sessionToken = nil
      throw error
    }
  }

  func stopAudio() throws -> CaptureInspection {
    guard let recorder, let id = currentID else { throw CaptureGateFailure.storage }
    recorder.stop()
    self.recorder = nil
    currentID = nil
    if let sessionToken { sessionOwnership.release(sessionToken) }
    sessionToken = nil
    return try files.inspectAudio(id: id)
  }

  func persistOutcome(_ identity: CaptureIdentity, inspection: CaptureInspection) throws -> Bool {
    try files.saveOutcome(identity, inspection: inspection)
  }

  func currentLevel() -> Float {
    guard let recorder else { return 0 }
    recorder.updateMeters()
    return max(0, min(1, (recorder.averagePower(forChannel: 0) + 60) / 60))
  }

  func currentAudioBytes() -> Int64? {
    guard let currentID else { return nil }
    return files.audioBytes(id: currentID)
  }

  func recover() -> [CaptureIdentity] { files.reconcile() }
  func pending() -> [CaptureIdentity] { files.list(outcome: "pending") }
  func failed() -> [CaptureIdentity] { files.list(outcome: "failed") }
  func issues() -> [CaptureRecoveryIssue] { files.issues() }
}

// swiftlint:enable trailing_comma
