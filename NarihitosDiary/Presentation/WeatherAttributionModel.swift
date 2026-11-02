import Combine
import Foundation
import UIKit

@MainActor
final class WeatherAttributionModel: ObservableObject {
  @Published private(set) var lightMark: UIImage?
  @Published private(set) var darkMark: UIImage?
  @Published private(set) var legalPage: URL?
  @Published private(set) var failed = false
  private let source: any WeatherAttributionPort
  private var loading = false

  init(source: any WeatherAttributionPort) { self.source = source }
  var ready: Bool { lightMark != nil && darkMark != nil && legalPage != nil }

  func load() async {
    guard !loading, !ready else { return }
    loading = true
    failed = false
    defer { loading = false }
    do {
      let material = try await source.load()
      guard let light = UIImage(data: material.lightMark),
        let dark = UIImage(data: material.darkMark),
        light.size.width <= 2_048, light.size.height <= 2_048,
        dark.size.width <= 2_048, dark.size.height <= 2_048,
        let page = URL(string: material.legalPage), page.scheme == "https"
      else { throw CatalogIssue.unavailable }
      try Task.checkCancellation()
      lightMark = light
      darkMark = dark
      legalPage = page
    } catch { failed = true }
  }
}
