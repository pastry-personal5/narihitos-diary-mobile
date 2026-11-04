import Combine
import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

@MainActor
private final class DiaryTestAttribution: WeatherAttributionPort {
  func load() async throws -> WeatherAttributionMaterial { throw CatalogIssue.unavailable }
}

@MainActor
final class DiaryPresentationState: ObservableObject {
  @Published var phase: ScenePhase = .active
  @Published var dark = false
  @Published var large = false
  @Published var showDetail = true
}

@MainActor
struct DiaryPresentationRoot: View {
  @ObservedObject var state: DiaryPresentationState
  @ObservedObject var actions: DiaryActionsModel
  let detail: CatalogDetail

  var body: some View {
    NavigationStack {
      if state.showDetail {
        CatalogDetailRendererRegistry.production(
          attributionSource: DiaryTestAttribution(), actions: actions
        )
        .render(detail)
        .navigationTitle("Diary Snippet")
        .navigationBarTitleDisplayMode(.inline)
      } else {
        Text("Main")
      }
    }
    .modifier(DiaryEditorPresentation(actions: actions))
    .environment(\.scenePhase, state.phase)
    .preferredColorScheme(state.dark ? .dark : .light)
    .dynamicTypeSize(state.large ? .accessibility5 : .large)
    .transaction { $0.disablesAnimations = true }
  }
}

@MainActor
final class DiaryPresentationFixture {
  let state = DiaryPresentationState()
  let actions = DiaryActionsModel()
  let store = MemoryDiaryEditStore()
  let player = TestReplayPlayer()
  let titleModel = EditTitleModel()
  let edits: DiaryEditCoordinator
  let replay: DiaryReplayCoordinator
  let window: UIWindow
  let host: UIHostingController<DiaryPresentationRoot>
  private let previous: UIWindow?

  init(legacy: Bool = false) async throws {
    let scene = try await Self.foregroundScene()
    edits = DiaryEditCoordinator(
      store: store,
      titles: DiaryTitlePolicy(model: titleModel, languageDetector: EditLanguageDetector()))
    replay = DiaryReplayCoordinator(player: player)
    actions.configure(edits: edits, replay: replay, changed: {})
    actions.updateScope(DestinationID(rawValue: store.destinationID))
    edits.activate()
    replay.activate()
    let handle = CatalogItemHandle(
      session: CatalogSessionID(), resource: UUID(), version: UUID(),
      kind: DiarySnippetSupportPolicy.kind)
    let snippet = try DiaryEditFixture.snippet()
    let detail = DiaryCatalogDetail(
      title: snippet.title, body: snippet.body.text, favorite: legacy ? nil : false,
      recordedAt: .now,
      duration: 60, language: "en-US", location: nil, weather: nil, audioAvailable: true,
      isLegacy: legacy,
      assetID: legacy ? nil : snippet.id.description)
    previous = scene.keyWindow
    window = UIWindow(windowScene: scene)
    host = UIHostingController(
      rootView: DiaryPresentationRoot(
        state: state, actions: actions, detail: CatalogDetail(handle: handle, payload: detail)))
    window.rootViewController = host
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
  }

  private static func foregroundScene() async throws -> UIWindowScene {
    for _ in 0..<200 {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) {
        return scene
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw DiaryEditIssue.unavailable
  }

  func element(_ id: String) -> NSObject? {
    var roots = [host.view!]
    var presented = host.presentedViewController
    while let value = presented {
      roots.append(value.view)
      presented = value.presentedViewController
    }
    var visited = Set<ObjectIdentifier>()
    for root in roots { if let value = find(id, object: root, visited: &visited) { return value } }
    return nil
  }

  // swiftlint:disable opening_brace
  private func find(_ id: String, object: NSObject, visited: inout Set<ObjectIdentifier>)
    -> NSObject?
  {
    guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
    let matches =
      object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
      && object.value(forKey: "accessibilityIdentifier") as? String == id
    if matches { return object }
    var children = (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
    let count = object.accessibilityElementCount()
    if count > 0, count < 256 {
      children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
    }
    children += (object as? UIView)?.subviews ?? []
    for child in children {
      if let value = find(id, object: child, visited: &visited) { return value }
    }
    return nil
  }
  // swiftlint:enable opening_brace

  func waitUntil(_ predicate: () -> Bool) async throws {
    for _ in 0..<100 {
      window.layoutIfNeeded()
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw DiaryEditIssue.busy
  }

  func activate(_ id: String) async throws {
    try await waitUntil { element(id) != nil }
    let control = try #require(element(id))
    #expect(control.accessibilityTraits.contains(.button))
    #expect(control.accessibilityActivate())
    await Task.yield()
  }

  func preview(_ name: String, size: CGSize) async throws {
    window.frame = CGRect(origin: .zero, size: size)
    var controller: UIViewController? = host
    while let current = controller {
      current.overrideUserInterfaceStyle = state.dark ? .dark : .light
      current.traitOverrides.preferredContentSizeCategory =
        state.large ? .accessibilityExtraExtraExtraLarge : .large
      controller = current.presentedViewController
    }
    try await Task.sleep(for: .milliseconds(100))
    for _ in 0..<3 {
      await Task.yield()
      window.layoutIfNeeded()
    }
    let view = host.presentedViewController?.view ?? host.view!
    let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
      view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
    }
    let url = FileManager.default.temporaryDirectory
      .appending(path: "diary-presentation-\(name).png")
    try image.pngData()?.write(to: url)
    print("Diary presentation synthetic preview: \(url.path)")
  }

  func close() {
    edits.deactivate()
    replay.deactivate()
    host.dismiss(animated: false)
    window.isHidden = true
    window.rootViewController = nil
    previous?.makeKey()
  }
}
