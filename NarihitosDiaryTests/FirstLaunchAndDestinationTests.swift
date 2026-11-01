import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct FirstLaunchAndDestinationTests {
  @Test func destinationIdentityRequiresCanonicalOpaqueUUID() {
    let canonical = "85e7b8c2-74fa-4c36-a75f-705cb068d589"
    #expect(DestinationID(rawValue: canonical)?.rawValue == canonical)
    #expect(DestinationID(rawValue: canonical.uppercased()) == nil)
    #expect(DestinationID(rawValue: "folder/name") == nil)
  }

  @Test func folderProjectionIsBoundedSingleLineAndDirectionSafe() {
    let projected = SafeFolderDisplayName.project("  private\n\u{202E}name\u{0000}  ")
    #expect(projected == "private name")
    #expect(!projected.contains("\n"))
    #expect(!projected.contains("\u{202E}"))
    #expect(SafeFolderDisplayName.project("") == "Selected Folder")
    #expect(
      SafeFolderDisplayName.project(String(repeating: "a", count: 100)).count
        == SafeFolderDisplayName.maximumLength)
  }

  @Test func freshLaunchMarksAttemptsBeforeEachRequestAndCompletes() async {
    let microphone = FakeMicrophone()
    let location = FakeLocation()
    let store = FakeFirstLaunchStore()
    microphone.onRequest = { #expect(store.saved.last?.microphoneAttempted == true) }
    location.onRequest = { #expect(store.saved.last?.locationAttempted == true) }
    let coordinator = FirstLaunchCoordinator(
      microphone: microphone, location: location, store: store)

    #expect(coordinator.pendingExplanation == .microphone)
    await coordinator.continueCurrentStep()
    #expect(coordinator.pendingExplanation == .location)
    await coordinator.continueCurrentStep()
    await waitUntil { microphone.requestCount == 1 && location.requestCount == 1 }

    #expect(coordinator.progress.step == .complete)
    #expect(microphone.requestCount == 1)
    #expect(location.requestCount == 1)
  }

  @Test func attemptedUndeterminedPermissionNeverPromptsAgainAfterRelaunch() async {
    let microphone = FakeMicrophone()
    let location = FakeLocation()
    let store = FakeFirstLaunchStore(
      progress: FirstLaunchProgress(
        step: .microphone, microphoneAttempted: true, locationAttempted: true))
    let coordinator = FirstLaunchCoordinator(
      microphone: microphone, location: location, store: store)

    #expect(coordinator.progress.step == .complete)
    #expect(coordinator.pendingExplanation == nil)
    await coordinator.continueCurrentStep()
    #expect(microphone.requestCount == 0)
    #expect(location.requestCount == 0)
  }

  @Test func decidedPermissionsSkipPromptsAndReachRoot() {
    let microphone = FakeMicrophone(state: .denied)
    let location = FakeLocation(state: .restricted)
    let coordinator = FirstLaunchCoordinator(
      microphone: microphone, location: location, store: FakeFirstLaunchStore())

    #expect(coordinator.progress.step == .complete)
    #expect(coordinator.pendingExplanation == nil)
    #expect(microphone.requestCount == 0)
    #expect(location.requestCount == 0)
  }

  @Test func failedAttemptPersistencePreventsSystemRequest() async {
    let microphone = FakeMicrophone()
    let store = FakeFirstLaunchStore()
    store.shouldFail = true
    let coordinator = FirstLaunchCoordinator(
      microphone: microphone, location: FakeLocation(), store: store)

    await coordinator.continueCurrentStep()

    #expect(microphone.requestCount == 0)
    #expect(!coordinator.progress.microphoneAttempted)
    #expect(coordinator.progress.step == .microphone)
  }

  @Test func requestWithoutCallbackDoesNotBlockFirstLaunchProgress() async {
    let microphone = FakeMicrophone()
    microphone.suspendsRequest = true
    let coordinator = FirstLaunchCoordinator(
      microphone: microphone, location: FakeLocation(), store: FakeFirstLaunchStore())

    await coordinator.continueCurrentStep()
    await waitUntil { microphone.hasSuspendedRequest }

    #expect(coordinator.progress.step == .location)
    #expect(coordinator.pendingExplanation == .location)
    #expect(microphone.requestCount == 1)
    #expect(microphone.hasSuspendedRequest)
    microphone.finishSuspendedRequest()
  }

  @Test func privateSettingsRoundTripAndCorruptInputFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    try repository.saveFirstLaunchProgress(
      FirstLaunchProgress(step: .complete, microphoneAttempted: true, locationAttempted: true))
    let id = DestinationID.make()
    try repository.saveDestination(
      StoredDestinationRecord(
        id: id.rawValue,
        displayName: "Diary",
        bookmark: Data([1, 2, 3]),
        identityArchive: Data([4, 5, 6]),
        disclosureAcknowledged: true))

    let restored = PrivateSettingsRepository(root: root)
    #expect(restored.loadFirstLaunchProgress().step == .complete)
    #expect(restored.loadDestination()?.id == id.rawValue)

    let file = root.appendingPathComponent("private-settings.json")
    try Data("not json".utf8).write(to: file, options: .atomic)
    let corrupt = PrivateSettingsRepository(root: root)
    #expect(corrupt.loadDestination() == nil)
    #expect(corrupt.loadFirstLaunchProgress() == FirstLaunchProgress())
  }

  @Test func recordPrerequisitesKeepPermissionAndDestinationIndependent() {
    let id = DestinationID.make()
    let accessible = ActiveDestination(
      summary: DestinationSummary(id: id, displayName: "Diary"), accessState: .accessible)
    #expect(RecordPrerequisites(microphone: .authorized, destination: accessible).allowsCapture)
    #expect(!RecordPrerequisites(microphone: .denied, destination: accessible).allowsCapture)
    #expect(
      !RecordPrerequisites(
        microphone: .authorized,
        destination: ActiveDestination(
          summary: accessible.summary, accessState: .temporarilyUnavailable)
      ).allowsCapture)
  }

  @Test func candidatePredicateFailsClosedForEveryMissingSignal() {
    let accepted = DestinationCandidateFacts(
      isDirectory: true,
      isSymbolicLink: false,
      isUbiquitousItem: true,
      hasICloudIdentity: true)
    #expect(throws: Never.self) { try AppleDestinationService.validate(accepted) }

    // swiftlint:disable trailing_comma
    let rejected = [
      DestinationCandidateFacts(
        isDirectory: false,
        isSymbolicLink: false,
        isUbiquitousItem: true,
        hasICloudIdentity: true),
      DestinationCandidateFacts(
        isDirectory: nil,
        isSymbolicLink: false,
        isUbiquitousItem: true,
        hasICloudIdentity: true),
      DestinationCandidateFacts(
        isDirectory: true,
        isSymbolicLink: true,
        isUbiquitousItem: true,
        hasICloudIdentity: true),
      DestinationCandidateFacts(
        isDirectory: true,
        isSymbolicLink: nil,
        isUbiquitousItem: true,
        hasICloudIdentity: true),
      DestinationCandidateFacts(
        isDirectory: true,
        isSymbolicLink: false,
        isUbiquitousItem: false,
        hasICloudIdentity: true),
      DestinationCandidateFacts(
        isDirectory: true,
        isSymbolicLink: false,
        isUbiquitousItem: nil,
        hasICloudIdentity: true),
      DestinationCandidateFacts(
        isDirectory: true,
        isSymbolicLink: false,
        isUbiquitousItem: true,
        hasICloudIdentity: false),
    ]
    // swiftlint:enable trailing_comma
    for facts in rejected {
      #expect(throws: DestinationValidationError.self) {
        try AppleDestinationService.validate(facts)
      }
    }
  }

  @Test func inwardSourceFilesDoNotImportPlatformOrPresentationFrameworks() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
    // swiftlint:disable trailing_comma
    let files = [
      root.appendingPathComponent("NarihitosDiary/Domain/AccessValues.swift"),
      root.appendingPathComponent("NarihitosDiary/Application/AccessPorts.swift"),
    ]
    // swiftlint:enable trailing_comma
    let forbidden = ["SwiftUI", "UIKit", "AVFoundation", "CoreLocation", "FileProvider"]
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      for framework in forbidden {
        #expect(!source.contains("import \(framework)"))
      }
    }
  }

  private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 {
      if condition() { return }
      await Task.yield()
    }
  }
}

@MainActor
private final class FakeMicrophone: MicrophoneAuthorizationPort {
  var state: PermissionState
  var requestCount = 0
  var onRequest: (() -> Void)?
  var suspendsRequest = false
  private var suspendedContinuation: CheckedContinuation<PermissionState, Never>?

  var hasSuspendedRequest: Bool { suspendedContinuation != nil }

  init(state: PermissionState = .notDetermined) {
    self.state = state
  }

  func currentState() -> PermissionState { state }

  func requestAccess() async -> PermissionState {
    requestCount += 1
    onRequest?()
    if suspendsRequest {
      return await withCheckedContinuation { continuation in
        suspendedContinuation = continuation
      }
    }
    return state
  }

  func finishSuspendedRequest() {
    suspendedContinuation?.resume(returning: state)
    suspendedContinuation = nil
  }
}

@MainActor
private final class FakeLocation: LocationAuthorizationPort {
  var state: PermissionState
  var requestCount = 0
  var onRequest: (() -> Void)?

  init(state: PermissionState = .notDetermined) {
    self.state = state
  }

  func currentState() -> PermissionState { state }

  func requestWhenInUse() async -> PermissionState {
    requestCount += 1
    onRequest?()
    return state
  }
}

@MainActor
private final class FakeFirstLaunchStore: FirstLaunchStorePort {
  var progress: FirstLaunchProgress
  var saved: [FirstLaunchProgress] = []
  var shouldFail = false

  init(progress: FirstLaunchProgress = FirstLaunchProgress()) {
    self.progress = progress
  }

  func loadFirstLaunchProgress() -> FirstLaunchProgress { progress }

  func saveFirstLaunchProgress(_ progress: FirstLaunchProgress) throws {
    if shouldFail { throw CocoaError(.fileWriteUnknown) }
    self.progress = progress
    saved.append(progress)
  }
}
