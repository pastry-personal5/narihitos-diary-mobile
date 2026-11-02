import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

private struct HostedSettingsScene {
  let host: UIHostingController<ContentView>
  let window: UIWindow
  let previousWindow: UIWindow?
}

@MainActor
@Suite(.serialized)
struct FolderSelectionSettingsHierarchyTests {
  @Test func settingsEntryKeepsCommittedFolderWithoutPresentingPicker() async throws {
    let destination = FolderSelectionTestDestination()
    destination.activeSummary = destination.summary
    let model = makeFolderSelectionModel(destination)
    model.selectedRoot = .all
    await model.becameActive()
    let hosted = try makeHost(model)
    let host = hosted.host
    defer { tearDown(hosted) }
    await waitForPresentation { model.firstLaunchStep == nil && host.view.window != nil }

    model.openAppSettings()
    await waitForPresentation { self.showsSettings(in: host) }
    try #require(showsSettings(in: host))
    await model.becameActive()
    try? await Task.sleep(for: .milliseconds(100))

    #expect(model.destination.summary == destination.summary)
    #expect(!model.isFolderPickerPresented)
    #expect(model.folderPickerRequestID == nil)
    #expect(findController(UIDocumentPickerViewController.self, in: host) == nil)

    model.selectFolderFromSettings()
    await waitForPresentation {
      self.findController(UIDocumentPickerViewController.self, in: host) != nil
    }
    #expect(findController(UIDocumentPickerViewController.self, in: host) != nil)
    model.cancelFolderPicker(requestID: model.folderPickerRequestID)
  }

  @Test func settingsHierarchyShowsDisclosureForResultAfterSheetDismissal() async throws {
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectedRoot = .all
    let hosted = try makeHost(model)
    let host = hosted.host
    defer { tearDown(hosted) }
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
  }

  private func makeHost(
    _ model: AppModel
  ) throws -> HostedSettingsScene {
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    let previousWindow = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(rootView: ContentView(model: model))
    window.rootViewController = host
    window.makeKeyAndVisible()
    return HostedSettingsScene(host: host, window: window, previousWindow: previousWindow)
  }

  private func tearDown(_ hosted: HostedSettingsScene) {
    hosted.host.dismiss(animated: false)
    hosted.window.isHidden = true
    hosted.window.rootViewController = nil
    hosted.previousWindow?.makeKey()
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
