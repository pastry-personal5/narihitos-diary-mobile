// swiftlint:disable trailing_comma
import Darwin
import Foundation
import SQLite3
import Testing

@testable import NarihitosDiary

/// Opt-in measurements keep fixture creation and benchmark repetitions out of the normal test gate.
@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["NDM_CATALOG_BENCHMARK"] == "1"))
struct CatalogBenchmarkTests {
  @Test func metadataScale() async throws {
    for count in [0, 10, 11, 100, 1_000, 10_000] {
      let root = try makeMetadata(count: count)
      defer { try? FileManager.default.removeItem(at: root) }
      for repeatIndex in 0..<5 {
        let metrics = CatalogPerformanceProbe()
        var registry = CatalogAssetRegistry()
        registry.register(BenchmarkMetadataHandler())
        try await measure(
          root: root, registry: registry, metrics: metrics,
          count: count, sample: ("metadata", repeatIndex))
      }
    }
  }

  @Test func playableDiaryAudio() async throws {
    let template = try DiaryCatalogHandlerTests().makeLegacy()
    defer { try? FileManager.default.removeItem(at: template.root) }
    let audio = try Data(contentsOf: template.audio)
    for count in [10, 100] {
      let root = try makeDiaries(count: count, audio: audio)
      defer { try? FileManager.default.removeItem(at: root) }
      for repeatIndex in 0..<5 {
        let metrics = CatalogPerformanceProbe()
        var registry = CatalogAssetRegistry()
        registry.register(DiaryCatalogHandler(metrics: metrics))
        try await measure(
          root: root, registry: registry, metrics: metrics,
          count: count, sample: ("aac-100ms", repeatIndex))
      }
    }
  }

  @Test func systemSQLiteIsAvailableWithoutAdditionalBuildConfiguration() {
    #expect(sqlite3_libversion_number() >= 3_008_000)
  }

  private func measure(
    root: URL, registry: CatalogAssetRegistry, metrics: CatalogPerformanceProbe,
    count: Int, sample: (corpus: String, repeatIndex: Int)
  ) async throws {
    let (corpus, repeatIndex) = sample
    let clock = ContinuousClock()
    let start = clock.now
    let session = CatalogSessionID()
    var cursor: CatalogCursor? = CatalogCursor(session: session, token: UUID())
    let worker = FileCatalogWorker(
      session: session, cursor: try #require(cursor), registry: registry, metrics: metrics)
    var rows: [CatalogSummary] = []
    var pages = 0
    while let current = cursor, rows.count < min(count, 10) || count == 0 {
      let page = try await worker.page(current, root: root)
      #expect(page.examinedCandidates <= 50)
      #expect(page.continuation != current)
      #expect(page.recovery.isEmpty)
      pages += 1
      #expect(pages <= count / 10 + 100)
      rows += page.summaries
      cursor = page.continuation
      if count == 0, cursor == nil { break }
    }
    let elapsed = start.duration(to: clock.now)
    let milliseconds =
      Double(elapsed.components.seconds) * 1_000
      + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    #expect(rows.count >= min(count, 10))
    #expect(rows.map(\.createdAt) == rows.map(\.createdAt).sorted(by: >))
    let result: [String: Any] = [
      "corpus": corpus, "entries": count, "repeat": repeatIndex,
      "session": "fresh-worker-in-same-process", "millisecondsToFirstBatch": milliseconds,
      "rowsInFirstBatch": rows.count, "requests": pages, "counters": metrics.snapshot,
      "provider": "local-test-directory", "sqliteVersion": String(cString: sqlite3_libversion()),
      "debuggerAttached": try debuggerAttached(),
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print("CATALOG_BENCHMARK " + (try #require(String(data: data, encoding: .utf8))))
  }

  private func debuggerAttached() throws -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let result = sysctl(&query, UInt32(query.count), &info, &size, nil, 0)
    #expect(result == 0)
    let attached = (info.kp_proc.p_flag & P_TRACED) != 0
    #expect(!attached)
    return attached
  }

  func makeMetadata(count: Int) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let directory = root.appending(path: "notes")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for number in 0..<count {
      try Data("Synthetic".utf8).write(to: directory.appending(path: "\(number).note"))
    }
    return root
  }

  private func makeDiaries(count: Int, audio: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let instant = try SchemaInstant("2026-01-02T03:04:05Z")
    for number in 0..<count {
      let id = try AssetID(String(format: "00000000-0000-4000-8000-%012d", number))
      let layout = DiarySnippetLayout(id: id, createdAt: instant)
      let day = layout.directoryComponents.reduce(root) { $0.appending(path: $1) }
      let assets = day.appending(path: layout.assetsDirectoryName)
      try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
      try audio.write(to: assets.appending(path: layout.audioFilename))
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
    return root
  }
}

struct BenchmarkMetadataHandler: CatalogAssetHandler {
  let kind = "benchmark.metadata"
  func descends(into components: [String]) -> Bool { components == ["notes"] }
  func candidate(components: [String], safe: Bool) -> CatalogCandidate? {
    guard components.count == 2, components[0] == "notes",
      let name = components.last, name.hasSuffix(".note"),
      let number = Int(name.dropLast(5))
    else { return nil }
    return CatalogCandidate(
      components: components, handler: kind, date: Date(timeIntervalSince1970: Double(number)),
      stableID: String(format: "%06d", number), safe: safe)
  }

  func read(_ candidate: CatalogCandidate, root: URL) async throws -> CatalogReadValue {
    guard candidate.safe else { throw CatalogIssue.unsafe }
    let (_, version) = try CatalogSafeFiles.read(
      root: root, components: candidate.components, maximum: 1_024)
    return CatalogReadValue(
      version: version, assetID: candidate.stableID, createdAt: candidate.date,
      title: "Synthetic", favorite: nil, payload: nil, issue: nil, hasText: true, hasAudio: false)
  }
}

// swiftlint:enable trailing_comma
