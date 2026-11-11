import Combine
import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

@MainActor
@Suite(.serialized)
struct RecordingRemovalPresentationTests {
  // swiftlint:disable:next function_body_length
  @Test func removalRequiresInlineConfirmationAndCancelDoesNothing() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let fixture = try RemovalPresentationFixture()
    defer { fixture.close() }

    let failedEntries = fixture.entries
    try await fixture.savePreview("failed-actions-light", size: CGSize(width: 375, height: 812))
    fixture.state.title = "Pending Recordings"
    fixture.entries = [
      QueueProjection(
        id: "first", startedAt: Date(timeIntervalSince1970: 1), language: .english,
        state: .readyToSave, reason: "Waiting for iCloud upload verification."),
      QueueProjection(
        id: "second", startedAt: Date(timeIntervalSince1970: 2), language: .english,
        state: .waiting, reason: "Cohere model isn’t installed."),
    ]
    try await fixture.savePreview("pending-actions-light", size: CGSize(width: 375, height: 812))
    fixture.state.title = "Failed Recordings"
    fixture.entries = failedEntries
    fixture.state.scheme = .dark
    fixture.state.typeSize = .accessibility5
    try await fixture.savePreview(
      "failed-actions-dark-large", size: CGSize(width: 375, height: 812))
    fixture.state.scheme = .light
    fixture.state.typeSize = .large
    try await fixture.savePreview("actions-wide", size: CGSize(width: 812, height: 375))
    windowSizeRestore(fixture)

    try await fixture.activate("recording-remove-first")
    await fixture.waitFor { fixture.element("recording-remove-confirm-first") != nil }
    #expect(fixture.element("recording-remove-confirmation-first") != nil)
    #expect(fixture.host.presentedViewController == nil)
    #expect(fixture.removed.isEmpty)
    #expect(fixture.retried.isEmpty)
    try await fixture.savePreview("light", size: CGSize(width: 375, height: 812))
    fixture.state.scheme = .dark
    fixture.state.typeSize = .accessibility5
    try await fixture.savePreview("dark-large", size: CGSize(width: 375, height: 812))
    fixture.state.scheme = .light
    fixture.state.typeSize = .large
    try await fixture.savePreview("landscape", size: CGSize(width: 812, height: 375))
    windowSizeRestore(fixture)

    try await fixture.activate("recording-remove-cancel-first")
    await fixture.waitFor { fixture.element("recording-remove-first") != nil }
    #expect(fixture.element("recording-remove-confirm-first") == nil)
    #expect(fixture.removed.isEmpty)

    try await fixture.activate("recording-remove-second")
    await fixture.waitFor { fixture.element("recording-remove-confirm-second") != nil }
    let confirmation = try #require(fixture.element("recording-remove-confirm-second"))
    #expect(confirmation.accessibilityActivate())
    _ = confirmation.accessibilityActivate()
    await fixture.waitFor { fixture.removed == ["second"] }
    #expect(fixture.removed == ["second"])
    #expect(fixture.retried.isEmpty)
  }

  private func windowSizeRestore(_ fixture: RemovalPresentationFixture) {
    fixture.window.frame = fixture.window.windowScene?.screen.bounds ?? fixture.window.frame
    fixture.window.layoutIfNeeded()
  }

  @Test func anotherSelectionAndCancellingCannotLeaveAnArmedRemoval() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let fixture = try RemovalPresentationFixture()
    defer { fixture.close() }

    try await fixture.activate("recording-remove-first")
    try await fixture.activate("recording-remove-second")
    await fixture.waitFor { fixture.element("recording-remove-confirm-second") != nil }
    #expect(fixture.element("recording-remove-confirm-first") == nil)

    fixture.entries[1] = QueueProjection(
      id: "second", startedAt: Date(timeIntervalSince1970: 2), language: .english,
      state: .cancelling, reason: nil)
    await fixture.waitFor { fixture.element("recording-remove-confirm-second") == nil }
    #expect(fixture.element("recording-remove-second") == nil)
    #expect(fixture.removed.isEmpty)

    fixture.entries.removeAll { $0.id == "second" }
    await fixture.waitFor { fixture.element("recording-remove-first") != nil }
    try await fixture.activate("recording-remove-first")
    await fixture.waitFor { fixture.element("recording-remove-confirm-first") != nil }
    let first = try #require(fixture.entries.first)
    fixture.entries = []
    await fixture.waitFor { fixture.element("recording-remove-confirm-first") == nil }
    fixture.entries = [first]
    await fixture.waitFor { fixture.element("recording-remove-first") != nil }
    #expect(fixture.element("recording-remove-confirm-first") == nil)
    #expect(fixture.removed.isEmpty)
    #expect(fixture.host.presentedViewController == nil)
  }

  @Test func sceneDepartureDisarmsConfirmation() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let fixture = try RemovalPresentationFixture()
    defer { fixture.close() }

    try await fixture.activate("recording-remove-first")
    await fixture.waitFor { fixture.element("recording-remove-confirm-first") != nil }
    fixture.phase = .inactive
    await fixture.waitFor { fixture.element("recording-remove-confirm-first") == nil }
    fixture.phase = .active
    await fixture.waitFor { fixture.element("recording-remove-first") != nil }

    #expect(fixture.element("recording-remove-confirm-first") == nil)
    #expect(fixture.removed.isEmpty)
  }
}

@MainActor
private final class RemovalPresentationState: ObservableObject {
  @Published var entries = [
    QueueProjection(
      id: "first", startedAt: Date(timeIntervalSince1970: 1), language: .english,
      state: .failed, reason: "This recording can’t be read."),
    QueueProjection(
      id: "second", startedAt: Date(timeIntervalSince1970: 2), language: .english,
      state: .failed, reason: "Transcription couldn’t finish."),
  ]
  @Published var phase: ScenePhase = .active
  @Published var title = "Failed Recordings"
  @Published var scheme: ColorScheme = .light
  @Published var typeSize: DynamicTypeSize = .large
  var removed: [String] = []
  var retried: [String] = []
}

@MainActor
private final class RemovalPresentationFixture {
  let state = RemovalPresentationState()
  let window: UIWindow
  let host: UIHostingController<RemovalTestList>
  private let previousWindow: UIWindow?
  private var inspectedElements: [String] = []

  var removed: [String] { state.removed }
  var retried: [String] { state.retried }
  var entries: [QueueProjection] {
    get { state.entries }
    set { state.entries = newValue }
  }
  var phase: ScenePhase {
    get { state.phase }
    set { state.phase = newValue }
  }

  init() throws {
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    previousWindow = scene.keyWindow
    window = UIWindow(windowScene: scene)
    host = UIHostingController(rootView: RemovalTestList(state: state))
    window.rootViewController = host
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
  }

  func activate(_ identifier: String) async throws {
    await waitFor { self.element(identifier) != nil }
    if element(identifier) == nil {
      print("Hosted removal accessibility tree: \(inspectedElements.joined(separator: " | "))")
      let preview = FileManager.default.temporaryDirectory.appending(
        path: "removal-test-preview.png")
      let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
      }
      try image.pngData()?.write(to: preview)
      print("Hosted removal preview: \(preview.path)")
    }
    let target = try #require(element(identifier), "Missing accessible control: \(identifier)")
    #expect(target.accessibilityActivate())
  }

  func element(_ identifier: String) -> NSObject? {
    var visited = Set<ObjectIdentifier>()
    inspectedElements = []
    return find(identifier, in: host.view, visited: &visited)
  }

  func waitFor(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<80 {
      window.layoutIfNeeded()
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  func close() {
    host.dismiss(animated: false)
    window.isHidden = true
    window.rootViewController = nil
    previousWindow?.makeKey()
  }

  func savePreview(_ name: String, size: CGSize) async throws {
    window.frame = CGRect(origin: .zero, size: size)
    for _ in 0..<3 {
      await Task.yield()
      window.layoutIfNeeded()
    }
    let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
      host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }
    let url = FileManager.default.temporaryDirectory.appending(path: "inline-removal-\(name).png")
    try image.pngData()?.write(to: url)
    print("Inline removal preview: \(url.path)")
  }

  private func find(
    _ identifier: String, in object: NSObject, visited: inout Set<ObjectIdentifier>
  ) -> NSObject? {
    guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
    let elementID =
      object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
      ? object.value(forKey: "accessibilityIdentifier") as? String : nil
    let label = elementID ?? object.accessibilityLabel ?? "-"
    inspectedElements.append("\(type(of: object)): \(label)")
    if elementID == identifier {
      return object
    }
    var children: [NSObject] = (object as? UIView)?.subviews ?? []
    children += (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
    let count = object.accessibilityElementCount()
    if count > 0, count < 256 {
      children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
    }
    for child in children {
      if let match = find(identifier, in: child, visited: &visited) { return match }
    }
    return nil
  }
}

private struct RemovalTestList: View {
  @ObservedObject var state: RemovalPresentationState

  var body: some View {
    NavigationStack {
      CaptureListView(
        title: state.title, captures: [], queueEntries: state.entries,
        onRetry: { state.retried.append($0) }, onRemove: { state.removed.append($0) })
    }
    .environment(\.scenePhase, state.phase)
    .preferredColorScheme(state.scheme)
    .dynamicTypeSize(state.typeSize)
    .transaction { $0.disablesAnimations = true }
  }
}

// swiftlint:enable trailing_comma
