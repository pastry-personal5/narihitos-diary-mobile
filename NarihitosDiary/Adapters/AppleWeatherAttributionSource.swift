import Foundation
import WeatherKit

/// Only Apple's public attribution material is requested; there is no context lookup.
@MainActor
final class AppleWeatherAttributionSource: WeatherAttributionPort {
  func load() async throws -> WeatherAttributionMaterial {
    let attribution = try await WeatherService.shared.attribution
    guard Self.allowed(attribution.legalPageURL),
      Self.allowed(attribution.combinedMarkLightURL), Self.allowed(attribution.combinedMarkDarkURL)
    else { throw CatalogIssue.unavailable }
    let light = try await mark(attribution.combinedMarkLightURL)
    let dark = try await mark(attribution.combinedMarkDarkURL)
    return WeatherAttributionMaterial(
      lightMark: light, darkMark: dark, legalPage: attribution.legalPageURL.absoluteString)
  }

  private func mark(_ url: URL) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(from: url)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      let final = response.url, Self.allowed(final),
      response.expectedContentLength <= 262_144
    else { throw CatalogIssue.unavailable }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 262_144 else { throw CatalogIssue.unavailable }
      data.append(byte)
    }
    return data
  }

  private static func allowed(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil,
      url.password == nil
    else { return false }
    return host == "apple.com" || host.hasSuffix(".apple.com")
  }
}
