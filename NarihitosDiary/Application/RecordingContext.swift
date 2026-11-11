import Foundation

// MARK: Plain values and ports (no platform types cross this boundary)

struct LocationSample: Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let horizontalAccuracy: Double
  let timestamp: Date
}

struct WeatherSample: Equatable, Sendable {
  let validAt: Date
  let temperatureCelsius: Double
  let weatherCode: Int
}

@MainActor
protocol LocationSamplePort: AnyObject {
  /// One bounded foreground fix. Must honor task cancellation and release the platform manager.
  func currentLocation() async -> LocationSample?
}

@MainActor
protocol PlaceNamePort: AnyObject {
  func placeName(latitude: Double, longitude: Double) async -> String?
}

@MainActor
protocol WeatherPort: AnyObject {
  /// Receives full-precision accepted coordinates; the adapter rounds before any request.
  func current(latitude: Double, longitude: Double, near start: Date) async -> WeatherSample?
}

/// Live gates checked before acquisition, before each outbound lookup and before acceptance.
@MainActor
protocol ContextGate: AnyObject {
  var locationAllowed: Bool { get }
  var weatherAllowed: Bool { get }
}

struct ContextSnapshot: Equatable, Sendable {
  var location: LocationContext?
  var weather: WeatherContext?
  var isEmpty: Bool { location == nil && weather == nil }
}

// MARK: Acceptance policy

enum ContextPolicy {
  static let locationLeadSeconds: TimeInterval = 300
  static let maximumAccuracyMeters = 500.0
  static let weatherToleranceSeconds: TimeInterval = 3_600
  static let maximumPlaceBytes = 256

  static func acceptLocation(_ sample: LocationSample, start: Date, now: Date) -> LocationContext? {
    guard sample.latitude.isFinite, sample.longitude.isFinite, sample.horizontalAccuracy.isFinite,
      (-90.0...90.0).contains(sample.latitude), (-180.0...180.0).contains(sample.longitude),
      sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maximumAccuracyMeters,
      sample.timestamp >= start.addingTimeInterval(-locationLeadSeconds),
      sample.timestamp >= now.addingTimeInterval(-locationLeadSeconds),
      sample.timestamp <= now,
      let latitude = decimal(sample.latitude), let longitude = decimal(sample.longitude),
      let accuracy = decimal(sample.horizontalAccuracy),
      let sampled = try? SchemaInstant.from(date: sample.timestamp)
    else { return nil }
    return LocationContext(
      latitude: latitude, longitude: longitude, sampledAt: sampled,
      horizontalAccuracyMeters: accuracy, placeName: nil)
  }

  static func acceptWeather(_ sample: WeatherSample, start: Date) -> WeatherContext? {
    guard sample.temperatureCelsius.isFinite, (-100.0...70.0).contains(sample.temperatureCelsius),
      abs(sample.validAt.timeIntervalSince(start)) <= weatherToleranceSeconds,
      let summary = weatherSummary(code: sample.weatherCode),
      let temperature = decimal(sample.temperatureCelsius),
      let observed = try? SchemaInstant.from(date: sample.validAt)
    else { return nil }
    return WeatherContext(observedAt: observed, summary: summary, temperatureCelsius: temperature)
  }

  static func cleanPlace(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.utf8.count <= maximumPlaceBytes,
      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    return value
  }

  /// Exact returned value: the shortest round-trip spelling, never binary noise.
  static func decimal(_ value: Double) -> Decimal? {
    guard value.isFinite else { return nil }
    return Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX"))
  }

  /// Two decimals (about 1 km) is all an outbound weather request may carry.
  static func roundedForRequest(_ value: Double) -> Double { (value * 100).rounded() / 100 }

  // swiftlint:disable:next cyclomatic_complexity
  static func weatherSummary(code: Int) -> String? {
    switch code {
    case 0: "Clear sky"
    case 1: "Mainly clear"
    case 2: "Partly cloudy"
    case 3: "Overcast"
    case 45: "Fog"
    case 48: "Depositing rime fog"
    case 51: "Light drizzle"
    case 53: "Moderate drizzle"
    case 55: "Dense drizzle"
    case 56, 57: "Freezing drizzle"
    case 61: "Slight rain"
    case 63: "Moderate rain"
    case 65: "Heavy rain"
    case 66, 67: "Freezing rain"
    case 71: "Slight snowfall"
    case 73: "Moderate snowfall"
    case 75: "Heavy snowfall"
    case 77: "Snow grains"
    case 80, 81, 82: "Rain showers"
    case 85, 86: "Snow showers"
    case 95: "Thunderstorm"
    case 96, 99: "Thunderstorm with hail"
    case 97: "Heavy thunderstorm"
    default: nil
    }
  }
}

// MARK: Durable envelope

enum ContextEnvelopeState: String, Codable, Sendable { case collecting, sealed, omitted }

struct ContextEnvelope: Codable, Equatable, Sendable {
  static let version = 1
  static let maximumBytes = 32 * 1_024
  var version = Self.version
  var ownerID: String
  var start: String
  var installation: String?
  var state: ContextEnvelopeState = .collecting
  var latitude: String?
  var longitude: String?
  var accuracy: String?
  var sampledAt: String?
  var placeName: String?
  var weatherObservedAt: String?
  var weatherSummary: String?
  var temperature: String?

  init(ownerID: String, start: Date, installation: String?) throws {
    self.ownerID = ownerID
    self.start = try SchemaInstant.from(date: start).description
    self.installation = installation
  }

  // swift-format places braces after multiline condition lists; SwiftLint requires the opposite.
  // swiftlint:disable opening_brace
  var snapshot: ContextSnapshot {
    get {
      var result = ContextSnapshot()
      if let latitude = Self.decimal(latitude), let longitude = Self.decimal(longitude),
        let accuracy = Self.decimal(accuracy), let sampledAt,
        let sampled = try? SchemaInstant(sampledAt),
        (-90...90).contains(latitude), (-180...180).contains(longitude), accuracy >= 0,
        accuracy <= Decimal(ContextPolicy.maximumAccuracyMeters)
      {
        result.location = LocationContext(
          latitude: latitude, longitude: longitude, sampledAt: sampled,
          horizontalAccuracyMeters: accuracy,
          placeName: ContextPolicy.cleanPlace(placeName))
      }
      if result.location != nil, let weatherObservedAt, let weatherSummary,
        let temperature = Self.decimal(temperature),
        let observed = try? SchemaInstant(weatherObservedAt),
        temperature >= Decimal(-100), temperature <= Decimal(70),
        temperature.isFinite, ContextPolicy.isKnownSummary(weatherSummary)
      {
        result.weather = WeatherContext(
          observedAt: observed, summary: weatherSummary, temperatureCelsius: temperature)
      }
      return result
    }
    set {
      latitude = newValue.location.map { Self.string($0.latitude) }
      longitude = newValue.location.map { Self.string($0.longitude) }
      accuracy = newValue.location.map { Self.string($0.horizontalAccuracyMeters) }
      sampledAt = newValue.location?.sampledAt.description
      placeName = newValue.location?.placeName
      weatherObservedAt = newValue.weather?.observedAt.description
      weatherSummary = newValue.weather?.summary
      temperature = newValue.weather.map { Self.string($0.temperatureCelsius) }
    }
  }

  // swiftlint:enable opening_brace

  private static func decimal(_ raw: String?) -> Decimal? {
    raw.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
  }

  private static func string(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
  }
}

extension ContextPolicy {
  static func isKnownSummary(_ value: String) -> Bool {
    (0...99).contains { weatherSummary(code: $0) == value }
  }
}

protocol ContextEnvelopeStore: AnyObject {
  /// nil when absent; throws only for unavailable/corrupt storage. Callers treat both as omission.
  func load(ownerID: String) throws -> ContextEnvelope?
  func save(_ envelope: ContextEnvelope) throws
  func delete(ownerID: String) throws
}

// MARK: Coordinator

/// One cancellable acquisition per recording. Nothing here is awaited by capture, settlement,
/// transcription, drafting or saving; `seal` is synchronous.
@MainActor
final class RecordingContextCoordinator {
  static let locationBudget: Duration = .seconds(15)
  static let enrichmentBudget: Duration = .seconds(15)

  private let location: any LocationSamplePort
  private let place: any PlaceNamePort
  private let weather: any WeatherPort
  private let gate: any ContextGate
  private let store: any ContextEnvelopeStore
  private let now: () -> Date
  private var epoch = 0
  private var task: Task<Void, Never>?

  init(
    location: any LocationSamplePort, place: any PlaceNamePort, weather: any WeatherPort,
    gate: any ContextGate, store: any ContextEnvelopeStore, now: @escaping () -> Date = Date.init
  ) {
    self.location = location
    self.place = place
    self.weather = weather
    self.gate = gate
    self.store = store
    self.now = now
  }

  var isAcquiring: Bool { task != nil }

  /// Call only after audio (or a manual first Save) has genuinely started.
  func begin(ownerID: String, start: Date, installation: String?) {
    cancel()
    guard gate.locationAllowed,
      let initial = try? ContextEnvelope(ownerID: ownerID, start: start, installation: installation)
    else { return }
    let epoch = self.epoch
    task = Task { [weak self] in
      guard let self else { return }
      var envelope = initial
      await self.acquire(&envelope, start: start, epoch: epoch)
      if self.epoch == epoch { self.task = nil }
    }
  }

  /// Stops acquisition: departure, opt-out/revocation, failed capture, removal, supersession.
  func cancel() {
    epoch += 1
    task?.cancel()
    task = nil
  }

  /// Synchronously freezes whatever was accepted. Later enrichment is rejected by the epoch bump
  /// and by the sealed state. Missing/invalid/foreign envelopes yield nil (old jobs, omission).
  func seal(ownerID: String, start: Date, installation: String?) -> ContextSnapshot? {
    cancel()
    guard var envelope = try? store.load(ownerID: ownerID),
      envelope.version == ContextEnvelope.version, envelope.ownerID == ownerID,
      envelope.installation == installation,
      envelope.start == (try? SchemaInstant.from(date: start).description)
    else { return nil }
    var snapshot = envelope.snapshot
    if !gate.locationAllowed { snapshot = ContextSnapshot() }
    if !gate.weatherAllowed { snapshot.weather = nil }
    if envelope.state != .sealed {
      envelope.state = snapshot.isEmpty ? .omitted : .sealed
      envelope.snapshot = snapshot
      try? store.save(envelope)
    }
    return snapshot.isEmpty ? nil : snapshot
  }

  func discard(ownerID: String) {
    cancel()
    try? store.delete(ownerID: ownerID)
  }

  // MARK: acquisition

  private func current(_ epoch: Int) -> Bool { self.epoch == epoch && !Task.isCancelled }

  private func acquire(_ envelope: inout ContextEnvelope, start: Date, epoch: Int) async {
    guard
      let sample = await Self.within(
        Self.locationBudget, { await self.location.currentLocation() }),
      current(epoch), gate.locationAllowed,
      var accepted = ContextPolicy.acceptLocation(sample, start: start, now: now())
    else { return }
    envelope.snapshot = ContextSnapshot(location: accepted)
    guard (try? store.save(envelope)) != nil else { return }
    let weatherWanted = gate.weatherAllowed
    async let name = Self.within(Self.enrichmentBudget) {
      await self.place.placeName(latitude: sample.latitude, longitude: sample.longitude)
    }
    async let sky: WeatherSample? =
      weatherWanted
      ? Self.within(Self.enrichmentBudget) {
        await self.weather.current(
          latitude: sample.latitude, longitude: sample.longitude, near: start)
      } : nil
    let (rawName, rawSky) = await (name, sky)
    guard current(epoch), gate.locationAllowed else { return }
    accepted.placeName = ContextPolicy.cleanPlace(rawName)
    var snapshot = ContextSnapshot(location: accepted)
    if gate.weatherAllowed, let rawSky {
      snapshot.weather = ContextPolicy.acceptWeather(rawSky, start: start)
    }
    envelope.snapshot = snapshot
    try? store.save(envelope)
  }

  private static func within<T: Sendable>(
    _ budget: Duration, _ operation: @escaping @MainActor @Sendable () async -> T?
  ) async -> T? {
    await withTaskGroup(of: T?.self) { group in
      group.addTask { await operation() }
      group.addTask {
        try? await Task.sleep(for: budget)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }
}

// MARK: Preferences

@MainActor
protocol ContextPreferenceStore: AnyObject {
  func loadLocationContextEnabled() -> Bool?
  func loadWeatherContextEnabled() -> Bool
  func saveLocationContextEnabled(_ value: Bool) throws
  func saveWeatherContextEnabled(_ value: Bool) throws
}

/// The system can only narrow the app preference: denial or disabled services win over On.
@MainActor
final class LivePreferenceContextGate: ContextGate {
  private let preferences: any ContextPreferenceStore
  private let location: any LocationAuthorizationPort

  init(preferences: any ContextPreferenceStore, location: any LocationAuthorizationPort) {
    self.preferences = preferences
    self.location = location
  }

  var locationAllowed: Bool {
    preferences.loadLocationContextEnabled() != false && location.currentState() == .authorized
  }

  var weatherAllowed: Bool { locationAllowed && preferences.loadWeatherContextEnabled() }
}

/// Manual-snippet context is intentionally not durable: a restart omits it (shortcut: no crash
/// persistence for manual context; upgrade if manual context must survive termination).
final class InMemoryContextEnvelopeStore: ContextEnvelopeStore {
  private var items: [String: ContextEnvelope] = [:]
  func load(ownerID: String) throws -> ContextEnvelope? { items[ownerID] }
  func save(_ envelope: ContextEnvelope) throws { items[envelope.ownerID] = envelope }
  func delete(ownerID: String) throws { items[ownerID] = nil }
}
