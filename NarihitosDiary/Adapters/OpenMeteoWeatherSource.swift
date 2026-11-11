import Foundation

private struct OpenMeteoCurrent: Decodable {
  let time: Int64
  let temperature2m: Double
  let weatherCode: Int
  enum CodingKeys: String, CodingKey {
    case time
    case temperature2m = "temperature_2m"
    case weatherCode = "weather_code"
  }
}

private struct OpenMeteoPayload: Decodable { let current: OpenMeteoCurrent }

/// Open-Meteo current conditions. Sends only two-decimal coordinates and two variable names
/// over HTTPS to a fixed host; no key, identifier, cache, cookie or retry. Any failure omits weather.
@MainActor
final class OpenMeteoWeatherSource: WeatherPort {
  nonisolated static let host = "api.open-meteo.com"
  nonisolated static let maximumResponseBytes = 16 * 1_024

  private let makeSession: () -> URLSession

  init(makeSession: @escaping () -> URLSession = OpenMeteoWeatherSource.ephemeralSession) {
    self.makeSession = makeSession
  }

  nonisolated static func ephemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 15
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
  }

  nonisolated static func requestURL(latitude: Double, longitude: Double) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = "/v1/forecast"
    // swiftlint:disable trailing_comma
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(ContextPolicy.roundedForRequest(latitude))),
      URLQueryItem(name: "longitude", value: String(ContextPolicy.roundedForRequest(longitude))),
      URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
      URLQueryItem(name: "timeformat", value: "unixtime"),
    ]
    // swiftlint:enable trailing_comma
    return components.url
  }

  nonisolated static func parse(_ data: Data) -> WeatherSample? {
    guard data.count <= maximumResponseBytes,
      let payload = try? JSONDecoder().decode(OpenMeteoPayload.self, from: data),
      payload.current.time > 0
    else { return nil }
    return WeatherSample(
      validAt: Date(timeIntervalSince1970: TimeInterval(payload.current.time)),
      temperatureCelsius: payload.current.temperature2m, weatherCode: payload.current.weatherCode)
  }

  func current(latitude: Double, longitude: Double, near start: Date) async -> WeatherSample? {
    guard let url = Self.requestURL(latitude: latitude, longitude: longitude) else { return nil }
    let session = makeSession()
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (bytes, response) = try? await session.bytes(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.url?.host?.lowercased() == Self.host, http.url?.scheme == "https",
      http.expectedContentLength <= Self.maximumResponseBytes
    else { return nil }
    var data = Data()
    do {
      for try await byte in bytes {
        guard data.count < Self.maximumResponseBytes else { return nil }
        data.append(byte)
      }
    } catch { return nil }
    return Self.parse(data)
  }
}
