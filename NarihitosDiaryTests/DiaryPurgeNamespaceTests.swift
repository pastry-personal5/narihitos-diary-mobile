import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct DiaryPurgeNamespaceTests {
  @Test func emptyEditReplayNamespacesDoNotBlockFolderPurgeButAnyArtifactDoes() async throws {
    let fixture = try PurgeDiskFixture()
    defer { fixture.close() }
    for namespace in ["DiaryEdits", "DiaryReplay"] {
      try FileManager.default.createDirectory(
        at: fixture.support.appending(path: "PrivateWorkspaces/" + namespace),
        withIntermediateDirectories: true)
    }
    _ = try await fixture.service().prepare(.activeFolder)
    try fixture.write("PrivateWorkspaces/DiaryEdits/pending-candidate")
    await #expect(throws: PurgeFailure.pendingWork) {
      try await fixture.service().prepare(.activeFolder)
    }
    let service = fixture.service()
    let transaction = try await service.prepare(.internalStaging)
    try service.begin(transaction)
    try await service.perform(transaction) { _ in }
    try service.finish()
    _ = try await service.prepare(.activeFolder)
  }
}
