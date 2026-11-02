import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

@MainActor
struct TranscriptionCandidateStoreTests {
  @Test func interruptedPublicationRetainsOnlyACompletePublishedCandidate() throws {
    for point in CandidateWritePoint.allCases {
      let fixture = try CandidateFixture()
      defer { fixture.clean() }
      let availability = fixture.protectedData
      let store = FileTranscriptionCandidateStore(
        root: fixture.root, audio: fixture.audio, protection: TestCandidateProtectionPolicy(),
        failureInjector: { current in
          if current == point { throw QueueStoreFailure.unavailable }
        }, protectedDataAvailable: { availability.value })
      #expect(throws: QueueStoreFailure.unavailable) {
        try store.publish(fixture.payload, request: fixture.request, job: fixture.job)
      }
      let expected: CandidateInspection =
        point == .published || point == .publishedVerified ? .verified : .missing
      #expect(try fixture.store.inspect(job: fixture.job) == expected)
      let children = try FileManager.default.contentsOfDirectory(
        atPath: fixture.candidate.deletingLastPathComponent().path)
      #expect(children.allSatisfy { !$0.hasPrefix(".result-") })
    }
  }

  @Test func publicationReopensProtectedCandidateAndRejectsSourceReplacement() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    try fixture.store.publish(fixture.payload, request: fixture.request, job: fixture.job)
    #expect(try fixture.store.inspect(job: fixture.job) == .verified)
    #expect(throws: QueueStoreFailure.corrupt) { try fixture.store.readVerified(job: fixture.job) }
    var ready = fixture.job
    ready.state = .resultReady
    #expect(try fixture.store.readVerified(job: ready) == fixture.payload)
    let values = try fixture.candidate.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
    fixture.audio.digest = String(repeating: "b", count: 64)
    #expect(try fixture.store.inspect(job: fixture.job) == .invalid)
    #expect(throws: QueueStoreFailure.corrupt) { try fixture.store.readVerified(job: ready) }
  }

  @Test func staleClaimAndRestoredRevisionCannotAdoptCandidate() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    try fixture.store.publish(fixture.payload, request: fixture.request, job: fixture.job)
    var stale = fixture.job
    stale.attemptGeneration += 1
    #expect(try fixture.store.inspect(job: stale) == .invalid)
    stale = fixture.job
    stale.destinationRevision += 1
    #expect(try fixture.store.inspect(job: stale) == .invalid)
    stale = fixture.job
    stale.bodyRevision += 1
    #expect(try fixture.store.inspect(job: stale) == .invalid)
    stale.state = .resultReady
    #expect(throws: QueueStoreFailure.corrupt) { try fixture.store.discard(job: stale) }
    #expect(try fixture.store.inspect(job: fixture.job) == .verified)
  }

  @Test func lockedDataIsDeferredAndBadTextCannotPublish() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    fixture.protectedData.value = false
    #expect(try fixture.store.inspect(job: fixture.job) == .protectedDataUnavailable)
    var ready = fixture.job
    ready.state = .resultReady
    #expect(throws: TranscriptionCandidateFailure.protectedDataUnavailable) {
      try fixture.store.readVerified(job: ready)
    }
    fixture.protectedData.value = true
    var bad = fixture.payload
    bad = TranscriptionPayload(
      text: "...", sourceDigest: bad.sourceDigest, resolvedLocale: bad.resolvedLocale,
      runtime: bad.runtime, conversion: bad.conversion,
      operatingSystemVersion: bad.operatingSystemVersion)
    #expect(throws: (any Error).self) {
      try fixture.store.publish(bad, request: fixture.request, job: fixture.job)
    }
    #expect(try fixture.store.inspect(job: fixture.job) == .missing)
  }

  @Test func resultCannotChangeTheClaimedAppleProvenance() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    let wrongLocale = TranscriptionPayload(
      text: fixture.payload.text, sourceDigest: fixture.payload.sourceDigest,
      resolvedLocale: "ko-KR", runtime: fixture.payload.runtime,
      conversion: fixture.payload.conversion,
      operatingSystemVersion: fixture.payload.operatingSystemVersion)
    #expect(throws: QueueStoreFailure.corrupt) {
      try fixture.store.publish(wrongLocale, request: fixture.request, job: fixture.job)
    }
    #expect(try fixture.store.inspect(job: fixture.job) == .missing)
  }

  @Test func cohereCandidateRequiresClosedPinnedProvenance() throws {
    let fixture = try CandidateFixture(method: .cohere)
    defer { fixture.clean() }

    try fixture.store.publish(fixture.payload, request: fixture.request, job: fixture.job)

    #expect(try fixture.store.inspect(job: fixture.job) == .verified)
    var mismatched = fixture.job
    mismatched.effectiveSettings?["backend"] = "cpu"
    #expect(try fixture.store.inspect(job: mismatched) == .invalid)
  }

  @Test func unknownMethodCandidateFailsClosed() throws {
    let fixture = try CandidateFixture(method: .unknown)
    defer { fixture.clean() }

    #expect(throws: QueueStoreFailure.corrupt) {
      try fixture.store.publish(fixture.payload, request: fixture.request, job: fixture.job)
    }
  }

  @Test func sourceChangedDuringPublicationCannotBeAccepted() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    let availability = fixture.protectedData
    let store = FileTranscriptionCandidateStore(
      root: fixture.root, audio: fixture.audio, protection: TestCandidateProtectionPolicy(),
      failureInjector: { point in
        if point == .published { fixture.audio.digest = String(repeating: "b", count: 64) }
      }, protectedDataAvailable: { availability.value })
    #expect(throws: TranscriptionCandidateFailure.invalidSource) {
      try store.publish(fixture.payload, request: fixture.request, job: fixture.job)
    }
    try store.discard(job: fixture.job)
    #expect(try store.inspect(job: fixture.job) == .missing)
  }

  @Test func linkedCandidateIsRejectedWithoutRemovingTarget() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    let target = fixture.root.appending(path: "target")
    try Data("private".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: fixture.candidate, withDestinationURL: target)
    #expect(try fixture.store.inspect(job: fixture.job) == .invalid)
    #expect(throws: (any Error).self) { try fixture.store.discard(job: fixture.job) }
    #expect(try Data(contentsOf: target) == Data("private".utf8))
  }

  @Test func linkedWorkspaceIsIsolatedWithoutReadingItsContents() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    let workspace = fixture.candidate.deletingLastPathComponent()
    let target = fixture.root.appending(path: "outside", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.removeItem(at: workspace)
    try FileManager.default.createSymbolicLink(at: workspace, withDestinationURL: target)
    #expect(try fixture.store.inspect(job: fixture.job) == .invalid)
    try fixture.store.discard(job: fixture.job)
    #expect(FileManager.default.fileExists(atPath: target.path))
  }

  @Test func hardLinkedCandidateIsRejectedWithoutRemovingTarget() throws {
    let fixture = try CandidateFixture()
    defer { fixture.clean() }
    let target = fixture.root.appending(path: "target")
    try Data("private".utf8).write(to: target)
    try FileManager.default.linkItem(at: target, to: fixture.candidate)
    #expect(try fixture.store.inspect(job: fixture.job) == .invalid)
    #expect(throws: (any Error).self) { try fixture.store.discard(job: fixture.job) }
    #expect(try Data(contentsOf: target) == Data("private".utf8))
  }
}

@MainActor
private final class CandidateFixture {
  enum Method: Equatable {
    case apple
    case cohere
    case unknown
  }

  let root: URL
  let candidate: URL
  let job: QueueJob
  let request: TranscriptionRequest
  let payload: TranscriptionPayload
  let audio = FakeAudioFingerprint()
  let protectedData = MutableAvailability()
  let store: FileTranscriptionCandidateStore

  // swiftlint:disable:next function_body_length
  init(method: Method = .apple) throws {
    let id = try WorkspaceID("00000000-0000-4000-8000-000000000001")
    root = FileManager.default.temporaryDirectory.appending(path: "candidate-\(UUID())")
    let workspace = root.appending(path: id.description, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    candidate = workspace.appending(path: "transcription-result-v1.json")
    let receipt = QueueReceipt(
      id: id, startedAt: Date(timeIntervalSince1970: 1), language: .english,
      destinationReference: UUID(), installationBinding: "current",
      inspection: CaptureInspection(
        byteCount: 1024, duration: 1, isMonoAAC: true, isPlayable: true,
        sampleRate: 44_100, channelCount: 1))
    var claim = QueueJob(receipt: receipt, state: .transcribing)
    claim.attemptGeneration = 1
    claim.attemptID = UUID()
    switch method {
    case .apple:
      claim.selectedMethodID = TranscriptionMethodIdentifiers.apple
      claim.effectiveSettings = [
        "settingsRevision": "1", "requestedLocale": "en-US", "resolvedLocale": "en-US",
        "preset": "transcription", "resultPolicy": "final-only",
        "runtime": "apple-speech-analyzer", "operatingSystemVersion": "27.0",
      ]
      claim.modelIdentity = nil
      claim.conversionIdentity = "file-v1"
    case .cohere:
      let descriptor = CohereTrustedModel.production
      claim.selectedMethodID = TranscriptionMethodIdentifiers.cohere
      claim.effectiveSettings = [
        "settingsRevision": "1", "requestedLocale": "en-US", "resolvedLocale": "en-US",
        "languageHint": "en", "backend": "metal",
        "runtime": CohereRuntimeProvenance.identity,
        "runtimeCommit": CohereRuntimeProvenance.commit,
        "modelID": descriptor.modelID, "modelRevision": descriptor.repositoryRevision,
        "quantization": descriptor.quantization,
        "chunkingRevision": CohereChunkPlanner.identity,
        "installedIdentity": descriptor.installationIdentity,
        "operatingSystemVersion": "27.0",
      ]
      claim.modelIdentity = descriptor.installationIdentity
      claim.conversionIdentity = CohereAudioConversion.identity
    case .unknown:
      claim.selectedMethodID = "ndm.transcription.unknown"
      claim.effectiveSettings = ["settingsRevision": "1"]
      claim.modelIdentity = nil
      claim.conversionIdentity = "file-v1"
    }
    job = claim
    let settings = EffectiveTranscriptionSettings(
      values: claim.effectiveSettings!, modelIdentity: claim.modelIdentity,
      conversionIdentity: claim.conversionIdentity ?? "file-v1")
    request = TranscriptionRequest(
      jobID: id.description, attemptID: claim.attemptID!, generation: 1, language: .english,
      settings: settings, destinationRevision: 0, bodyRevision: 0)
    let payloadRuntime =
      method == .cohere ? CohereRuntimeProvenance.identity : "apple-speech-analyzer"
    payload = TranscriptionPayload(
      text: "A test diary.", sourceDigest: String(repeating: "a", count: 64),
      resolvedLocale: "en-US", runtime: payloadRuntime,
      conversion: claim.conversionIdentity ?? "file-v1",
      operatingSystemVersion: "27.0")
    let availability = protectedData
    store = FileTranscriptionCandidateStore(
      root: root, audio: audio, protection: TestCandidateProtectionPolicy(),
      protectedDataAvailable: { availability.value })
  }

  func clean() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class FakeAudioFingerprint: CaptureAudioFingerprintSource {
  var digest = String(repeating: "a", count: 64)
  func fingerprint(for _: QueueJob) throws -> String { digest }
}

@MainActor
private final class MutableAvailability {
  var value = true
}

private struct TestCandidateProtectionPolicy: CandidateProtectionPolicy {
  func apply(to _: URL, manager _: FileManager) throws {}
  func verify(to _: URL, manager _: FileManager) throws {}
}

// swiftlint:enable trailing_comma
