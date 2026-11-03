import Foundation
import Testing

@testable import NarihitosDiary

struct DiaryEditCleanupTests {
  private func completedFixture() async throws -> (EditStorageFixture, DiaryEditRecord) {
    let fixture = try await DiaryEditStorageTests().fixture()
    let ready = try await fixture.journal.finalize(fixture.record, candidate: fixture.snippet)
    guard
      case .verified(let version) = try await DiaryEditPublicationAdapter.publish(
        ready, binding: fixture.binding, candidate: fixture.snippet, root: fixture.root,
        files: fixture.files)
    else { throw DiaryEditIssue.changed }
    var record = ready
    record.stage = .published
    record.publishedVersion = version
    try await fixture.journal.checkpoint(record)
    record.markdownUploaded = true
    record.audioUploaded = true
    record.stage = .completed
    try await fixture.journal.checkpoint(record)
    return (fixture, record)
  }

  @Test(arguments: ["audio.m4a", "retirement-receipt"])
  func interruptedCleanupResumesAfterLastPayloadAndReceipt(fault: String) async throws {
    let (fixture, record) = try await completedFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let path =
      Array(fixture.candidate.components.dropLast()) + [
        try CommittedDiaryResource.requiredStem(fixture.candidate) + ".md"
      ]
    let (_, before) = try CatalogSafeFiles.read(
      root: fixture.root, components: path, maximum: 1_114_122)
    try await interruptRetirement(fixture, record: record, at: fault)
    let reopened = DiaryEditJournal(files: fixture.files)
    let page = try await reopened.inventory(after: nil, installation: record.installationBinding)
    #expect(page.records.isEmpty)
    #expect(page.isolatedCount == 0)
    #expect(try PurgeFileTree.isEmpty(fixture.files.root))
    try await reopened.assertAvailable(resourceKey: record.resourceKey)
    let (_, after) = try CatalogSafeFiles.read(
      root: fixture.root, components: path, maximum: 1_114_122)
    #expect(before == after)
  }

  @Test func restoredCleanupReceiptCannotDeleteBeforeInstallationReview() async throws {
    let (fixture, record) = try await completedFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await interruptRetirement(fixture, record: record, at: "audio.m4a")
    let before = try FileManager.default.contentsOfDirectory(atPath: fixture.files.root.path)
      .sorted()
    let reopened = DiaryEditJournal(files: fixture.files)
    let page = try await reopened.inventory(after: nil, installation: "another-installation")
    #expect(page.isolatedCount > 0)
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: fixture.files.root.path).sorted()
        == before)
  }

  @Test(arguments: [false, true])
  func replacedRetiredPayloadCannotPassVersionCheck(useSymbolicLink: Bool) async throws {
    let (fixture, record) = try await completedFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let outside = fixture.root.appending(path: "outside-cleanup.txt")
    let outsideBytes = Data("Synthetic outside content.".utf8)
    try outsideBytes.write(to: outside)
    let retired = fixture.files.root.appending(
      path: "completed-" + record.id.uuidString.lowercased())
    var target: URL?
    #expect(throws: DiaryEditIssue.changed) {
      try fixture.files.remove(record) { child in
        guard target == nil else { return }
        let replacement = retired.appending(path: child)
        target = replacement
        if useSymbolicLink {
          try FileManager.default.removeItem(at: replacement)
          try FileManager.default.createSymbolicLink(at: replacement, withDestinationURL: outside)
        } else {
          let bytes = try Data(contentsOf: replacement)
          try bytes.write(to: replacement, options: .atomic)
        }
      }
    }
    let replaced = try #require(target)
    #expect(FileManager.default.fileExists(atPath: replaced.path))
    #expect(try Data(contentsOf: outside) == outsideBytes)
    #expect(try fixture.files.cleanupReceiptExists(record.id))
  }

  private func interruptRetirement(
    _ fixture: EditStorageFixture, record: DiaryEditRecord, at fault: String
  ) async throws {
    var injected = false
    for _ in 0..<5 {
      do {
        try fixture.files.remove(record) { name in
          if name == fault {
            injected = true
            throw DiaryEditIssue.storage
          }
        }
        Issue.record("Expected the injected cleanup fault")
        return
      } catch {
        if injected {
          #expect(error as? DiaryEditIssue == .storage)
          return
        }
        // iPhone metadata can settle between observations. Preserve the exact
        // checks and resume the receipt before injecting the requested fault.
        guard error as? DiaryEditIssue == .changed else { throw error }
        #expect(try fixture.files.cleanupReceiptExists(record.id))
        await Task.yield()
      }
    }
    throw DiaryEditIssue.busy
  }
}
