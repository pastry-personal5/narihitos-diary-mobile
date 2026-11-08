import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

@MainActor
@Suite(.serialized)
struct CatalogCollectionPresentationTests {
  @Test func mountedFooterDoesNotDrainAndAccessibleContinuationLoadsTenMore() async throws {
    let fixture = try await CatalogCollectionFixture()
    defer { fixture.close() }
    fixture.scrollToBottom(fixture.host.view)
    try await fixture.wait { fixture.element("catalog-load-more") != nil }
    try await Task.sleep(for: .milliseconds(150))
    #expect(fixture.port.demands == [10])
    #expect(fixture.model.rows.count == 10)
    #expect(fixture.element("catalog-loading-more") == nil)
    let button = try #require(fixture.element("catalog-load-more"))
    #expect(button.accessibilityTraits.contains(.button))
    #expect(button.accessibilityFrame.height >= 44)
    #expect(button.accessibilityActivate())
    try await fixture.wait {
      fixture.model.rows.count == 20 && fixture.model.remembered?.isReading == false
    }
    #expect(fixture.port.demands == [10, 20])
    try fixture.preview("light")
    fixture.state.large = true
    fixture.state.dark = true
    try await Task.sleep(for: .milliseconds(100))
    fixture.scrollToBottom(fixture.host.view)
    try await fixture.wait { fixture.element("catalog-load-more") != nil }
    #expect(fixture.port.demands == [10, 20])
    #expect(try #require(fixture.element("catalog-load-more")).accessibilityFrame.height >= 44)
    try fixture.preview("dark-large")
  }

  @Test func rememberedTapShowsOpeningUntilFreshDetailResolves() async throws {
    let fixture = try await CatalogCollectionFixture()
    defer { fixture.close() }
    fixture.port.holdResolve = true
    let row = try #require(fixture.model.rows.first)
    let id = "catalog-row-" + row.id.rawValue.uuidString
    try await fixture.wait { fixture.element(id) != nil }
    #expect(try #require(fixture.element(id)).accessibilityActivate())
    try await fixture.wait {
      fixture.port.heldResolve != nil && fixture.element("catalog-opening") != nil
    }
    #expect(fixture.model.selectedItem == nil)
    fixture.port.heldResolve?.resume()
    try await fixture.wait { fixture.element("catalog-fresh-detail") != nil }
    #expect(fixture.model.detail != nil)
    #expect(fixture.model.selectedItem == fixture.model.detail?.handle)
    try fixture.preview("fresh-detail")
  }
}

@MainActor
final class CatalogCollectionViewState: ObservableObject {
  @Published var large = false
  @Published var dark = false
}

struct CatalogCollectionTestRoot: View {
  let model: CatalogModel
  let registry: CatalogDetailRendererRegistry
  @ObservedObject var state: CatalogCollectionViewState
  var body: some View {
    NavigationStack {
      CatalogCollectionView(catalog: model, openAll: {}, renderers: registry).navigationTitle(
        "Main")
    }
    .dynamicTypeSize(state.large ? .accessibility5 : .large)
    .preferredColorScheme(state.dark ? .dark : .light)
    .transaction { $0.disablesAnimations = true }
  }
}

@MainActor
final class CatalogCollectionFixture {
  let port = RememberedCatalogFixture(count: 50)
  let model: CatalogModel
  let state = CatalogCollectionViewState()
  let window: UIWindow
  let host: UIHostingController<CatalogCollectionTestRoot>
  private let previous: UIWindow?

  init() async throws {
    model = CatalogModel(catalog: port)
    model.setVisible(true)
    model.activate()
    var registry = CatalogDetailRendererRegistry()
    registry.register("test") { detail in
      AnyView(
        Text((detail.payload as? ReconciliationFixturePayload)?.text ?? "Unavailable")
          .accessibilityIdentifier("catalog-fresh-detail"))
    }
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    previous = scene.keyWindow
    window = UIWindow(windowScene: scene)
    host = UIHostingController(
      rootView: CatalogCollectionTestRoot(model: model, registry: registry, state: state))
    window.rootViewController = host
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    try await wait { self.model.rows.count == 10 && self.model.remembered?.isReading == false }
    try await Task.sleep(for: .milliseconds(100))
  }

  func close() {
    model.stop()
    window.isHidden = true
    previous?.makeKeyAndVisible()
  }

  func preview(_ name: String) throws {
    window.layoutIfNeeded()
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let picture = renderer.image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let path = FileManager.default.temporaryDirectory.appending(path: "ndm-catalog-\(name).png")
    try #require(picture.pngData()).write(to: path)
  }

  func scrollToBottom(_ view: UIView) {
    view.layoutIfNeeded()
    if let scroll = view as? UIScrollView {
      let bottom = max(
        -scroll.adjustedContentInset.top,
        scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
      scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    } else {
      for child in view.subviews { scrollToBottom(child) }
    }
  }

  func element(_ id: String) -> NSObject? {
    var visited: Set<ObjectIdentifier> = []
    return find(id, in: host.view, visited: &visited)
  }

  private func find(
    _ id: String, in object: NSObject, visited: inout Set<ObjectIdentifier>
  ) -> NSObject? {
    guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
    let matches =
      object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
      && object.value(forKey: "accessibilityIdentifier") as? String == id
    if matches { return object }
    var children = (object as? UIView)?.subviews.map { $0 as NSObject } ?? []
    children += (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
    let count = object.accessibilityElementCount()
    if count > 0, count < 256 {
      children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
    }
    for child in children {
      if let found = find(id, in: child, visited: &visited) { return found }
    }
    return nil
  }

  func wait(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<2_000 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Hosted catalog did not reach the expected state")
  }
}
