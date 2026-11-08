import Foundation
import Testing

@testable import NarihitosDiary

actor CatalogReadProbe {
  private(set) var keys: [String] = []
  private var holdNext = false
  private var held: CheckedContinuation<Void, Never>?
  var isHeld: Bool { held != nil }
  func hold() { holdNext = true }
  func release() {
    held?.resume()
    held = nil
  }
  func read(_ key: String) async {
    keys.append(key)
    if holdNext {
      holdNext = false
      await withCheckedContinuation { held = $0 }
    }
  }
}

struct ReconciliationFixturePayload: CatalogDetailPayload { let text: String }

struct ReconciliationBucketHandler: CatalogAssetHandler {
  let kind = "test.buckets"
  let probe: CatalogReadProbe
  var duplicateNumber: Int?
  var bounded = true

  func descends(into components: [String]) -> Bool {
    DiaryCatalogHandler().descends(into: components)
  }

  func unexploredDateUpperBound(in components: [String]) -> Date? {
    bounded ? DiaryCatalogHandler().unexploredDateUpperBound(in: components) : nil
  }

  func candidate(components: [String], safe: Bool) -> CatalogCandidate? {
    guard components.count == 4, let name = components.last, name.hasSuffix(".note"),
      let number = Int(name.dropLast(5)),
      let day = DiaryCatalogHandler().unexploredDateUpperBound(in: Array(components.dropLast()))
    else { return nil }
    let id =
      duplicateNumber == number ? "duplicate" : "synthetic-" + components.joined(separator: "-")
    return CatalogCandidate(
      components: components, handler: kind, date: day.addingTimeInterval(-86_400 + Double(number)),
      stableID: id, safe: safe)
  }

  func read(_ candidate: CatalogCandidate, root: URL) async throws -> CatalogReadValue {
    await probe.read(candidate.key)
    guard candidate.safe else { throw CatalogIssue.unsafe }
    let (bytes, version) = try CatalogSafeFiles.read(
      root: root, components: candidate.components, maximum: 1_024)
    let text = try #require(String(data: bytes, encoding: .utf8))
    if text == "unavailable" { throw CatalogIssue.unavailable }
    return CatalogReadValue(
      version: version, assetID: candidate.stableID, createdAt: candidate.date,
      title: text == "bad" ? nil : text, favorite: nil,
      payload: ReconciliationFixturePayload(text: text), issue: text == "bad" ? .malformed : nil,
      hasText: true, hasAudio: false)
  }
}

func makeReconciliationFixture(_ days: [Int: Int]) throws -> URL {
  let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  for day in days.keys.sorted() {
    let directory = root.appending(path: String(format: "2026/01/%02d", day))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for number in 0..<(days[day] ?? 0) {
      try Data("Synthetic".utf8).write(to: directory.appending(path: "\(number).note"))
    }
  }
  return root
}
