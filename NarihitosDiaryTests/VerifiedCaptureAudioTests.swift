import AVFAudio
import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

@MainActor
struct VerifiedCaptureAudioTests {
  @Test func missingAndCorruptAudioFailWithoutDeletingOtherCaptureFiles() throws {
    for missing in [true, false] {
      let fixture = try VerifiedAudioFixture()
      defer { fixture.clean() }
      if missing {
        try FileManager.default.removeItem(at: fixture.url)
      } else {
        try Data([0, 1, 2, 3]).write(to: fixture.url)
      }
      #expect(throws: AudioFingerprintFailure.invalidAudio) {
        try fixture.source.open(job: fixture.job)
      }
      #expect(
        FileManager.default.fileExists(
          atPath: fixture.workspace.appending(path: "receipt.json").path))
      #expect(FileManager.default.fileExists(atPath: fixture.url.path) == !missing)
    }
  }

  @Test func oversizedAudioIsRejectedAndRetained() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    let handle = try FileHandle(forWritingTo: fixture.url)
    try handle.truncate(atOffset: UInt64(CapturePrivateFiles.maximumAudioBytes + 1))
    try handle.close()
    #expect(throws: AudioFingerprintFailure.invalidAudio) {
      try fixture.source.open(job: fixture.job)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.url.path))
  }

  @Test func stereoReplacementAndMismatchedClaimAreRejected() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    let actual = fixture.receipt.inspection
    let incompatible = QueueReceipt(
      id: fixture.receipt.id, startedAt: fixture.receipt.startedAt,
      language: fixture.receipt.language,
      destinationReference: fixture.receipt.destinationReference,
      installationBinding: fixture.receipt.installationBinding,
      inspection: CaptureInspection(
        byteCount: actual.byteCount, duration: actual.duration, isMonoAAC: true, isPlayable: true,
        sampleRate: actual.sampleRate, channelCount: 2))
    #expect(throws: AudioFingerprintFailure.invalidAudio) {
      try fixture.source.open(job: QueueJob(receipt: incompatible, state: .transcribing))
    }
    try FileManager.default.removeItem(at: fixture.url)
    try VerifiedAudioFixture.writeAAC(to: fixture.url, channels: 2)
    try fixture.files.protectOpenAudio(id: fixture.receipt.id)
    let inspection = try fixture.files.inspectAudio(id: fixture.receipt.id)
    #expect(!inspection.isMonoAAC)
    #expect(throws: AudioFingerprintFailure.invalidAudio) {
      try fixture.source.open(job: fixture.job)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.url.path))
  }

  @Test func unavailableProtectedDataWaitsBeforeOpeningAudio() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    let source = VerifiedCaptureAudioSource(files: fixture.files, protectedDataAvailable: { false })
    #expect(throws: AudioFingerprintFailure.protectedDataUnavailable) {
      try source.open(job: fixture.job)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.url.path))
  }

  @Test func readableNonAACReplacementIsRejectedAndRetained() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    let pcm = fixture.root.appending(path: "synthetic.caf")
    try VerifiedAudioFixture.writePCM(to: pcm)
    let format = try AVAudioFile(forReading: pcm).fileFormat
    #expect((format.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatLinearPCM)
    let bytes = try Data(contentsOf: pcm)
    try bytes.write(to: fixture.url)
    try fixture.files.protectOpenAudio(id: fixture.receipt.id)
    let inspection = try fixture.files.inspectAudio(id: fixture.receipt.id)
    #expect(!inspection.isMonoAAC)
    #expect(throws: AudioFingerprintFailure.invalidAudio) {
      try fixture.source.open(job: fixture.job)
    }
    #expect(try Data(contentsOf: fixture.url) == bytes)
  }

  @Test func overlongAACReplacementIsRejectedAndRetained() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    try FileManager.default.removeItem(at: fixture.url)
    try VerifiedAudioFixture.writeOverlongAAC(to: fixture.url)
    try fixture.files.protectOpenAudio(id: fixture.receipt.id)
    let file = try AVAudioFile(forReading: fixture.url)
    #expect(Double(file.length) / file.fileFormat.sampleRate > 301)
    #expect(throws: AudioFingerprintFailure.invalidAudio) {
      try fixture.source.open(job: fixture.job)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.url.path))
  }

  @Test func sameSizePlayableSubstitutionInvalidatesPublishedCandidate() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    let claim = try fixture.makeClaim()
    let store = FileTranscriptionCandidateStore(
      root: fixture.root, audio: fixture.source, protection: FixtureCandidateProtection())
    try store.publish(claim.payload, request: claim.request, job: claim.job)
    let original = try Data(contentsOf: fixture.url)
    let marker = try #require(original.range(of: Data("mvhd".utf8)))
    let index = marker.upperBound + 4
    #expect(index < original.count)
    let handle = try FileHandle(forWritingTo: fixture.url)
    try handle.seek(toOffset: UInt64(index))
    try handle.write(contentsOf: Data([original[index] ^ 1]))
    try handle.close()
    let changedDigest = try fixture.source.fingerprint(for: claim.job)
    #expect(changedDigest != claim.payload.sourceDigest)
    #expect(try Data(contentsOf: fixture.url).count == original.count)
    #expect(try store.inspect(job: claim.job) == .invalid)
  }

  @Test func publishedFileCandidateRecoversAndCanBeAdoptedAfterRelaunch() throws {
    let fixture = try VerifiedAudioFixture()
    defer { fixture.clean() }
    let claim = try fixture.makeClaim()
    let candidateStore = FileTranscriptionCandidateStore(
      root: fixture.root, audio: fixture.source, protection: FixtureCandidateProtection())
    try candidateStore.publish(claim.payload, request: claim.request, job: claim.job)
    let jobs = MemoryQueueStore()
    jobs.values[claim.job.id] = claim.job
    let queue = ProcessingQueueCoordinator(
      store: jobs, receipts: MemoryReceiptSource([fixture.receipt]),
      identity: FakeInstallationIdentity(), settings: FakeTranscriptionSettings(),
      registry: TranscriptionMethodRegistry(), candidates: candidateStore)
    queue.reconcile()
    let recovered = try #require(jobs.values[claim.job.id])
    #expect(recovered.state == .resultReady)
    #expect(try candidateStore.readVerified(job: recovered) == claim.payload)
  }
}

private struct FixtureCandidateProtection: CandidateProtectionPolicy {
  func apply(to _: URL, manager _: FileManager) throws {}
  func verify(to _: URL, manager _: FileManager) throws {}
}

@MainActor
private final class VerifiedAudioFixture {
  let root: URL
  let workspace: URL
  let url: URL
  let files: CapturePrivateFiles
  let receipt: QueueReceipt
  let job: QueueJob
  let source: VerifiedCaptureAudioSource

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "verified-audio-\(UUID())")
    files = CapturePrivateFiles(root: root, protection: NoCaptureProtectionPolicy())
    let destination = try files.saveSnapshot(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue, displayName: "Synthetic", bookmark: Data([1]),
        identityArchive: Data([2]), disclosureAcknowledged: true))
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: Date(timeIntervalSince1970: 1),
      language: .english, destinationReference: destination, installationBinding: "current")
    try files.createWorkspace(identity)
    url = try files.prepareAudio(id: identity.id)
    workspace = url.deletingLastPathComponent()
    try Self.writeAAC(to: url, channels: 1)
    try files.protectOpenAudio(id: identity.id)
    let inspection = try files.inspectAudio(id: identity.id)
    guard try files.saveOutcome(identity, inspection: inspection),
      let receipt = files.queueReceipt(jobID: identity.id.description)
    else { throw QueueStoreFailure.corrupt }
    self.receipt = receipt
    job = QueueJob(receipt: receipt, state: .transcribing)
    source = VerifiedCaptureAudioSource(files: files)
  }

  func makeClaim() throws -> VerifiedFileClaim {
    var claim = job
    claim.attemptID = UUID()
    claim.attemptGeneration = 1
    claim.selectedMethodID = TranscriptionMethodIdentifiers.apple
    claim.effectiveSettings = [
      "settingsRevision": "1", "requestedLocale": "en-US", "resolvedLocale": "en-US",
      "preset": "transcription", "resultPolicy": "final-only",
      "runtime": "apple-speech-analyzer", "operatingSystemVersion": "27.0",
    ]
    claim.conversionIdentity = "ndm.apple-speech.av-audio-file-v1"
    let settings = EffectiveTranscriptionSettings(
      values: try #require(claim.effectiveSettings), modelIdentity: nil,
      conversionIdentity: try #require(claim.conversionIdentity))
    let request = TranscriptionRequest(
      jobID: claim.id, attemptID: try #require(claim.attemptID), generation: 1,
      language: .english, settings: settings, destinationRevision: 0, bodyRevision: 0)
    let payload = TranscriptionPayload(
      text: "A synthetic diary.", sourceDigest: try source.fingerprint(for: claim),
      resolvedLocale: "en-US", runtime: "apple-speech-analyzer",
      conversion: settings.conversionIdentity, operatingSystemVersion: "27.0")
    return VerifiedFileClaim(job: claim, request: request, payload: payload)
  }

  static func writeAAC(to url: URL, channels: AVAudioChannelCount) throws {
    let format = try #require(
      AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: channels))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
    buffer.frameLength = 4_410
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: Int(channels), AVEncoderBitRateKey: 64_000,
      ])
    try writer.write(from: buffer)
  }

  static func writePCM(to url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
    buffer.frameLength = 4_410
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      ])
    try writer.write(from: buffer)
  }

  static func writeOverlongAAC(to url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
    buffer.frameLength = 8_000
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 8_000,
        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 16_000,
      ])
    for _ in 0..<302 { try writer.write(from: buffer) }
  }

  func clean() { try? FileManager.default.removeItem(at: root) }
}

private struct VerifiedFileClaim {
  let job: QueueJob
  let request: TranscriptionRequest
  let payload: TranscriptionPayload
}

// swiftlint:enable trailing_comma
