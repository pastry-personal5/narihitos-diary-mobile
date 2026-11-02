import Foundation

struct WeatherAttributionMaterial: Sendable {
  let lightMark: Data
  let darkMark: Data
  let legalPage: String
}

@MainActor
protocol WeatherAttributionPort: AnyObject {
  func load() async throws -> WeatherAttributionMaterial
}
