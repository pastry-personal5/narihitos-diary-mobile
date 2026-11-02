// swiftlint:disable trailing_comma
import AVFAudio
import Foundation
import Testing

@testable import NarihitosDiary

struct DiaryCatalogHandlerTests {
  private let handler = DiaryCatalogHandler()

  @Test func legacyPairRemainsReadOnlyAndUnusableAudioDoesNotHideText() async throws {
    let fixture = try makeLegacy()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let before = try Data(contentsOf: fixture.markdown)
    let value = try await handler.read(fixture.candidate, root: fixture.root)
    #expect(value.issue == nil)
    #expect(value.hasAudio)
    #expect(value.assetID == nil)
    let detail = try #require(value.payload as? DiaryCatalogDetail)
    #expect(detail.isLegacy)
    #expect(detail.favorite == nil)
    #expect(detail.audioAvailable)
    #expect(detail.body == "A synthetic first sentence. Another sentence.")
    #expect(try Data(contentsOf: fixture.markdown) == before)
    try Data("Not audio".utf8).write(to: fixture.audio)
    let unavailable = try await handler.read(fixture.candidate, root: fixture.root)
    #expect(unavailable.issue == nil)
    #expect(!unavailable.hasAudio)
    #expect((unavailable.payload as? DiaryCatalogDetail)?.body == detail.body)
  }

  @Test func zeroMultipleAndUnsafeLegacySiblingsProduceSeparateReasons() async throws {
    let fixture = try makeLegacy()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let other = fixture.audio.deletingLastPathComponent().appending(path: "second.m4a")
    try Data(contentsOf: fixture.audio).write(to: other)
    #expect(try await handler.read(fixture.candidate, root: fixture.root).issue == .ambiguousAudio)
    try FileManager.default.removeItem(at: other)
    try FileManager.default.removeItem(at: fixture.audio)
    #expect(try await handler.read(fixture.candidate, root: fixture.root).issue == .missingAudio)
    try FileManager.default.createSymbolicLink(
      at: fixture.audio, withDestinationURL: fixture.markdown)
    let unsafe = try await handler.read(fixture.candidate, root: fixture.root)
    #expect(unsafe.issue == .unsafe)
    #expect(
      (unsafe.payload as? DiaryCatalogDetail)?.body
        == "A synthetic first sentence. Another sentence.")
  }

  @Test func streamingAudioValidatesRealContainerBoundsAndCancellation() throws {
    let fixture = try makeLegacy()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let components =
      Array(fixture.candidate.components.dropLast()) + [
        LegacyDiaryReaderTests.stem + ".assets", "synthetic.m4a",
      ]
    let inspected = try CatalogAudioInspector.inspect(
      root: fixture.root, components: components, maximumDuration: 3_600,
      control: CatalogReadControl())
    #expect(inspected.duration > 0)
    #expect(inspected.duration < 1)
    #expect(throws: CatalogIssue.self) {
      try CatalogAudioInspector.inspect(
        root: fixture.root, components: components, maximumDuration: inspected.duration / 2,
        control: CatalogReadControl())
    }
    let cancelled = CatalogReadControl()
    cancelled.cancel()
    #expect(throws: CatalogIssue.self) {
      try CatalogAudioInspector.inspect(
        root: fixture.root, components: components, maximumDuration: 3_600, control: cancelled)
    }
    let bytes = try Data(contentsOf: fixture.audio)
    try bytes.prefix(bytes.count / 2).write(to: fixture.audio)
    #expect(throws: CatalogIssue.self) {
      try CatalogAudioInspector.inspect(
        root: fixture.root, components: components, maximumDuration: 3_600,
        control: CatalogReadControl())
    }
  }

  @Test func canonicalV1PairHasFreshVersionAndMissingAudioIsRecovery() async throws {
    let fixture = try makeLegacy()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let id = try AssetID("123e4567-e89b-42d3-a456-426614174000")
    let instant = try SchemaInstant("2026-01-02T03:04:05Z")
    let layout = DiarySnippetLayout(id: id, createdAt: instant)
    let day = fixture.markdown.deletingLastPathComponent()
    let assets = day.appending(path: layout.assetsDirectoryName)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: false)
    try Data(contentsOf: fixture.audio).write(to: assets.appending(path: layout.audioFilename))
    let snippet = DiarySnippetV1(
      id: id, createdAt: instant, updatedAt: instant, title: "Synthetic diary",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil, osVersion: nil,
        modelID: nil),
      favorite: true, language: "en-US", audioFilename: layout.audioFilename,
      recordingDurationMilliseconds: 100, audioCodec: "aac", audioSampleRateHertz: 44_100,
      audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID("ndm.transcription.apple"), languageHint: "en-US",
        settingsRevision: 1, modelID: nil, modelVersion: nil, runtimeID: nil, conversionID: nil),
      location: nil, weather: nil, body: try DiaryBody("[Inert](https://example.invalid)"),
      preservedScalars: [])
    let markdown = day.appending(path: layout.markdownFilename)
    try DiarySnippetMarkdownCodec().encode(snippet).write(to: markdown)
    let candidate = try #require(
      handler.candidate(
        components: layout.directoryComponents + [layout.markdownFilename], safe: true))
    let value = try await handler.read(candidate, root: fixture.root)
    #expect(value.issue == nil)
    #expect(value.assetID == id.description)
    #expect((value.payload as? DiaryCatalogDetail)?.favorite == true)
    #expect((value.payload as? DiaryCatalogDetail)?.body == snippet.body.text)
    try FileManager.default.removeItem(at: assets.appending(path: layout.audioFilename))
    #expect(try await handler.read(candidate, root: fixture.root).issue == .missingAudio)
  }

  @Test func streamedLegacyHourAndNewSchemaLimitsUseActualFrames() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "synthetic.m4a")
    try writeHourAAC(url)
    let inspection = try CatalogAudioInspector.inspect(
      root: root, components: ["synthetic.m4a"], maximumDuration: 3_600,
      control: CatalogReadControl())
    #expect(inspection.duration == 3_600)
    #expect(throws: CatalogIssue.self) {
      try CatalogAudioInspector.inspect(
        root: root, components: ["synthetic.m4a"], maximumDuration: 301,
        control: CatalogReadControl())
    }
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(CatalogAudioInspector.maximumBytes + 1))
    try handle.close()
    #expect(throws: CatalogIssue.self) {
      try CatalogAudioInspector.inspect(
        root: root, components: ["synthetic.m4a"], maximumDuration: 3_600,
        control: CatalogReadControl())
    }
  }

  private func writeHourAAC(_ url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
    buffer.frameLength = 8_000
    if let samples = buffer.floatChannelData { samples[0].initialize(repeating: 0, count: 8_000) }
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 8_000,
        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 16_000,
      ])
    for _ in 0..<3_600 { try writer.write(from: buffer) }
  }

  @Test func plannedReadCoordinatesOnlyTheConfinedMarkdownAndUniqueAudio() throws {
    let fixture = try makeLegacy()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let control = CatalogReadControl()
    let plan = try handler.planRead(fixture.candidate, root: fixture.root, control: control)
    #expect(plan.files.count == 2)
    #expect(plan.audio.count == 1)
    control.allowAudio(plan.audio)
    let audio = try #require(plan.audio.first)
    try control.authorizeAudio(audio)
    #expect(throws: CatalogIssue.self) {
      try control.authorizeAudio(Array(audio.dropLast()) + ["unplanned.m4a"])
    }
  }

  struct Fixture {
    let root: URL
    let markdown: URL
    let audio: URL
    let candidate: CatalogCandidate
  }

  func makeLegacy() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let day = root.appending(path: "2026/01/02")
    let assets = day.appending(path: LegacyDiaryReaderTests.stem + ".assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let markdown = day.appending(path: LegacyDiaryReaderTests.stem + ".md")
    try Data(LegacyDiaryReaderTests.fixture.utf8).write(to: markdown)
    let audio = assets.appending(path: "synthetic.m4a")
    try writeAAC(audio)
    let candidate = try #require(
      handler.candidate(
        components: ["2026", "01", "02", LegacyDiaryReaderTests.stem + ".md"], safe: true))
    return Fixture(root: root, markdown: markdown, audio: audio, candidate: candidate)
  }

  private func writeAAC(_ url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
    buffer.frameLength = 4_410
    if let samples = buffer.floatChannelData { samples[0].initialize(repeating: 0, count: 4_410) }
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
      ])
    try writer.write(from: buffer)
  }
}

struct DiaryCatalogPagingTests {
  @Test func mixedPrecisionAndEqualTimesRemainOrderedAcrossPageBoundary() async throws {
    let fixture = try DiaryCatalogHandlerTests().makeLegacy()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    for number in (0..<55).reversed() { try writeCurrent(number, fixture: fixture) }
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    let session = CatalogSessionID()
    var cursor: CatalogCursor? = CatalogCursor(session: session, token: UUID())
    let worker = FileCatalogWorker(
      session: session, cursor: try #require(cursor), registry: registry)
    var summaries: [CatalogSummary] = []
    var requests = 0
    while let current = cursor {
      requests += 1
      guard requests < 20 else {
        Issue.record("Paging did not settle")
        return
      }
      let page = try await worker.page(current, root: fixture.root)
      #expect(page.examinedCandidates <= 50)
      #expect(page.recovery.isEmpty)
      summaries += page.summaries
      cursor = page.continuation
    }
    #expect(summaries.count == 56)
    #expect(summaries.first?.assetID == nil)
    let currentIDs = summaries.dropFirst().compactMap(\.assetID)
    #expect(currentIDs.count == 55)
    #expect(currentIDs == currentIDs.sorted())
  }

  private func writeCurrent(_ number: Int, fixture: DiaryCatalogHandlerTests.Fixture) throws {
    let id = try AssetID(String(format: "00000000-0000-4000-8000-%012d", number))
    let instant = try SchemaInstant("2026-01-02T03:04:05Z")
    let layout = DiarySnippetLayout(id: id, createdAt: instant)
    let day = fixture.markdown.deletingLastPathComponent()
    let assets = day.appending(path: layout.assetsDirectoryName)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: false)
    try Data(contentsOf: fixture.audio).write(to: assets.appending(path: layout.audioFilename))
    let snippet = DiarySnippetV1(
      id: id, createdAt: instant, updatedAt: instant, title: "Synthetic diary",
      titleProvenance: TitleProvenance(
        originID: try TitleOriginID("first-sentence"), promptRevision: nil, osVersion: nil,
        modelID: nil),
      favorite: false, language: "en-US", audioFilename: layout.audioFilename,
      recordingDurationMilliseconds: 100, audioCodec: "aac", audioSampleRateHertz: 44_100,
      audioChannels: 1, audioBitrateBPS: 64_000,
      transcription: TranscriptionProvenance(
        methodID: try TranscriptionMethodID("ndm.transcription.apple"), languageHint: "en-US",
        settingsRevision: 1, modelID: nil, modelVersion: nil, runtimeID: nil, conversionID: nil),
      location: nil, weather: nil, body: try DiaryBody("Synthetic"), preservedScalars: [])
    try DiarySnippetMarkdownCodec().encode(snippet).write(
      to: day.appending(path: layout.markdownFilename))
  }
}

// swiftlint:enable trailing_comma
