import Darwin
import Foundation
import Testing

@testable import NarihitosDiary

struct DiaryFileObservationTests {
  @Test func metadataRaceWaitsWhileContentRaceRequiresReview() throws {
    var before = stat()
    before.st_dev = 1
    before.st_ino = 2
    before.st_size = 512
    before.st_mtimespec.tv_sec = 100
    before.st_ctimespec.tv_sec = 100
    var metadata = before
    metadata.st_ctimespec.tv_sec += 1
    do {
      try DiaryFileIdentity.requireStableRead(before, metadata)
      Issue.record("A ctime race must wait for a stable read")
    } catch DiaryFileObservationFailure.unavailable {}
    var content = metadata
    content.st_mtimespec.tv_nsec += 1
    do {
      try DiaryFileIdentity.requireStableRead(before, content)
      Issue.record("A content-version race must remain a conflict")
    } catch DiaryFileObservationFailure.changed {}
    var replacement = metadata
    replacement.st_ino += 1
    do {
      try DiaryFileIdentity.requireStableRead(before, replacement)
      Issue.record("A replacement inode must remain a conflict")
    } catch DiaryFileObservationFailure.changed {}
    try DiaryFileIdentity.requireStableRead(before, before)
  }

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
