import AVFAudio
import Foundation
import OSLog
import SwiftUI

// Capture presentation adds the M9 lifecycle to the M8 root model.
// swiftlint:disable type_body_length

enum RootTab: Hashable {
  case main
  case benefits
  case calendar
  case plugins
  case all
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var microphoneState: PermissionState
  @Published private(set) var locationState: PermissionState
  @Published private(set) var destination = ActiveDestination(
    summary: nil, accessState: .restoreAccessRequired)
  @Published private(set) var firstLaunchStep: FirstLaunchStep?
  @Published var isFolderPickerPresented = false
  @Published var preparedDestination: PreparedDestination?
  @Published var message: String?
  @Published private(set) var offersSettingsRecovery = false
  @Published private(set) var offersPendingReview = false
  @Published var isCapturePresented = false
  @Published private(set) var captureElapsed = 0
  @Published private(set) var captureLevel: Float = 0
  @Published private(set) var pendingCaptures: [CaptureIdentity] = []
  @Published private(set) var failedCaptures: [CaptureIdentity] = []
  @Published private(set) var captureIssues: [CaptureRecoveryIssue] = []
  @Published var selectedRoot: RootTab = .main
  @Published var showPendingRecordings = false

  private let microphone: any MicrophoneAuthorizationPort
  private let location: any LocationAuthorizationPort
  private let systemSettings: any SystemSettingsPort
  private let destinationService: any DestinationSelectionPort
  private let firstLaunch: FirstLaunchCoordinator
  private var captureEnvironment: AppleCaptureEnvironment?
  private var captureCoordinator: CaptureCoordinator?
  private var captureEntryInProgress = false
  private var captureTimer: Task<Void, Never>?
  private var interruptionObserver: NSObjectProtocol?
  private let folderSelectionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "NarihitosDiary",
    category: "FolderSelection")

  var disclosurePresented: Binding<Bool> {
    Binding(
      get: { self.preparedDestination?.needsDisclosure == true },
      set: { isPresented in
        self.folderSelectionLogger.debug(
          "Disclosure presentation changed; isPresented=\(isPresented, privacy: .public); prepared selection retained"
        )
        // Alert buttons own acceptance and cancellation. SwiftUI writes false before invoking
        // their actions, so treating this write as cancellation would discard the selection.
      })
  }

  convenience init() {
    let repository = PrivateSettingsRepository()
    let destination = AppleDestinationService(repository: repository)
    self.init(
      microphone: AppleMicrophoneAuthorization(),
      location: AppleLocationAuthorization(),
      systemSettings: AppleSystemSettings(),
      destinationService: destination,
      firstLaunchStore: repository)
    captureEnvironment = AppleCaptureEnvironment(microphone: microphone, destination: destination)
  }

  init(
    microphone: any MicrophoneAuthorizationPort,
    location: any LocationAuthorizationPort,
    systemSettings: any SystemSettingsPort,
    destinationService: any DestinationSelectionPort,
    firstLaunchStore: any FirstLaunchStorePort
  ) {
    self.microphone = microphone
    self.location = location
    self.systemSettings = systemSettings
    self.destinationService = destinationService
    firstLaunch = FirstLaunchCoordinator(
      microphone: microphone, location: location, store: firstLaunchStore)
    microphoneState = microphone.currentState()
    locationState = location.currentState()
    firstLaunchStep = firstLaunch.pendingExplanation
  }

  func becameActive() async {
    firstLaunch.refresh()
    microphoneState = microphone.currentState()
    locationState = location.currentState()
    destination = await destinationService.activeDestination()
    firstLaunchStep = firstLaunch.pendingExplanation
    _ = captureEnvironment?.recover()
    refreshCaptureLists()
  }

  func becameInactive() {
    destinationService.invalidateAccess()
    preparedDestination = nil
    isFolderPickerPresented = false
  }

  func identityChanged() async {
    destinationService.invalidateAccess()
    destination = await destinationService.activeDestination()
  }

  func continueFirstLaunch() async {
    await firstLaunch.continueCurrentStep()
    microphoneState = microphone.currentState()
    locationState = location.currentState()
    firstLaunchStep = firstLaunch.pendingExplanation
  }

  func requestLocation() async {
    guard location.currentState() == .notDetermined else { return }
    locationState = await location.requestWhenInUse()
  }

  func openSettings() {
    clearMessage()
    systemSettings.openApplicationSettings()
  }

  func clearMessage() {
    message = nil
    offersSettingsRecovery = false
    offersPendingReview = false
  }

  func reviewPendingRecordings() {
    clearMessage()
    selectedRoot = .all
    showPendingRecordings = true
  }

  func selectFolder() {
    clearMessage()
    destinationService.invalidateAccess()
    isFolderPickerPresented = true
  }

  func pickedFolder(_ url: URL) {
    isFolderPickerPresented = false
    switch destinationService.prepareSelection(of: url) {
    case .prepared(let candidate):
      folderSelectionLogger.debug(
        "Folder selection prepared; disclosureRequired=\(candidate.needsDisclosure, privacy: .public)"
      )
      preparedDestination = candidate
      if !candidate.needsDisclosure {
        commitPreparedDestination()
      }
    case .rejected:
      folderSelectionLogger.debug("Folder selection rejected")
      presentMessage("Choose a folder in iCloud Drive.")
    case .temporarilyUnavailable:
      folderSelectionLogger.debug("Folder selection temporarily unavailable")
      presentMessage("The folder is temporarily unavailable. Try again later.")
    }
  }

  func cancelFolderPicker() {
    isFolderPickerPresented = false
  }

  func cancelDisclosure() {
    guard let preparedDestination else { return }
    folderSelectionLogger.debug("Folder disclosure canceled; prepared selection discarded")
    destinationService.cancelPreparedSelection(preparedDestination.id)
    self.preparedDestination = nil
  }

  func acceptDisclosure() {
    folderSelectionLogger.debug("Folder disclosure accepted; committing prepared selection")
    commitPreparedDestination()
  }

  func handleRecord(language: CaptureLanguage) async {
    guard !captureEntryInProgress, !isCapturePresented else { return }
    captureEntryInProgress = true
    defer { captureEntryInProgress = false }
    microphoneState = microphone.currentState()
    switch microphoneState {
    case .denied, .restricted:
      presentMicrophoneRecovery()
    case .notDetermined:
      microphoneState = await microphone.requestAccess()
      if microphoneState != .authorized {
        if microphoneState == .denied || microphoneState == .restricted {
          presentMicrophoneRecovery()
        } else {
          presentMessage("Microphone access is required to record.")
        }
        return
      }
      await routeRecordAfterAuthorization(language: language)
    case .authorized:
      await routeRecordAfterAuthorization(language: language)
    }
  }

  private func routeRecordAfterAuthorization(language: CaptureLanguage) async {
    microphoneState = microphone.currentState()
    guard microphoneState == .authorized else {
      if microphoneState == .denied || microphoneState == .restricted {
        presentMicrophoneRecovery()
      } else {
        presentMessage("Microphone access is required to record.")
      }
      return
    }

    destination = await destinationService.activeDestination()
    microphoneState = microphone.currentState()
    guard microphoneState == .authorized else {
      if microphoneState == .denied || microphoneState == .restricted {
        presentMicrophoneRecovery()
      } else {
        presentMessage("Microphone access is required to record.")
      }
      return
    }
    var verifiedOffline = false
    if destination.accessState == .temporarilyUnavailable {
      if let service = destinationService as? AppleDestinationService {
        verifiedOffline = (try? await service.captureSnapshotRecord()) != nil
      }
    }
    if destination.summary == nil || (destination.accessState != .accessible && !verifiedOffline) {
      selectFolder()
    } else {
      await startCapture(language: language)
    }
  }

  private func startCapture(language: CaptureLanguage) async {
    guard let captureEnvironment else {
      presentMessage("Recording is temporarily unavailable.")
      return
    }
    let coordinator = CaptureCoordinator(environment: captureEnvironment)
    captureCoordinator = coordinator
    coordinator.onSettlement = { [weak self] phase in
      self?.finishCapture(phase)
    }
    do {
      try await coordinator.start(language: language)
      guard case .capturing = coordinator.phase else { return }
      captureElapsed = 0
      captureLevel = 0
      isCapturePresented = true
      interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: raw) == .began
        else { return }
        Task { @MainActor in self?.stopCapture(reason: .interruption) }
      }
      captureTimer?.cancel()
      captureTimer = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(250))
          guard let self, self.isCapturePresented else { return }
          self.captureElapsed = coordinator.elapsedSeconds
          self.captureLevel = captureEnvironment.currentLevel()
        }
      }
    } catch CaptureGateFailure.insufficientSpace {
      presentMessage("Not enough storage to start recording.", offersPendingReview: true)
    } catch {
      presentMessage("Recording could not start. Try again later.")
    }
  }

  func stopCapture(reason: CaptureEndReason = .user) {
    guard let captureCoordinator else { return }
    captureCoordinator.end(reason)
  }

  private func finishCapture(_ phase: CapturePhase) {
    captureTimer?.cancel()
    captureTimer = nil
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
      self.interruptionObserver = nil
    }
    isCapturePresented = false
    refreshCaptureLists()
    switch phase {
    case .pending:
      presentMessage("Recording saved in Pending Recordings. Processing will be available later.")
    case .failed:
      presentMessage("This recording can’t be read.")
    case .paused:
      presentMessage("Recording saved locally. Recovery will resume when storage is available.")
    default:
      break
    }
  }

  func refreshCaptureLists() {
    pendingCaptures = captureEnvironment?.pending() ?? []
    failedCaptures = captureEnvironment?.failed() ?? []
    captureIssues = captureEnvironment?.issues() ?? []
  }

  private func presentMicrophoneRecovery() {
    presentMessage(
      "Microphone access is required to record. Open Settings to allow access.",
      offersSettingsRecovery: true)
  }

  private func commitPreparedDestination() {
    guard let candidate = preparedDestination else { return }
    switch destinationService.commitPreparedSelection(candidate.id) {
    case .committed(let summary):
      folderSelectionLogger.debug("Folder selection committed")
      destination = ActiveDestination(summary: summary, accessState: .accessible)
    case .superseded:
      folderSelectionLogger.debug("Folder selection commit superseded")
      presentMessage("The selection changed before it could be saved.")
    case .failed:
      folderSelectionLogger.debug("Folder selection commit failed")
      presentMessage("The folder could not be saved. Your previous selection was kept.")
    }
    preparedDestination = nil
  }

  private func presentMessage(
    _ message: String, offersSettingsRecovery: Bool = false,
    offersPendingReview: Bool = false
  ) {
    self.message = message
    self.offersSettingsRecovery = offersSettingsRecovery
    self.offersPendingReview = offersPendingReview
  }
}

// swiftlint:enable type_body_length
