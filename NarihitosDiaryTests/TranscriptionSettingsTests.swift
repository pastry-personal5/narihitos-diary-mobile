import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct TranscriptionSettingsTests {
  @Test func selectionIsExplicitGlobalAndSurvivesRelaunch() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    let settings = ProductionTranscriptionSettings(repository: repository)
    #expect(settings.selectedMethodID(for: .english) == nil)
    #expect(settings.selectedMethodID(for: .korean) == nil)
    try repository.selectTranscriptionMethod("ndm.transcription.apple")
    let reopened = PrivateSettingsRepository(root: root)
    let restored = ProductionTranscriptionSettings(repository: reopened)
    #expect(restored.selectedMethodID(for: .english) == "ndm.transcription.apple")
    #expect(restored.selectedMethodID(for: .korean) == "ndm.transcription.apple")
  }

  @Test func invalidSelectionDoesNotReplacePreviousChoice() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    try repository.selectTranscriptionMethod("ndm.transcription.apple")
    #expect(throws: (any Error).self) { try repository.selectTranscriptionMethod("../unsafe") }
    #expect(repository.selectedTranscriptionMethodID() == "ndm.transcription.apple")
  }

  @Test func settingsWithoutASelectionPreserveEarlierOnboardingState() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    let progress = FirstLaunchProgress(
      step: .complete, microphoneAttempted: true, locationAttempted: true)
    try repository.saveFirstLaunchProgress(progress)
    let file = root.appending(path: "private-settings.json")
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(object["selectedTranscriptionMethodID"] == nil)
    let reopened = PrivateSettingsRepository(root: root)
    #expect(reopened.loadFirstLaunchProgress() == progress)
    #expect(reopened.selectedTranscriptionMethodID() == nil)
  }

  @Test func appleAttemptSettingsRecordTheRequestedLanguageAndNeverInventAModel() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let settings = ProductionTranscriptionSettings(
      repository: PrivateSettingsRepository(root: root))
    let snapshot = settings.effectiveSettings(
      methodID: TranscriptionMethodIdentifiers.apple, language: .korean)
    #expect(snapshot.values["settingsRevision"] == "1")
    #expect(snapshot.values["requestedLocale"] == "ko-KR")
    #expect(snapshot.values["preset"] == "transcription")
    #expect(snapshot.values["resultPolicy"] == "final-only")
    #expect(snapshot.values["runtime"] == "apple-speech-analyzer")
    #expect(snapshot.modelIdentity == nil)
    #expect(snapshot.conversionIdentity == "ndm.apple-speech.av-audio-file-v1")
  }
}
