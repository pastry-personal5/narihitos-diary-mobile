import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

private struct HostedSettingsScene {
  let host: UIHostingController<SettingsHierarchyRoot>
  let window: UIWindow
  let previousWindow: UIWindow?
}

private struct SettingsHierarchyRoot: View {
  let model: AppModel
  var dark = false
  var accessibilitySize = false

  var body: some View {
    ContentView(model: model)
      .environment(\.scenePhase, .active)
      .preferredColorScheme(dark ? .dark : .light)
      .dynamicTypeSize(accessibilitySize ? .accessibility5 : .large)
  }
}

@MainActor
@Suite(.serialized)
struct FolderSelectionSettingsHierarchyTests {
  @Test func settingsEntryKeepsCommittedFolderWithoutPresentingPicker() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let destination = FolderSelectionTestDestination()
    destination.activeSummary = destination.summary
    let model = makeFolderSelectionModel(destination)
    model.selectedRoot = .all
    await model.becameActive()
    let hosted = try await makeHost(model)
    let host = hosted.host
    defer { tearDown(hosted) }
    await waitForPresentation { model.firstLaunchStep == nil && host.view.window != nil }

    await waitForPresentation { !self.settingsButtons(in: host.view).isEmpty }
    let settings = try #require(settingsButtons(in: host.view).first)
    #expect(settings.accessibilityActivate())
    await waitForPresentation { self.showsSettings(in: host) }
    try #require(showsSettings(in: host))
    await model.becameActive()
    try? await Task.sleep(for: .milliseconds(100))

    #expect(model.destination.summary == destination.summary)
    #expect(!model.isFolderPickerPresented)
    #expect(model.folderPickerRequestID == nil)
    #expect(findController(UIDocumentPickerViewController.self, in: host) == nil)
    await waitForPresentation { self.settingsButtons(in: host.view).isEmpty }
    #expect(settingsButtons(in: host.view).isEmpty)

    model.showSettings = false
    await waitForPresentation { !self.settingsButtons(in: host.view).isEmpty }
    let restored = try #require(settingsButtons(in: host.view).first)
    #expect(restored.accessibilityActivate())
    await waitForPresentation { self.showsSettings(in: host) }
    #expect(showsSettings(in: host))
    #expect(!model.isFolderPickerPresented)
    #expect(model.folderPickerRequestID == nil)

    model.selectFolderFromSettings()
    await waitForPresentation {
      self.findController(UIDocumentPickerViewController.self, in: host) != nil
    }
    #expect(findController(UIDocumentPickerViewController.self, in: host) != nil)
    model.cancelFolderPicker(requestID: model.folderPickerRequestID)
  }

  @Test(arguments: [false, true], [false, true])
  func allSettingsToolbarHasOneAccessibleTarget(dark: Bool, accessibilitySize: Bool) async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let destination = FolderSelectionTestDestination()
    destination.activeSummary = destination.summary
    let model = makeFolderSelectionModel(destination)
    model.selectedRoot = .all
    let hosted = try await makeHost(model, dark: dark, accessibilitySize: accessibilitySize)
    defer { tearDown(hosted) }
    await waitForPresentation { !self.settingsButtons(in: hosted.host.view).isEmpty }
    let navigation = try #require(findController(UINavigationController.self, in: hosted.host))
    let buttons = settingsButtons(in: hosted.host.view)
    let button = try #require(buttons.first)
    let barButtons = settingsButtons(in: navigation.navigationBar)
    let barFrame = navigation.navigationBar.convert(navigation.navigationBar.bounds, to: nil)

    #expect(buttons.count == 1)
    #expect(barButtons.count == 1)
    #expect(button.value(forKey: "accessibilityIdentifier") as? String == "all-settings-button")
    #expect(button.accessibilityTraits.contains(.button))
    #expect(button.accessibilityFrame.width >= 44)
    #expect(button.accessibilityFrame.height >= 44)
    #expect(barFrame.contains(button.accessibilityFrame))
    #expect(button.accessibilityFrame.midX > barFrame.midX)
    try await checkRecoveryRows(in: hosted, navigation: navigation)
    try savePreview(hosted, dark: dark, accessibilitySize: accessibilitySize)

    let pending = try #require(
      accessibleElements(in: hosted.host.view).first {
        $0.accessibilityLabel == "Pending Recordings"
      })
    #expect(pending.accessibilityActivate())
    await waitForPresentation {
      navigation.topViewController?.navigationItem.title == "Pending Recordings"
    }
    #expect(navigation.topViewController?.navigationItem.title == "Pending Recordings")
    await waitForPresentation { self.settingsButtons(in: hosted.host.view).isEmpty }
    #expect(settingsButtons(in: hosted.host.view).isEmpty)
    #expect(!model.showSettings)
  }

  private func checkRecoveryRows(
    in hosted: HostedSettingsScene, navigation: UINavigationController
  ) async throws {
    // swiftlint:disable trailing_comma
    for title in [
      "Pending Recordings", "Failed Recordings", "Incomplete Diary Snippets",
      "Conflicting Versions",
    ] {
      if !accessibleElements(in: hosted.host.view).contains(where: {
        $0.accessibilityLabel == title
      }) {
        let scroll = try #require(
          findView(UIScrollView.self, in: navigation.topViewController?.view))
        scroll.setContentOffset(
          CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)),
          animated: false)
        await waitForPresentation {
          self.accessibleElements(in: hosted.host.view).contains { $0.accessibilityLabel == title }
        }
      }
      #expect(accessibleElements(in: hosted.host.view).contains { $0.accessibilityLabel == title })
    }
    // swiftlint:enable trailing_comma
    if let scroll = findView(UIScrollView.self, in: navigation.topViewController?.view) {
      scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
    }
    await waitForPresentation {
      self.accessibleElements(in: hosted.host.view).contains {
        $0.accessibilityLabel == "Pending Recordings"
      }
    }

  }

  private func savePreview(
    _ hosted: HostedSettingsScene, dark: Bool, accessibilitySize: Bool
  ) throws {
    let image = UIGraphicsImageRenderer(bounds: hosted.host.view.bounds).image { _ in
      hosted.host.view.drawHierarchy(in: hosted.host.view.bounds, afterScreenUpdates: true)
    }
    let name =
      "all-settings-\(dark ? "dark" : "light")-\(accessibilitySize ? "ax5" : "default").png"
    let url = FileManager.default.temporaryDirectory.appending(path: name)
    try image.pngData()?.write(to: url)
    print("All Settings layout preview: \(url.path)")

  }

  @Test func settingsHierarchyShowsDisclosureForResultAfterSheetDismissal() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let destination = FolderSelectionTestDestination()
    let model = makeFolderSelectionModel(destination)
    model.selectedRoot = .all
    let hosted = try await makeHost(model)
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
    _ model: AppModel, dark: Bool = false, accessibilitySize: Bool = false
  ) async throws -> HostedSettingsScene {
    await waitForPresentation {
      UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
    }
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    let previousWindow = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: dark ? 440 : 375, height: dark ? 956 : 667)
    let host = UIHostingController(
      rootView: SettingsHierarchyRoot(
        model: model, dark: dark, accessibilitySize: accessibilitySize))
    window.rootViewController = host
    window.makeKeyAndVisible()
    return HostedSettingsScene(host: host, window: window, previousWindow: previousWindow)
  }

  private func settingsButtons(in view: UIView) -> [NSObject] {
    accessibleElements(in: view).filter {
      $0.accessibilityLabel == "Settings" && $0.accessibilityTraits.contains(.button)
    }
  }

  private func findView<Match: UIView>(_ type: Match.Type, in view: UIView?) -> Match? {
    guard let view else { return nil }
    if let match = view as? Match { return match }
    return view.subviews.lazy.compactMap { findView(type, in: $0) }.first
  }

  private func accessibleElements(in root: NSObject) -> [NSObject] {
    var visited = Set<ObjectIdentifier>()
    func collect(_ object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
      var children: [NSObject] = (object as? UIView)?.subviews ?? []
      children += (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
      let count = object.accessibilityElementCount()
      if count > 0, count < 256 {
        children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
      }
      return (object.isAccessibilityElement ? [object] : []) + children.flatMap(collect)
    }
    return collect(root)
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
