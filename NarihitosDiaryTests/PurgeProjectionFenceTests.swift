import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct PurgeProjectionFenceTests {
  @Test(arguments: PurgeScope.allCases)
  func completionRetainsFenceAndWaitsForSettlement(_ scope: PurgeScope) async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    if scope == .internalStaging { try fixture.write("Captures/private") }
    try fixture.write("icloud/diary.md")
    let journal = fixture.support.appending(path: "purge-transaction.json")
    var held: CheckedContinuation<Void, Never>?
    let service = ApplePurgeService(
      destination: fixture.destination, support: fixture.support,
      protection: DiaryFixtureProtection(), protectedDataAvailable: { true },
      settleProjection: { await withCheckedContinuation { held = $0 } })
    let original = try service.projectionGeneration()
    let transaction = try await service.prepare(scope)
    try service.begin(transaction)
    #expect(throws: PurgeFailure.self) { try fixture.service().projectionGeneration() }
    let before = try JSONDecoder().decode(PurgeJournalRecord.self, from: Data(contentsOf: journal))
    #expect(before.projectionGeneration != nil)
    let purge = Task { try await service.perform(transaction) { _ in } }
    for _ in 0..<1_000 {
      if held != nil { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(held != nil)
    #expect(
      FileManager.default.fileExists(atPath: fixture.platform.url.appending(path: "diary.md").path))
    held?.resume()
    try await purge.value
    // Source success before completion publication is still an interrupted purge.
    #expect(try fixture.service().pendingTransaction() == transaction)
    #expect(throws: PurgeFailure.self) { try fixture.service().projectionGeneration() }
    try service.finish()
    let reopened = fixture.service()
    #expect(try reopened.pendingTransaction() == nil)
    #expect(try reopened.projectionGeneration() != original)
    #expect(try reopened.projectionGeneration() == before.projectionGeneration?.uuidString)
    let completed = try JSONDecoder().decode(
      PurgeJournalRecord.self, from: Data(contentsOf: journal))
    #expect(completed.sourceCompleted == true)
    #expect(
      FileManager.default.fileExists(atPath: fixture.platform.url.appending(path: "diary.md").path)
        == (scope == .internalStaging))
  }

  @Test func legacyIntentGainsFenceBeforeAnySourceRemovalAndRepeatedPurgeChangesIt() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    try fixture.write("Captures/private")
    let transaction = PurgeTransaction(scope: .internalStaging, destinationID: nil)
    let journal = fixture.support.appending(path: "purge-transaction.json")
    try JSONEncoder().encode(transaction).write(to: journal)
    let service = fixture.service()
    #expect(try service.pendingTransaction() == transaction)
    #expect(throws: PurgeFailure.self) { try service.projectionGeneration() }
    try await service.perform(transaction) { _ in }
    try service.finish()
    let first = try service.projectionGeneration()
    let second = try await service.prepare(.internalStaging)
    try service.begin(second)
    try await service.perform(second) { _ in }
    try service.finish()
    #expect(try service.projectionGeneration() != first)
  }

  @Test func invalidCompletionAndCorruptCompletedRecordFailClosed() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    let journal = fixture.support.appending(path: "purge-transaction.json")
    let invalid = "{\"scope\":\"internalStaging\",\"sourceCompleted\":true}"
    try Data(invalid.utf8).write(to: journal)
    #expect(throws: PurgeFailure.self) { try fixture.service().pendingTransaction() }
    #expect(throws: PurgeFailure.self) { try fixture.service().projectionGeneration() }
    #expect(FileManager.default.fileExists(atPath: journal.path))
  }
}
