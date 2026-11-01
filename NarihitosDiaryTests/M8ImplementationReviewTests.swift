import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct M8ImplementationReviewTests {
  @Test func oversizedPrivateSettingsInputFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("private-settings.json")
    try Data(repeating: 0x41, count: 129 * 1_024).write(to: file, options: .atomic)

    let repository = PrivateSettingsRepository(root: root)

    #expect(repository.loadDestination() == nil)
    #expect(repository.loadFirstLaunchProgress() == FirstLaunchProgress())
  }

  @Test func restoredDestinationDisplayNameIsSanitizedBeforeErrorProjection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PrivateSettingsRepository(root: root)
    try repository.saveDestination(
      StoredDestinationRecord(
        id: DestinationID.make().rawValue,
        displayName: "private\n\u{202E}name",
        bookmark: Data([0x01]),
        identityArchive: Data([0x02]),
        disclosureAcknowledged: true))

    let destination = await AppleDestinationService(repository: repository).activeDestination()

    #expect(destination.summary?.displayName == "private name")
    #expect(destination.accessState != .accessible)
  }

  @Test func recordDenialOffersExplicitSettingsRecovery() async {
    let settings = ReviewSystemSettings()
    let model = makeModel(
      microphone: ReviewMicrophone(state: .denied),
      systemSettings: settings)

    await model.handleRecord()

    #expect(model.offersSettingsRecovery)
    #expect(model.message?.contains("Microphone access is required") == true)
    model.openSettings()
    #expect(settings.openCount == 1)
    #expect(model.message == nil)
    #expect(!model.offersSettingsRecovery)
  }

  @Test func recordChecksCurrentDestinationBeforeReportingUnavailableCapture() async {
    let id = DestinationID.make()
    let destination = ReviewDestinationService(
      active: ActiveDestination(
        summary: DestinationSummary(id: id, displayName: "Diary"), accessState: .accessible))
    let model = makeModel(
      microphone: ReviewMicrophone(state: .authorized),
      destinationService: destination)

    await model.handleRecord()

    #expect(destination.activeRequestCount == 1)
    #expect(model.message == "Recording is not available yet.")
    #expect(!model.offersSettingsRecovery)
  }

  @Test func firstRecordGrantRechecksLiveFolderBeforeRouting() async {
    let microphone = ReviewMicrophone(state: .notDetermined)
    microphone.requestResult = .authorized
    let destination = ReviewDestinationService()
    let model = makeModel(microphone: microphone, destinationService: destination)

    await model.handleRecord()

    #expect(microphone.requestCount == 1)
    #expect(destination.activeRequestCount == 1)
    #expect(model.isFolderPickerPresented)
    #expect(model.message == nil)
  }

  @Test func disclosureDismissalWriteDoesNotDiscardAcceptedFolder() {
    let prepared = PreparedDestination(
      id: UUID(), displayName: "Diary", needsDisclosure: true)
    let summary = DestinationSummary(id: DestinationID.make(), displayName: "Diary")
    let destination = ReviewDestinationService()
    destination.prepareOutcome = .prepared(prepared)
    destination.commitOutcome = .committed(summary)
    let model = makeModel(
      microphone: ReviewMicrophone(state: .authorized),
      destinationService: destination)

    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"))
    #expect(model.disclosurePresented.wrappedValue)

    model.disclosurePresented.wrappedValue = false
    model.acceptDisclosure()

    #expect(destination.cancelledIDs.isEmpty)
    #expect(destination.committedIDs == [prepared.id])
    #expect(model.destination == ActiveDestination(summary: summary, accessState: .accessible))
  }

  @Test func disclosureCancelStillDiscardsPreparedFolder() {
    let prepared = PreparedDestination(
      id: UUID(), displayName: "Diary", needsDisclosure: true)
    let destination = ReviewDestinationService()
    destination.prepareOutcome = .prepared(prepared)
    let model = makeModel(
      microphone: ReviewMicrophone(state: .authorized),
      destinationService: destination)

    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"))
    model.cancelDisclosure()

    #expect(destination.cancelledIDs == [prepared.id])
    #expect(destination.committedIDs.isEmpty)
    #expect(model.preparedDestination == nil)
  }

  @Test func activationRefreshesLivePermissionsAndDestination() async {
    let microphone = ReviewMicrophone(state: .denied)
    let location = ReviewLocation(state: .restricted)
    let summary = DestinationSummary(id: DestinationID.make(), displayName: "Diary")
    let destination = ReviewDestinationService(
      active: ActiveDestination(summary: summary, accessState: .accessible))
    let model = makeModel(
      microphone: microphone,
      location: location,
      destinationService: destination)
    microphone.state = .authorized
    location.state = .authorized

    await model.becameActive()

    #expect(model.microphoneState == .authorized)
    #expect(model.locationState == .authorized)
    #expect(model.destination.summary == summary)
    #expect(destination.activeRequestCount == 1)
  }

  @Test func explicitLocationRequestRunsOnlyWhileUndetermined() async {
    let location = ReviewLocation(state: .notDetermined)
    location.requestResult = .authorized
    let model = makeModel(
      microphone: ReviewMicrophone(state: .authorized), location: location)

    await model.requestLocation()
    await model.requestLocation()

    #expect(location.requestCount == 1)
    #expect(model.locationState == .authorized)
  }

  @Test func sceneAndIdentityChangesInvalidatePreparedAccess() async {
    let destination = ReviewDestinationService()
    destination.prepareOutcome = .prepared(
      PreparedDestination(id: UUID(), displayName: "Diary", needsDisclosure: true))
    let model = makeModel(
      microphone: ReviewMicrophone(state: .authorized),
      destinationService: destination)

    model.selectFolder()
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"))
    model.becameInactive()

    #expect(destination.invalidateCount == 2)
    #expect(model.preparedDestination == nil)
    #expect(!model.isFolderPickerPresented)

    await model.identityChanged()
    #expect(destination.invalidateCount == 3)
    #expect(destination.activeRequestCount == 1)
  }

  @Test func folderSelectionFailuresUseSanitizedMessages() {
    let destination = ReviewDestinationService()
    let model = makeModel(
      microphone: ReviewMicrophone(state: .authorized),
      destinationService: destination)

    destination.prepareOutcome = .rejected
    model.pickedFolder(URL(fileURLWithPath: "/private/folder-name"))
    #expect(model.message == "Choose a folder in iCloud Drive.")
    #expect(model.message?.contains("private") == false)

    destination.prepareOutcome = .temporarilyUnavailable
    model.pickedFolder(URL(fileURLWithPath: "/another/private-name"))
    #expect(model.message == "The folder is temporarily unavailable. Try again later.")
    #expect(model.message?.contains("another") == false)
  }

  @Test func generatedProjectDefinesClearPermissionPurposeStrings() throws {
    let project = try String(
      contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)

    #expect(project.contains("INFOPLIST_KEY_NSMicrophoneUsageDescription"))
    #expect(project.contains("Record audio for your diary."))
    #expect(project.contains("INFOPLIST_KEY_NSLocationWhenInUseUsageDescription"))
    #expect(project.contains("Add optional recording-time place and weather context"))
  }

  @Test func rootSourceContainsApprovedContainmentAndPrivacyAccessibility() throws {
    let source = try String(
      contentsOf: repositoryRoot.appendingPathComponent("NarihitosDiary/ContentView.swift"),
      encoding: .utf8)

    for label in ["Main", "Benefits", "Calendar", "Plugins", "All"] {
      #expect(source.contains("Label(\"\(label)\""))
    }
    // swiftlint:disable trailing_comma
    for message in [
      "Benefits are coming later.", "Calendar is coming later.",
      "Plugins are coming later.",
    ] {
      #expect(source.contains(message))
    }
    // swiftlint:enable trailing_comma
    #expect(source.contains(".accessibilityHidden(scenePhase != .active)"))
    #expect(source.contains("NavigationLink(\"Settings\")"))
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  }

  private func makeModel(
    microphone: ReviewMicrophone,
    location: ReviewLocation = ReviewLocation(state: .denied),
    systemSettings: ReviewSystemSettings = ReviewSystemSettings(),
    destinationService: ReviewDestinationService = ReviewDestinationService()
  ) -> AppModel {
    AppModel(
      microphone: microphone,
      location: location,
      systemSettings: systemSettings,
      destinationService: destinationService,
      firstLaunchStore: ReviewFirstLaunchStore())
  }
}

@MainActor
private final class ReviewMicrophone: MicrophoneAuthorizationPort {
  var state: PermissionState
  var requestResult: PermissionState?
  var requestCount = 0

  init(state: PermissionState) {
    self.state = state
  }

  func currentState() -> PermissionState { state }
  func requestAccess() async -> PermissionState {
    requestCount += 1
    state = requestResult ?? state
    return state
  }
}

@MainActor
private final class ReviewLocation: LocationAuthorizationPort {
  var state: PermissionState
  var requestResult: PermissionState?
  var requestCount = 0

  init(state: PermissionState) {
    self.state = state
  }

  func currentState() -> PermissionState { state }
  func requestWhenInUse() async -> PermissionState {
    requestCount += 1
    state = requestResult ?? state
    return state
  }
}

@MainActor
private final class ReviewSystemSettings: SystemSettingsPort {
  var openCount = 0

  func openApplicationSettings() {
    openCount += 1
  }
}

@MainActor
private final class ReviewDestinationService: DestinationSelectionPort {
  var active: ActiveDestination
  var activeRequestCount = 0
  var invalidateCount = 0
  var prepareOutcome: DestinationSelectionOutcome = .rejected
  var commitOutcome: DestinationCommitOutcome = .failed
  var cancelledIDs: [UUID] = []
  var committedIDs: [UUID] = []

  init(
    active: ActiveDestination = ActiveDestination(
      summary: nil, accessState: .restoreAccessRequired)
  ) {
    self.active = active
  }

  func activeDestination() async -> ActiveDestination {
    activeRequestCount += 1
    return active
  }

  func invalidateAccess() { invalidateCount += 1 }
  func prepareSelection(of url: URL) -> DestinationSelectionOutcome { prepareOutcome }
  func cancelPreparedSelection(_ id: UUID) { cancelledIDs.append(id) }
  func commitPreparedSelection(_ id: UUID) -> DestinationCommitOutcome {
    committedIDs.append(id)
    return commitOutcome
  }
}

@MainActor
private final class ReviewFirstLaunchStore: FirstLaunchStorePort {
  private var progress = FirstLaunchProgress()

  func loadFirstLaunchProgress() -> FirstLaunchProgress { progress }

  func saveFirstLaunchProgress(_ progress: FirstLaunchProgress) throws {
    self.progress = progress
  }
}
