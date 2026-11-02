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
func makeFolderSelectionModel(_ destination: FolderSelectionTestDestination) -> AppModel {
  let permissions = FolderTestPermissions()
  return AppModel(
    microphone: permissions, location: permissions, systemSettings: permissions,
    destinationService: destination, firstLaunchStore: permissions)
}

@MainActor
final class FolderTestPermissions: MicrophoneAuthorizationPort, LocationAuthorizationPort {
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
final class FolderSelectionTestDestination: DestinationSelectionPort {
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
