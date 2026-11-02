import Foundation
import Testing

@testable import NarihitosDiary

struct DiaryFileObservationTests {
  @Test func localFileCannotMasqueradeAsUploadedICloudFile() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "entry.md")
    try Data("# entry".utf8).write(to: file)

    let observation = try AppleDiaryFileObserver().observe(file, maximumBytes: 1_024)
    #expect(observation.uploaded == false)
    #expect(observation.byteCount == 7)
  }

  @Test func cachedResourceMetadataIsRefreshedBeforeObservation() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "entry.md")
    try Data("# entry".utf8).write(to: file)
    let original = Date(timeIntervalSince1970: 100)
    let updated = Date(timeIntervalSince1970: 200)
    try FileManager.default.setAttributes([.modificationDate: original], ofItemAtPath: file.path)
    #expect(
      try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        == original)
    try FileManager.default.setAttributes([.modificationDate: updated], ofItemAtPath: file.path)

    let observation = try AppleDiaryFileObserver().observe(file, maximumBytes: 1_024)
    #expect(observation.modifiedAt == updated)
    #expect(observation.uploaded == false)
  }

  @Test func missingProviderFileRemainsRetryable() throws {
    let file = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString).appending(path: "missing.md")
    do {
      _ = try AppleDiaryFileObserver().observe(file, maximumBytes: 1_024)
      Issue.record("A missing provider file must wait for access")
    } catch DiaryFileObservationFailure.unavailable {
      // A temporarily unavailable resource must not be classified as unsafe.
    }
  }

  @Test func symbolicLinkCannotBeAnUploadVersion() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appending(path: "target.md")
    let link = root.appending(path: "link.md")
    try Data("# entry".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(throws: DiaryFileObservationFailure.self) {
      _ = try AppleDiaryFileObserver().observe(link, maximumBytes: 1_024)
    }
  }

  @Test func boundedObservationKeepsLocalUploadFlagFalse() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "entry.md")
    try Data("# entry".utf8).write(to: file)

    let observation = try await AppleDiaryFileObserver().observeBounded(
      file, maximumBytes: 1_024, timeout: .seconds(5))
    #expect(observation.uploaded == false)
    #expect(observation.byteCount == 7)
  }
}
