import AVFAudio
import Foundation
import Testing

@testable import NarihitosDiary

// swift-format and SwiftLint disagree on trailing commas in multiline collections.
// swiftlint:disable trailing_comma file_length

@MainActor
// swiftlint:disable:next type_body_length
struct CapturePrivateFilesTests {
  @Test func pendingRemovalReleasesCaptureDestinationSnapshot() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]), disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 5),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let receipt = QueueReceipt(
      id: identity.id, startedAt: identity.startedAt, language: identity.language,
      destinationReference: reference, installationBinding: "installation",
      inspection: CaptureInspection(
        byteCount: 512, duration: 1, isMonoAAC: true, isPlayable: true))
    let job = QueueJob(receipt: receipt, state: .removing)

    try CaptureQueueReceiptSource(files: files).removePrivateCapture(job: job)
    let snapshot = root.appending(path: "snapshot-\(reference.uuidString.lowercased()).json")
    #expect(!FileManager.default.fileExists(atPath: snapshot.path))
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: job.id).path))
  }

  @Test func removalPreservesWorkspaceContainingUnknownFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]), disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 5),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let unknown = root.appending(path: identity.id.description).appending(path: "unknown.data")
    try Data([1, 2, 3]).write(to: unknown)
    #expect(throws: CaptureGateFailure.storage) {
      try files.removeWorkspace(jobID: identity.id.description)
    }
    #expect(FileManager.default.fileExists(atPath: unknown.path))
    #expect(
      FileManager.default.fileExists(
        atPath: unknown.deletingLastPathComponent().appending(path: "capture.json").path))
  }

  @Test func removalAcceptsOwnedM13DraftAndRecoveryFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]), disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 5),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let folder = root.appending(path: identity.id.description, directoryHint: .isDirectory)
    for name in [
      PrivateArtifactRole.markdownDraft.ownedFilename,
      PrivateArtifactRole.draftBinding.ownedFilename,
      ".recovery-markdownDraft", ".recovery-draftBinding",
    ] {
      try Data([1]).write(to: folder.appending(path: name))
    }
    try files.removeWorkspace(jobID: identity.id.description)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test func transcriptionLeaseDetectsSameSizeAudioReplacement() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]), disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 5),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let url = try files.prepareAudio(id: identity.id)
    try writeSyntheticAAC(to: url)
    try files.protectOpenAudio(id: identity.id)
    let inspection = try files.inspectAudio(id: identity.id)
    #expect(try files.saveOutcome(identity, inspection: inspection))
    let receipt = try #require(files.queueReceipt(jobID: identity.id.description))
    let job = QueueJob(receipt: receipt, state: .transcribing)
    let source = VerifiedCaptureAudioSource(files: files)
    let hardLink = root.appending(path: "extra-audio-link.m4a")
    try FileManager.default.linkItem(at: url, to: hardLink)
    #expect(throws: (any Error).self) { try source.open(job: job) }
    try FileManager.default.removeItem(at: hardLink)
    let lease = try source.open(job: job)
    #expect(lease.digest.count == 64)
    var bytes = try Data(contentsOf: url)
    bytes[bytes.count - 1] ^= 1
    try bytes.write(to: url, options: .atomic)
    #expect(throws: (any Error).self) { try lease.verifyUnchanged() }
    let workspace = url.deletingLastPathComponent()
    let relocated = root.appending(path: "relocated", directoryHint: .isDirectory)
    try FileManager.default.moveItem(at: workspace, to: relocated)
    try FileManager.default.createSymbolicLink(at: workspace, withDestinationURL: relocated)
    #expect(files.queueReceipt(jobID: identity.id.description) == nil)
  }

  @Test func syntheticAACIsDecodedBeforePendingReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 5),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try writeSyntheticAAC(to: audio)
    try files.protectOpenAudio(id: identity.id)

    let inspection = try files.inspectAudio(id: identity.id)
    #expect(inspection.isAccepted)
    #expect(inspection.isMonoAAC)
    #expect(inspection.channelCount == 1)
    #expect(inspection.sampleRate == 44_100)
    #expect(inspection.duration > 0 && inspection.duration < 2)
    #expect(try files.saveOutcome(identity, inspection: inspection))
    #expect(files.list(outcome: "pending") == [identity])
    #expect(files.reconcile().isEmpty)
  }

  @Test func veryShortEnglishAACReachesPendingWithoutExactReportedFrameEquality() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]), disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 5),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try writeSyntheticAAC(to: audio, frameCount: 441)
    try files.protectOpenAudio(id: identity.id)

    let inspection = try files.inspectAudio(id: identity.id)
    #expect(inspection.isAccepted)
    #expect(inspection.duration > 0)
    #expect(try files.saveOutcome(identity, inspection: inspection))
    #expect(files.queueReceipt(jobID: identity.id.description)?.language == .english)
  }

  @Test func playablePartialRecoversToOnePendingReceiptAfterRelaunch() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 6),
      language: .korean, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try writeSyntheticAAC(to: audio)
    try files.protectOpenAudio(id: identity.id)

    let reopened = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    #expect(reopened.reconcile() == [identity])
    #expect(reopened.list(outcome: "pending") == [identity])
    #expect(reopened.reconcile().isEmpty)
    #expect(reopened.list(outcome: "pending") == [identity])
  }

  @Test func unplayablePartialIsRetainedAndReconciledOnce() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 10),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try Data([0, 1, 2, 3]).write(to: audio)
    try files.protectOpenAudio(id: identity.id)

    #expect(files.issues().count == 1)
    #expect(files.reconcile() == [identity])
    #expect(files.reconcile().isEmpty)
    #expect(files.list(outcome: "failed") == [identity])
    #expect(files.list(outcome: "pending").isEmpty)
    #expect(files.issues().isEmpty)
    #expect(FileManager.default.fileExists(atPath: audio.path))
    let values = try audio.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
    let snapshot = root.appending(path: "snapshot-\(reference.uuidString.lowercased()).json")
    let workspace = root.appending(path: identity.id.description)
    let marker = workspace.appending(path: "capture.json")
    let receipt = workspace.appending(path: "receipt.json")
    for url in [snapshot, marker, receipt] {
      let attributes = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      #expect(attributes.isExcludedFromBackup == true)
    }
    try Data("invalid receipt".utf8).write(to: receipt)
    #expect(files.list(outcome: "failed").isEmpty)
    #expect(files.issues().count == 1)
    #expect(FileManager.default.fileExists(atPath: audio.path))
    try FileManager.default.removeItem(at: receipt)
    #expect(files.reconcile() == [identity])
    try FileManager.default.removeItem(at: audio)
    #expect(files.list(outcome: "failed").isEmpty)
    #expect(files.issues().count == 1)
  }

  @Test func failedReceiptCommitRetainsAudioForRelaunchRecovery() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(
      root: root, protection: NoCaptureProtectionPolicy(),
      failureInjector: { point, url in
        if case .beforeCommit = point, url.lastPathComponent == "receipt.json" {
          throw CaptureGateFailure.storage
        }
      })
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 20),
      language: .korean, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try Data([1, 2, 3, 4]).write(to: audio)
    try files.protectOpenAudio(id: identity.id)
    let inspection = CaptureInspection(
      byteCount: 4, duration: 0, isMonoAAC: false, isPlayable: false)
    #expect(throws: CaptureGateFailure.storage) {
      try files.saveOutcome(identity, inspection: inspection)
    }
    #expect(FileManager.default.fileExists(atPath: audio.path))
    #expect(files.issues().count == 1)
    let workspace = root.appending(path: identity.id.description)
    let children = try FileManager.default.contentsOfDirectory(
      at: workspace, includingPropertiesForKeys: [.isExcludedFromBackupKey])
    let scratch = children.filter { $0.lastPathComponent.hasPrefix(".write-") }
    #expect(scratch.count == 1)
    let attributes = try scratch[0].resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(attributes.isExcludedFromBackup == true)

    let reopened = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    #expect(reopened.reconcile() == [identity])
    #expect(reopened.list(outcome: "failed") == [identity])
  }

  @Test func missingAudioAfterRelaunchRemainsReviewableWithoutAFalseReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 30),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    #expect(files.reconcile().isEmpty)
    #expect(files.list(outcome: "failed").isEmpty)
    #expect(files.list(outcome: "pending").isEmpty)
    #expect(files.issues().count == 1)
  }

  @Test func postCommitErrorIsAcceptedOnlyAfterReceiptVerification() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(
      root: root, protection: NoCaptureProtectionPolicy(),
      failureInjector: { point, url in
        if case .afterCommit = point, url.lastPathComponent == "receipt.json" {
          throw CaptureGateFailure.storage
        }
      })
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 40),
      language: .korean, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try Data([1, 2, 3, 4]).write(to: audio)
    try files.protectOpenAudio(id: identity.id)
    let inspection = CaptureInspection(
      byteCount: 4, duration: 0, isMonoAAC: false, isPlayable: false)
    #expect(try files.saveOutcome(identity, inspection: inspection) == false)
    #expect(files.list(outcome: "failed") == [identity])
    #expect(files.issues().isEmpty)
  }

  @Test func substitutedAudioSymlinkNeverReadsExternalBytes() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let outside = FileManager.default.temporaryDirectory.appending(
      path: "outside-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: outside) }
    try Data([9, 9, 9]).write(to: outside)
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 50),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try FileManager.default.createSymbolicLink(at: audio, withDestinationURL: outside)
    #expect(throws: CaptureGateFailure.storage) { try files.inspectAudio(id: identity.id) }
    #expect(files.reconcile().isEmpty)
    #expect(files.list(outcome: "failed").isEmpty)
    #expect(files.issues().count == 1)
    #expect(try Data(contentsOf: outside) == Data([9, 9, 9]))
  }

  @Test func failedReceiptProtectionNeverReportsQueued() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: FailingReceiptProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 60),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try Data([1, 2, 3, 4]).write(to: audio)
    try files.protectOpenAudio(id: identity.id)
    let inspection = CaptureInspection(
      byteCount: 4, duration: 0, isMonoAAC: false, isPlayable: false)
    #expect(throws: CaptureGateFailure.storage) {
      try files.saveOutcome(identity, inspection: inspection)
    }
    #expect(files.list(outcome: "pending").isEmpty)
    #expect(files.list(outcome: "failed").isEmpty)
    #expect(files.issues().count == 1)
    #expect(FileManager.default.fileExists(atPath: audio.path))
    let reopened = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    #expect(reopened.reconcile() == [identity])
    #expect(reopened.list(outcome: "failed") == [identity])
  }
}

private func writeSyntheticAAC(to url: URL, frameCount: AVAudioFrameCount = 44_100) throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
  buffer.frameLength = frameCount
  let samples = try #require(buffer.floatChannelData?[0])
  for index in 0..<Int(frameCount) {
    samples[index] = 0.08 * sin(Float(index) * 2 * .pi * 440 / 44_100)
  }
  let writer = try AVAudioFile(
    forWriting: url,
    settings: [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 64_000,
    ])
  try writer.write(from: buffer)
}

@MainActor
struct CaptureClosedProtectionTests {
  @Test func emptyClosedAudioRequiresVerifiedProtectionBeforeFailureClassification() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: RejectClosedAudioProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 1),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try Data().write(to: audio)
    try files.protectOpenAudio(id: identity.id)

    #expect(throws: CaptureGateFailure.storage) {
      try files.inspectAudio(id: identity.id)
    }
    #expect(FileManager.default.fileExists(atPath: audio.path))
    #expect(files.list(outcome: "failed").isEmpty)
  }
}

@MainActor
struct CaptureReceiptVerificationTests {
  @Test func corruptCaptureMarkerCannotPublishPendingReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let reference = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic",
        bookmark: Data([1]), identityArchive: Data([2]),
        disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 7),
      language: .english, destinationReference: reference)
    try files.createWorkspace(identity)
    let audio = try files.prepareAudio(id: identity.id)
    try writeSyntheticAAC(to: audio)
    try files.protectOpenAudio(id: identity.id)
    let inspection = try files.inspectAudio(id: identity.id)
    let marker = root.appending(path: identity.id.description).appending(path: "capture.json")
    try Data("corrupt".utf8).write(to: marker)

    #expect(throws: CaptureGateFailure.storage) {
      try files.saveOutcome(identity, inspection: inspection)
    }
    #expect(files.list(outcome: "pending").isEmpty)
    #expect(files.issues().count == 1)
    #expect(FileManager.default.fileExists(atPath: audio.path))
  }
}

// swiftlint:enable trailing_comma

private struct FailingReceiptProtectionPolicy: CaptureProtectionPolicy {
  func applyAndVerify(to url: URL, open _: Bool, manager _: FileManager) throws {
    if url.lastPathComponent == "receipt.json" {
      var values = URLResourceValues()
      values.isExcludedFromBackup = false
      var mutable = url
      try mutable.setResourceValues(values)
      throw CaptureGateFailure.storage
    }
  }

  func verify(to url: URL, open _: Bool, manager _: FileManager) throws {
    if url.lastPathComponent == "receipt.json" { throw CaptureGateFailure.storage }
  }
}

private struct RejectClosedAudioProtectionPolicy: CaptureProtectionPolicy {
  func applyAndVerify(to url: URL, open: Bool, manager _: FileManager) throws {
    if url.lastPathComponent == "pending-audio.m4a" && !open {
      throw CaptureGateFailure.storage
    }
  }

  func verify(to _: URL, open _: Bool, manager _: FileManager) throws {}
}
