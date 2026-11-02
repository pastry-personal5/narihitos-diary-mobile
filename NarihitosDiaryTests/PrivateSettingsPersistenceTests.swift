import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct PrivateSettingsPersistenceTests {
  @Test func firstLaunchReloadsPersistedAttemptsWhenPrivateSettingsBecomeReadable() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    try repository.saveFirstLaunchProgress(
      FirstLaunchProgress(step: .complete, microphoneAttempted: true, locationAttempted: true))
    let file = root.appending(path: "private-settings.json")
    let retained = root.appending(path: "retained-settings.json")
    try FileManager.default.moveItem(at: file, to: retained)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    let permissions = SettingsPermissions()
    let coordinator = FirstLaunchCoordinator(
      microphone: permissions, location: permissions, store: repository)
    #expect(coordinator.pendingExplanation == .microphone)

    try FileManager.default.removeItem(at: file)
    try FileManager.default.moveItem(at: retained, to: file)
    coordinator.refresh()

    #expect(coordinator.pendingExplanation == nil)
    #expect(coordinator.progress.microphoneAttempted)
    #expect(coordinator.progress.locationAttempted)
  }

  @Test func repositoryInstancesPreserveEachOthersCommittedSettings() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = PrivateSettingsRepository(root: root)
    let second = PrivateSettingsRepository(root: root)
    let destination = storedDestination()

    try first.saveDestination(destination)
    try second.selectTranscriptionMethod(TranscriptionMethodIdentifiers.apple)
    try first.saveFirstLaunchProgress(FirstLaunchProgress(step: .complete))

    let reopened = PrivateSettingsRepository(root: root)
    #expect(reopened.loadDestination() == destination)
    #expect(reopened.selectedTranscriptionMethodID() == TranscriptionMethodIdentifiers.apple)
    #expect(reopened.loadFirstLaunchProgress().step == .complete)
  }

  @Test func allSettingsSurviveSuccessiveUpdatesAndReopening() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    let destination = storedDestination()
    let progress = FirstLaunchProgress(
      step: .complete, microphoneAttempted: true, locationAttempted: true)

    try repository.saveDestination(destination)
    try repository.saveFirstLaunchProgress(progress)
    try repository.selectTranscriptionMethod(TranscriptionMethodIdentifiers.apple)

    let reopened = PrivateSettingsRepository(root: root)
    #expect(reopened.loadDestination() == destination)
    #expect(reopened.loadFirstLaunchProgress() == progress)
    #expect(reopened.selectedTranscriptionMethodID() == TranscriptionMethodIdentifiers.apple)
  }

  @Test func temporarilyUnreadableSettingsAreRetriedWithoutLosingSavedValues() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = PrivateSettingsRepository(root: root)
    let destination = storedDestination()
    try original.saveDestination(destination)
    let file = root.appending(path: "private-settings.json")
    let retained = root.appending(path: "retained-settings.json")
    try FileManager.default.moveItem(at: file, to: retained)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

    let recovering = PrivateSettingsRepository(root: root)
    #expect(recovering.loadDestination() == nil)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.moveItem(at: retained, to: file)

    #expect(recovering.loadDestination() == destination)
    try recovering.selectTranscriptionMethod(TranscriptionMethodIdentifiers.apple)
    #expect(PrivateSettingsRepository(root: root).loadDestination() == destination)
  }

  @Test func unreadableOrCorruptSettingsCannotBeOverwrittenWithDefaults() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appending(path: "private-settings.json")
    let original = Data("not valid settings".utf8)
    try original.write(to: file)
    let repository = PrivateSettingsRepository(root: root)

    #expect(repository.loadDestination() == nil)
    #expect(throws: (any Error).self) {
      try repository.selectTranscriptionMethod(TranscriptionMethodIdentifiers.apple)
    }
    #expect(throws: (any Error).self) {
      try repository.saveDestination(storedDestination())
    }
    #expect(throws: (any Error).self) {
      try repository.saveFirstLaunchProgress(FirstLaunchProgress(step: .complete))
    }
    #expect(try Data(contentsOf: file) == original)
  }

  @Test func failedWriteRetainsCommittedSettingsAndCanBeRetried() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    let destination = storedDestination()
    try repository.saveDestination(destination)
    let file = root.appending(path: "private-settings.json")
    let retained = root.appending(path: "retained-settings.json")
    try FileManager.default.moveItem(at: file, to: retained)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

    #expect(throws: (any Error).self) {
      try repository.selectTranscriptionMethod(TranscriptionMethodIdentifiers.apple)
    }
    try FileManager.default.removeItem(at: file)
    try FileManager.default.moveItem(at: retained, to: file)
    #expect(repository.loadDestination() == destination)
    #expect(repository.selectedTranscriptionMethodID() == nil)
    try repository.selectTranscriptionMethod(TranscriptionMethodIdentifiers.apple)
    let reopened = PrivateSettingsRepository(root: root)
    #expect(reopened.loadDestination() == destination)
    #expect(reopened.selectedTranscriptionMethodID() == TranscriptionMethodIdentifiers.apple)
  }

  @Test func settingsDirectoryCreationRecoversBeforeSaving() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = PrivateSettingsRepository(root: root)
    try FileManager.default.removeItem(at: root)

    let destination = storedDestination()
    try repository.saveDestination(destination)

    #expect(PrivateSettingsRepository(root: root).loadDestination() == destination)
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID())")
  }

  private func storedDestination() -> StoredDestinationRecord {
    StoredDestinationRecord(
      id: DestinationID.make().rawValue, displayName: "Synthetic Diary",
      bookmark: Data([0x01]), identityArchive: Data([0x02]), disclosureAcknowledged: true)
  }
}

@MainActor
private final class SettingsPermissions: MicrophoneAuthorizationPort, LocationAuthorizationPort {
  func currentState() -> PermissionState { .notDetermined }
  func requestAccess() async -> PermissionState { .notDetermined }
  func requestWhenInUse() async -> PermissionState { .notDetermined }
}
