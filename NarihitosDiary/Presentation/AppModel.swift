import Foundation
import OSLog
import SwiftUI

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

  private let microphone: any MicrophoneAuthorizationPort
  private let location: any LocationAuthorizationPort
  private let systemSettings: any SystemSettingsPort
  private let destinationService: any DestinationSelectionPort
  private let firstLaunch: FirstLaunchCoordinator
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
    self.init(
      microphone: AppleMicrophoneAuthorization(),
      location: AppleLocationAuthorization(),
      systemSettings: AppleSystemSettings(),
      destinationService: AppleDestinationService(repository: repository),
      firstLaunchStore: repository)
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

  func handleRecord() async {
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
      await routeRecordAfterAuthorization()
    case .authorized:
      await routeRecordAfterAuthorization()
    }
  }

  private func routeRecordAfterAuthorization() async {
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
    if destination.summary == nil || destination.accessState != .accessible {
      selectFolder()
    } else {
      presentMessage("Recording is not available yet.")
    }
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

  private func presentMessage(_ message: String, offersSettingsRecovery: Bool = false) {
    self.message = message
    self.offersSettingsRecovery = offersSettingsRecovery
  }
}
