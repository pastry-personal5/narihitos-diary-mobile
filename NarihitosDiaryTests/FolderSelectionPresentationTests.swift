import Foundation
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import NarihitosDiary

@MainActor
@Suite(.serialized)
struct FolderSelectionPresentationTests {
  @Test func systemDismissalBeforePickerResultStillRequestsDisclosure() {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let requestID = model.folderPickerRequestID
    let coordinator = FolderPicker(
      onPick: { model.pickedFolder($0, requestID: requestID) },
      onCancel: { model.cancelFolderPicker(requestID: requestID) }
    ).makeCoordinator()

    // On the phone, the system clears the sheet binding and calls onDismiss
    // before UIDocumentPickerDelegate delivers the selected URL.
    model.isFolderPickerPresented = false
    model.folderPickerDismissed()
    coordinator.documentPicker(
      UIDocumentPickerViewController(forOpeningContentTypes: [.folder]),
      didPickDocumentsAt: [URL(fileURLWithPath: "/unused-test-folder")])

    #expect(model.disclosurePresented.wrappedValue)
    #expect(model.preparedDestination != nil)
    #expect(model.destination.summary == nil)
    #expect(destination.commitCount == 0)
  }

  @Test func previouslyDisclosedResultAfterSystemDismissalCommitsOnce() {
    let destination = FolderSelectionTestDestination(needsDisclosure: false)
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let requestID = model.folderPickerRequestID

    model.isFolderPickerPresented = false
    model.folderPickerDismissed()
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)
    model.folderPickerDismissed()
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)

    #expect(destination.commitCount == 1)
    #expect(model.destination.summary == destination.summary)
    #expect(!model.disclosurePresented.wrappedValue)
  }

  @Test func firstSelectionAfterEarlyDismissalRequiresAcceptanceAndSurvivesRefresh() async {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let requestID = model.folderPickerRequestID
    model.isFolderPickerPresented = false
    model.folderPickerDismissed()
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)

    #expect(destination.commitCount == 0)
    #expect(model.destination.summary == nil)
    // SwiftUI clears the alert binding before invoking its explicit action.
    model.disclosurePresented.wrappedValue = false
    #expect(model.preparedDestination != nil)
    model.acceptDisclosure()
    model.acceptDisclosure()
    await model.becameActive()

    #expect(destination.commitCount == 1)
    #expect(model.destination.summary == destination.summary)
  }

  @Test func cancellationOrCommitFailureAfterEarlyDismissalPreservesPreviousFolder() async {
    for cancel in [true, false] {
      let destination = FolderSelectionTestDestination()
      let previous = DestinationSummary(id: .make(), displayName: "Previous Synthetic Diary")
      destination.activeSummary = previous
      destination.commitFails = true
      let model = makeFolderSelectionModel(destination)
      await model.becameActive()
      model.selectFolder()
      let requestID = model.folderPickerRequestID
      model.isFolderPickerPresented = false
      model.folderPickerDismissed()
      model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)
      if cancel {
        model.cancelDisclosure()
      } else {
        model.acceptDisclosure()
        #expect(model.message == "The folder could not be saved. Your previous selection was kept.")
      }
      await model.becameActive()

      #expect(model.destination.summary == previous)
      #expect(destination.activeSummary == previous)
      #expect(model.preparedDestination == nil)
    }
  }

  @Test func validationFailureAfterEarlyDismissalIsPresentedWithoutCommitting() {
    for outcome in [DestinationSelectionOutcome.rejected, .temporarilyUnavailable] {
      let destination = FolderSelectionTestDestination()
      destination.selectionOutcome = outcome
      let model = makeFolderSelectionModel(destination)
      model.selectFolder()
      let requestID = model.folderPickerRequestID
      model.isFolderPickerPresented = false
      model.folderPickerDismissed()
      model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)

      #expect(
        model.message
          == (outcome == .rejected
            ? "Choose a folder in iCloud Drive."
            : "The folder is temporarily unavailable. Try again later."))
      #expect(model.preparedDestination == nil)
      #expect(model.destination.summary == nil)
      #expect(destination.commitCount == 0)
    }
  }

  @Test func identityChangeAfterEarlyDismissalRejectsLateResult() async {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let requestID = model.folderPickerRequestID
    model.isFolderPickerPresented = false
    model.folderPickerDismissed()
    await model.identityChanged()

    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)
    model.folderPickerDismissed()

    #expect(model.preparedDestination == nil)
    #expect(destination.commitCount == 0)
  }

  @Test func cancellationOrDepartureAfterSystemDismissalRejectsLateResult() {
    for cancel in [true, false] {
      let destination = FolderSelectionTestDestination()
      let model = makeFolderSelectionModel(destination)
      model.selectFolder()
      let requestID = model.folderPickerRequestID
      model.isFolderPickerPresented = false
      model.folderPickerDismissed()
      if cancel {
        model.cancelFolderPicker(requestID: requestID)
      } else {
        model.becameInactive()
      }

      model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: requestID)
      model.folderPickerDismissed()

      #expect(model.preparedDestination == nil)
      #expect(!model.disclosurePresented.wrappedValue)
      #expect(destination.commitCount == 0)
    }
  }

  @Test func earlyDismissalDoesNotAuthorizeAResultFromAnOlderSelection() {
    let destination = FolderSelectionTestDestination(needsDisclosure: false)
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let oldRequest = model.folderPickerRequestID
    model.isFolderPickerPresented = false
    model.folderPickerDismissed()
    model.selectFolder()
    let currentRequest = model.folderPickerRequestID

    model.pickedFolder(URL(fileURLWithPath: "/unused-old-folder"), requestID: oldRequest)
    #expect(model.isFolderPickerPresented)
    #expect(destination.commitCount == 0)
    model.isFolderPickerPresented = false
    model.folderPickerDismissed()
    model.pickedFolder(URL(fileURLWithPath: "/unused-current-folder"), requestID: currentRequest)

    #expect(destination.commitCount == 1)
    #expect(model.destination.summary == destination.summary)
  }

  @Test func firstSelectionWaitsForPickerDismissalBeforeRequestingDisclosure() {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)

    model.selectFolder()
    model.pickedFolder(
      URL(fileURLWithPath: "/unused-test-folder"), requestID: model.folderPickerRequestID)

    #expect(!model.isFolderPickerPresented)
    #expect(!model.disclosurePresented.wrappedValue)
    #expect(model.preparedDestination == nil)
    #expect(model.destination.summary == nil)
    #expect(destination.commitCount == 0)

    model.folderPickerDismissed()

    #expect(model.disclosurePresented.wrappedValue)
    #expect(model.preparedDestination != nil)
    #expect(destination.commitCount == 0)
  }

  @Test func latePickerCallbacksCannotReplaceANewerSelectionOrSurviveDeparture() {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let oldRequest = model.folderPickerRequestID
    model.selectFolder()

    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: oldRequest)
    #expect(model.isFolderPickerPresented)
    #expect(model.preparedDestination == nil)

    let currentRequest = model.folderPickerRequestID
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: currentRequest)
    model.becameInactive()
    model.folderPickerDismissed()
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: currentRequest)
    model.folderPickerDismissed()

    #expect(!model.disclosurePresented.wrappedValue)
    #expect(model.preparedDestination == nil)
    #expect(destination.commitCount == 0)
  }

  @Test func previouslyDisclosedSelectionCommitsExactlyOnceAfterDismissal() {
    let destination = FolderSelectionTestDestination(needsDisclosure: false)
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let request = model.folderPickerRequestID
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: request)
    #expect(destination.commitCount == 0)

    model.folderPickerDismissed()
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: request)
    model.folderPickerDismissed()

    #expect(destination.commitCount == 1)
    #expect(model.destination.summary == destination.summary)
    #expect(!model.disclosurePresented.wrappedValue)
  }

  @Test func cancelledPickerNeverPresentsADisclosureOrCommits() {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectFolder()
    let request = model.folderPickerRequestID

    model.cancelFolderPicker(requestID: request)
    model.pickedFolder(URL(fileURLWithPath: "/unused-test-folder"), requestID: request)
    model.folderPickerDismissed()

    #expect(!model.disclosurePresented.wrappedValue)
    #expect(destination.commitCount == 0)
  }

}

@MainActor
@Suite(.serialized)
struct FolderSelectionSettingsHierarchyTests {
  @Test func settingsHierarchyShowsDisclosureForResultAfterSheetDismissal() async throws {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectedRoot = .all
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    let previousWindow = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(rootView: ContentView(model: model))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      host.dismiss(animated: false)
      window.isHidden = true
      window.rootViewController = nil
      previousWindow?.makeKey()
    }
    await waitForPresentation { model.firstLaunchStep == nil && host.view.window != nil }
    model.showSettings = true
    await waitForPresentation { self.showsSettings(in: host) }
    try #require(showsSettings(in: host))
    model.selectFolder()
    await waitForPresentation {
      self.findController(UIDocumentPickerViewController.self, in: host) != nil
    }
    let picker = try #require(findController(UIDocumentPickerViewController.self, in: host))
    let delegate = try #require(picker.delegate)

    model.isFolderPickerPresented = false
    await waitForPresentation { picker.viewIfLoaded?.window == nil }
    delegate.documentPicker?(
      picker, didPickDocumentsAt: [URL(fileURLWithPath: "/unused-test-folder")])
    await waitForPresentation { self.findController(UIAlertController.self, in: host) != nil }
    let disclosure = try #require(findController(UIAlertController.self, in: host))

    #expect(disclosure.title == "Readable Files")
    #expect(disclosure.actions.map(\.title).contains("Use Folder"))
    #expect(destination.commitCount == 0)
    model.cancelDisclosure()
    host.dismiss(animated: false)
  }

  private func findController<Controller: UIViewController>(
    _ type: Controller.Type, in controller: UIViewController
  ) -> Controller? {
    if let match = controller as? Controller { return match }
    if let presented = controller.presentedViewController {
      if let match = findController(type, in: presented) { return match }
    }
    for child in controller.children {
      if let match = findController(type, in: child) { return match }
    }
    return nil
  }

  private func showsSettings(in controller: UIViewController) -> Bool {
    if let navigation = controller as? UINavigationController {
      if navigation.topViewController?.navigationItem.title == "Settings" { return true }
    }
    return controller.children.contains { showsSettings(in: $0) }
  }

  private func waitForPresentation(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(25))
    }
  }
}

@MainActor
private func makeFolderSelectionModel(_ destination: FolderSelectionTestDestination) -> AppModel {
  let permissions = FolderTestPermissions()
  return AppModel(
    microphone: permissions, location: permissions, systemSettings: permissions,
    destinationService: destination, firstLaunchStore: permissions)
}

@MainActor
private final class FolderTestPermissions: MicrophoneAuthorizationPort, LocationAuthorizationPort {
  var progress = FirstLaunchProgress(step: .complete)
  func currentState() -> PermissionState { .authorized }
  func requestAccess() async -> PermissionState { .authorized }
  func requestWhenInUse() async -> PermissionState { .authorized }
  func openApplicationSettings() {}
  func loadFirstLaunchProgress() -> FirstLaunchProgress { progress }
  func saveFirstLaunchProgress(_ progress: FirstLaunchProgress) throws { self.progress = progress }
}

extension FolderTestPermissions: SystemSettingsPort, FirstLaunchStorePort {}

@MainActor
private final class FolderSelectionTestDestination: DestinationSelectionPort {
  let summary = DestinationSummary(id: .make(), displayName: "Synthetic Diary")
  let needsDisclosure: Bool
  var commitCount = 0
  var commitFails = false
  var activeSummary: DestinationSummary?
  var selectionOutcome: DestinationSelectionOutcome?

  init(needsDisclosure: Bool = true) { self.needsDisclosure = needsDisclosure }
  func invalidateAccess() {}
  func activeDestination() async -> ActiveDestination {
    ActiveDestination(
      summary: activeSummary,
      accessState: activeSummary == nil ? .restoreAccessRequired : .accessible)
  }
  func prepareSelection(of url: URL) -> DestinationSelectionOutcome {
    selectionOutcome
      ?? .prepared(
        PreparedDestination(
          id: UUID(), displayName: summary.displayName, needsDisclosure: needsDisclosure))
  }
  func cancelPreparedSelection(_ id: UUID) {}
  func commitPreparedSelection(_ id: UUID) -> DestinationCommitOutcome {
    commitCount += 1
    if commitFails { return .failed }
    activeSummary = summary
    return .committed(summary)
  }
}
