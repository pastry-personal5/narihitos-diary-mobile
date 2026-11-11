import Combine
import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

@MainActor
@Suite(.serialized)
struct DangerZonePresentationTests {
  @Test func separateInlineConfirmationsCancelAndSceneDepartureAreSafe() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let fixture = try DangerZoneFixture()
    defer { fixture.close() }
    #expect(fixture.port.performed.isEmpty)
    try await fixture.activate("purge-request-activeFolder")
    await fixture.wait { fixture.element("purge-confirm-activeFolder") != nil }
    #expect(fixture.model.confirmation?.transaction.scope == .activeFolder)
    try fixture.savePreview("folder-light")
    #expect(fixture.host.presentedViewController == nil)
    #expect(fixture.element("purge-confirm-internalStaging") == nil)
    try await fixture.activate("purge-cancel-activeFolder")
    #expect(fixture.port.performed.isEmpty)
    try await fixture.activate("purge-request-internalStaging")
    await fixture.wait { fixture.element("purge-confirm-internalStaging") != nil }
    #expect(fixture.model.confirmation?.transaction.scope == .internalStaging)
    fixture.state.phase = .inactive
    await fixture.wait { fixture.model.confirmation == nil }
    #expect(fixture.port.performed.isEmpty)
    fixture.state.phase = .active
    try await fixture.activate("purge-request-internalStaging")
    try await fixture.activate("purge-confirm-internalStaging")
    await fixture.wait { fixture.port.performed == [.internalStaging] }
    #expect(fixture.port.performed == [.internalStaging])
  }

  @Test func navigationDepartureDisarmsAndLargeTextCanScroll() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let fixture = try DangerZoneFixture()
    defer { fixture.close() }
    fixture.state.large = true
    fixture.state.dark = true
    try await fixture.activate("purge-request-internalStaging")
    #expect(fixture.model.confirmation != nil)
    await fixture.scrollToBottom()
    let confirmation = try #require(fixture.element("purge-confirm-internalStaging"))
    #expect(
      fixture.window.convert(fixture.window.bounds, to: nil).intersects(
        confirmation.accessibilityFrame))
    try fixture.savePreview("staging-dark-large")
    fixture.state.visible = false
    await fixture.wait { fixture.model.confirmation == nil }
    #expect(fixture.port.performed.isEmpty)
  }
}

@MainActor
private final class DangerZoneViewState: ObservableObject {
  @Published var phase: ScenePhase = .active
  @Published var large = false
  @Published var dark = false
  @Published var visible = true
}

private struct DangerZoneTestRoot: View {
  let model: DangerZoneModel
  @ObservedObject var state: DangerZoneViewState
  var body: some View {
    NavigationStack {
      if state.visible { DangerZoneView(model: model, folderName: "Synthetic Folder") }
    }
    .environment(\.scenePhase, state.phase)
    .dynamicTypeSize(state.large ? .accessibility5 : .large)
    .preferredColorScheme(state.dark ? .dark : .light)
    .transaction { $0.disablesAnimations = true }
  }
}

@MainActor
private final class DangerZoneFixture {
  let model = DangerZoneModel()
  let port = SyntheticPurgePort()
  let state = DangerZoneViewState()
  let host: UIHostingController<DangerZoneTestRoot>
  let window: UIWindow
  let previous: UIWindow?

  init() throws {
    model.configure(port)
    model.acquireMaintenance = { true }
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    previous = scene.keyWindow
    window = UIWindow(windowScene: scene)
    host = UIHostingController(rootView: DangerZoneTestRoot(model: model, state: state))
    window.rootViewController = host
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
  }

  func activate(_ id: String) async throws {
    await wait { self.element(id) != nil }
    if element(id) == nil, let scroll = scroll(in: host.view) {
      scroll.setContentOffset(
        CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
      await wait { self.element(id) != nil }
    }
    let control = try #require(element(id), "Missing Danger Zone control: \(id)")
    #expect(control.accessibilityTraits.contains(.button))
    #expect(control.accessibilityFrame.height >= 44)
    #expect(control.accessibilityActivate())
    await Task.yield()
  }

  func element(_ id: String) -> NSObject? {
    var visited = Set<ObjectIdentifier>()
    return find(id, object: host.view, visited: &visited)
  }

  private func find(
    _ id: String, object: NSObject, visited: inout Set<ObjectIdentifier>
  ) -> NSObject? {
    guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
    let key = "accessibilityIdentifier"
    if object.responds(to: NSSelectorFromString(key)) {
      if object.value(forKey: key) as? String == id { return object }
    }
    var children: [NSObject] = (object as? UIView)?.subviews ?? []
    children += (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
    let count = object.accessibilityElementCount()
    if count > 0, count < 256 {
      children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
    }
    for child in children {
      if let value = find(id, object: child, visited: &visited) { return value }
    }
    return nil
  }

  private func scroll(in view: UIView) -> UIScrollView? {
    if let value = view as? UIScrollView { return value }
    return view.subviews.compactMap { scroll(in: $0) }.first
  }

  func wait(_ predicate: () -> Bool) async {
    for _ in 0..<80 {
      window.layoutIfNeeded()
      if predicate() { return }
      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  func scrollToBottom() async {
    for _ in 0..<4 {
      window.layoutIfNeeded()
      if let scroll = scroll(in: host.view) {
        scroll.setContentOffset(
          CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)),
          animated: false)
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  func savePreview(_ name: String) throws {
    window.layoutIfNeeded()
    let rendered = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
      host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }
    let url = FileManager.default.temporaryDirectory.appending(path: "danger-zone-\(name).png")
    try rendered.pngData()?.write(to: url)
    print("Danger Zone synthetic preview: \(url.path)")
  }

  func close() {
    window.isHidden = true
    window.rootViewController = nil
    previous?.makeKey()
  }
}
