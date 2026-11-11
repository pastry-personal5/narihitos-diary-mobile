// swift-format wraps multiline declarations and collections.
// swiftlint:disable file_length trailing_comma
import Foundation
import Testing

@testable import NarihitosDiary

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let ownerID = "123e4567-e89b-42d3-a456-426614174000"

@MainActor
private final class FakeLocation: LocationSamplePort {
  var sample: LocationSample?
  var gateTask: CheckedContinuation<Void, Never>?
  var holds = false
  func currentLocation() async -> LocationSample? {
    if holds { await withCheckedContinuation { gateTask = $0 } }
    return sample
  }
  func release() {
    gateTask?.resume()
    gateTask = nil
  }
}

@MainActor
private final class FakePlace: PlaceNamePort {
  var name: String? = "Somewhere"
  var calls = 0
  func placeName(latitude: Double, longitude: Double) async -> String? {
    calls += 1
    return name
  }
}

@MainActor
private final class FakeWeather: WeatherPort {
  var sample: WeatherSample?
  var calls: [(Double, Double)] = []
  func current(latitude: Double, longitude: Double, near start: Date) async -> WeatherSample? {
    calls.append((latitude, longitude))
    return sample
  }
}

@MainActor
private final class FakeGate: ContextGate {
  var locationAllowed = true
  var weatherAllowed = true
}

private final class MemoryEnvelopeStore: ContextEnvelopeStore {
  var items: [String: ContextEnvelope] = [:]
  var failSave = false
  func load(ownerID: String) throws -> ContextEnvelope? { items[ownerID] }
  func save(_ envelope: ContextEnvelope) throws {
    if failSave { throw PrivateWorkspaceFailureCode.atomicWriteFailed }
    items[envelope.ownerID] = envelope
  }
  func delete(ownerID: String) throws { items[ownerID] = nil }
}

struct ContextPolicyTests {
  private func fix(
    lat: Double = 37.5665, lon: Double = 126.978, accuracy: Double = 65,
    at time: Date = start
  ) -> LocationSample {
    LocationSample(latitude: lat, longitude: lon, horizontalAccuracy: accuracy, timestamp: time)
  }

  @Test func locationThresholdsAreInclusiveAndJustOutsideRejects() {
    let now = start.addingTimeInterval(10)
    #expect(ContextPolicy.acceptLocation(fix(accuracy: 500), start: start, now: now) != nil)
    #expect(ContextPolicy.acceptLocation(fix(accuracy: 500.01), start: start, now: now) == nil)
    #expect(ContextPolicy.acceptLocation(fix(accuracy: -1), start: start, now: now) == nil)
    // Exactly five minutes before the start is accepted; one second older is not.
    let atEdge = start.addingTimeInterval(-300)
    #expect(ContextPolicy.acceptLocation(fix(at: atEdge), start: start, now: start) != nil)
    #expect(
      ContextPolicy.acceptLocation(fix(at: atEdge.addingTimeInterval(-1)), start: start, now: start)
        == nil)
    // Older than five minutes at acceptance even though newer than the start window.
    #expect(
      ContextPolicy.acceptLocation(fix(), start: start, now: start.addingTimeInterval(301)) == nil)
    #expect(
      ContextPolicy.acceptLocation(fix(), start: start, now: start.addingTimeInterval(300)) != nil)
    // Future relative to the callback time.
    #expect(
      ContextPolicy.acceptLocation(fix(at: now.addingTimeInterval(1)), start: start, now: now)
        == nil)
  }

  @Test func rejectsNonFiniteAndOutOfRangeCoordinates() {
    let now = start
    for bad in [Double.nan, .infinity, -.infinity] {
      #expect(ContextPolicy.acceptLocation(fix(lat: bad), start: start, now: now) == nil)
      #expect(ContextPolicy.acceptLocation(fix(lon: bad), start: start, now: now) == nil)
      #expect(ContextPolicy.acceptLocation(fix(accuracy: bad), start: start, now: now) == nil)
    }
    #expect(ContextPolicy.acceptLocation(fix(lat: 90.0001), start: start, now: now) == nil)
    #expect(ContextPolicy.acceptLocation(fix(lon: -180.0001), start: start, now: now) == nil)
    #expect(ContextPolicy.acceptLocation(fix(lat: -90, lon: 180), start: start, now: now) != nil)
  }

  @Test func returnedCoordinatesAreStoredWithoutBinaryNoiseOrRounding() throws {
    let accepted = try #require(
      ContextPolicy.acceptLocation(
        fix(lat: 37.566535, lon: 126.977969), start: start, now: start))
    #expect(NSDecimalNumber(decimal: accepted.latitude).stringValue == "37.566535")
    #expect(NSDecimalNumber(decimal: accepted.longitude).stringValue == "126.977969")
    #expect(ContextPolicy.roundedForRequest(37.566535) == 37.57)
  }

  @Test func weatherToleranceCodesTemperatureAndSummaryAreEnforced() {
    func sky(_ offset: TimeInterval, _ code: Int = 1, _ celsius: Double = 12.5) -> WeatherSample {
      WeatherSample(
        validAt: start.addingTimeInterval(offset), temperatureCelsius: celsius, weatherCode: code)
    }
    #expect(ContextPolicy.acceptWeather(sky(3_600), start: start)?.summary == "Mainly clear")
    #expect(ContextPolicy.acceptWeather(sky(-3_600), start: start) != nil)
    #expect(ContextPolicy.acceptWeather(sky(3_601), start: start) == nil)
    #expect(ContextPolicy.acceptWeather(sky(0, 4), start: start) == nil)
    #expect(ContextPolicy.acceptWeather(sky(0, 1, .nan), start: start) == nil)
    #expect(ContextPolicy.acceptWeather(sky(0, 1, 500), start: start) == nil)
  }

  @Test func placeLabelsAreBoundedAndControlFree() {
    #expect(ContextPolicy.cleanPlace("  서울  ") == "서울")
    #expect(ContextPolicy.cleanPlace("") == nil)
    #expect(ContextPolicy.cleanPlace("a\u{0}b") == nil)
    #expect(ContextPolicy.cleanPlace(String(repeating: "x", count: 257)) == nil)
    #expect(ContextPolicy.cleanPlace(String(repeating: "x", count: 256)) != nil)
  }
}

@MainActor
struct RecordingContextCoordinatorTests {
  @MainActor private struct Rig {
    let location = FakeLocation()
    let place = FakePlace()
    let weather = FakeWeather()
    let gate = FakeGate()
    let store = MemoryEnvelopeStore()
    let coordinator: RecordingContextCoordinator

    init(now: Date = start) {
      coordinator = RecordingContextCoordinator(
        location: location, place: place, weather: weather, gate: gate, store: store,
        now: { now })
      location.sample = LocationSample(
        latitude: 37.5, longitude: 127.0, horizontalAccuracy: 50, timestamp: now)
      weather.sample = WeatherSample(validAt: now, temperatureCelsius: 20, weatherCode: 0)
    }

    func settle() async {
      for _ in 0..<50 where coordinator.isAcquiring { await Task.yield() }
    }
  }

  @Test func acceptedLocationPlaceAndWeatherSurviveSealing() async throws {
    let rig = Rig()
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: "inst")
    await rig.settle()
    let sealed = try #require(
      rig.coordinator.seal(ownerID: ownerID, start: start, installation: "inst"))
    #expect(sealed.location?.placeName == "Somewhere")
    #expect(sealed.weather?.summary == "Clear sky")
    // Rounded coordinates are the adapter's job; the port receives exact accepted values.
    #expect(rig.weather.calls.count == 1)
  }

  @Test func sealIsSynchronousAndRejectsLaterEnrichment() async throws {
    let rig = Rig()
    rig.location.holds = true
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    await Task.yield()
    // Nothing accepted yet: sealing must not wait and yields nil without an envelope.
    #expect(rig.coordinator.seal(ownerID: ownerID, start: start, installation: nil) == nil)
    rig.location.holds = false
    rig.location.release()
    await rig.settle()
    #expect(rig.store.items[ownerID] == nil)
    #expect(rig.place.calls == 0)
  }

  @Test func earlySealKeepsLocationOnlyAndLateResultsAreDiscarded() async throws {
    let rig = Rig()
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    // Let the location land, then seal before place/weather finish by cancelling immediately.
    for _ in 0..<3 { await Task.yield() }
    let sealed = rig.coordinator.seal(ownerID: ownerID, start: start, installation: nil)
    await rig.settle()
    let again = rig.coordinator.seal(ownerID: ownerID, start: start, installation: nil)
    #expect(sealed == again)
    #expect(rig.store.items[ownerID]?.state != .collecting)
  }

  @Test func optOutAndSystemDenialStopLookupsAndOmitStoredGroups() async throws {
    let rig = Rig()
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    await rig.settle()
    rig.gate.locationAllowed = false
    rig.gate.weatherAllowed = false
    #expect(rig.coordinator.seal(ownerID: ownerID, start: start, installation: nil) == nil)
    let denied = Rig()
    denied.gate.locationAllowed = false
    denied.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    #expect(!denied.coordinator.isAcquiring)
    #expect(denied.place.calls == 0 && denied.weather.calls.isEmpty)
  }

  @Test func weatherOffKeepsLocationAndSendsNoWeatherRequest() async throws {
    let rig = Rig()
    rig.gate.weatherAllowed = false
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    await rig.settle()
    let sealed = try #require(
      rig.coordinator.seal(ownerID: ownerID, start: start, installation: nil))
    #expect(sealed.location != nil && sealed.weather == nil)
    #expect(rig.weather.calls.isEmpty)
  }

  @Test func wrongInstallStartOrOwnerEnvelopesAreIsolated() async throws {
    let rig = Rig()
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: "a")
    await rig.settle()
    #expect(rig.coordinator.seal(ownerID: ownerID, start: start, installation: "b") == nil)
    #expect(
      rig.coordinator.seal(
        ownerID: ownerID, start: start.addingTimeInterval(5), installation: "a") == nil)
    #expect(
      rig.coordinator.seal(
        ownerID: "223e4567-e89b-42d3-a456-426614174000", start: start, installation: "a") == nil)
  }

  @Test func staleLocationAndWeatherFailureLeaveOtherGroupsIntact() async throws {
    let stale = Rig()
    stale.location.sample = LocationSample(
      latitude: 1, longitude: 1, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(-301))
    stale.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    await stale.settle()
    #expect(stale.store.items[ownerID] == nil)
    let noWeather = Rig()
    noWeather.weather.sample = nil
    noWeather.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    await noWeather.settle()
    let sealed = noWeather.coordinator.seal(ownerID: ownerID, start: start, installation: nil)
    #expect(sealed?.location?.placeName == "Somewhere" && sealed?.weather == nil)
  }

  @Test func storageFailureOmitsContextWithoutThrowing() async throws {
    let rig = Rig()
    rig.store.failSave = true
    rig.coordinator.begin(ownerID: ownerID, start: start, installation: nil)
    await rig.settle()
    #expect(rig.coordinator.seal(ownerID: ownerID, start: start, installation: nil) == nil)
  }
}

struct ContextStorageTests {
  @Test func workspaceStoreRoundTripsAndStaysProtectedAndExcluded() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = try LocalPrivateWorkspace(root: root)
    let id = try WorkspaceID.random()
    _ = try workspace.allocate(id: id)
    let store = WorkspaceContextEnvelopeStore(workspace: workspace)
    #expect(try store.load(ownerID: id.description) == nil)
    var envelope = try ContextEnvelope(ownerID: id.description, start: start, installation: "i")
    envelope.snapshot = ContextSnapshot(
      location: ContextPolicy.acceptLocation(
        LocationSample(
          latitude: 37.566535, longitude: 126.977969, horizontalAccuracy: 10, timestamp: start),
        start: start, now: start))
    try store.save(envelope)
    #expect(try store.load(ownerID: id.description) == envelope)
    let file = root.appending(path: id.description).appending(path: "context-v1.json")
    let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
    try store.delete(ownerID: id.description)
    #expect(try store.load(ownerID: id.description) == nil)
  }

  @Test func corruptOversizedAndHostileEnvelopesAreRejected() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = try LocalPrivateWorkspace(root: root)
    let id = try WorkspaceID.random()
    _ = try workspace.allocate(id: id)
    let store = WorkspaceContextEnvelopeStore(workspace: workspace)
    // `load` re-opens the workspace and invalidates older handles, so take a fresh one each time.
    func artifact() throws -> ArtifactHandle {
      try workspace.artifact(.context, in: try workspace.reopen(id: id))
    }
    try workspace.replace(try artifact(), with: Data("{not json".utf8))
    #expect(throws: PrivateWorkspaceFailureCode.verificationFailed) {
      try store.load(ownerID: id.description)
    }
    try workspace.replace(try artifact(), with: Data(repeating: 65, count: 40 * 1_024))
    #expect(throws: PrivateWorkspaceFailureCode.verificationFailed) {
      try store.load(ownerID: id.description)
    }
    // Out-of-range values in a well-formed file decode to omission, not a failure.
    var envelope = try ContextEnvelope(ownerID: id.description, start: start, installation: nil)
    envelope.latitude = "999"
    envelope.longitude = "1"
    envelope.accuracy = "5"
    envelope.sampledAt = "2026-01-01T00:00:00Z"
    #expect(envelope.snapshot.isEmpty)
    envelope.weatherSummary = "Totally invented"
    #expect(envelope.snapshot.weather == nil)
  }

  @Test func olderSettingsWithoutContextFieldsStillDecodeAndDefaultSafely() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let legacy =
      #"{"firstLaunch":{"step":"complete","microphoneAttempted":true,"#
      + #""locationAttempted":true}}"#
    try Data(legacy.utf8).write(to: root.appending(path: "private-settings.json"))
    let repository = await PrivateSettingsRepository(root: root)
    #expect(await repository.loadLocationContextEnabled() == nil)
    #expect(await repository.loadWeatherContextEnabled() == false)
    try await repository.saveWeatherContextEnabled(true)
    try await repository.saveLocationContextEnabled(false)
    #expect(await repository.loadWeatherContextEnabled() == true)
    #expect(await repository.loadLocationContextEnabled() == false)
  }
}

struct ManualContextCodecTests {
  @Test func manualSnippetRoundTripsLocationWeatherAndPreservesBadGroups() throws {
    let title = DiaryTitlePolicy.fallback("Hi")
    let location = try #require(
      ContextPolicy.acceptLocation(
        LocationSample(
          latitude: 37.566535, longitude: 126.977969, horizontalAccuracy: 12, timestamp: start),
        start: start, now: start))
    let weather = try #require(
      ContextPolicy.acceptWeather(
        WeatherSample(validAt: start, temperatureCelsius: 18.4, weatherCode: 3), start: start))
    let snippet = DiarySnippetV1.manual(
      id: try AssetID(ownerID), createdAt: try SchemaInstant("2026-01-02T03:04:05Z"),
      body: try DiaryBody("Hi"), title: title.text, provenance: title.provenance,
      location: location, weather: weather)
    let codec = DiarySnippetMarkdownCodec()
    let data = try codec.encode(snippet)
    guard case .supported(let decoded) = codec.decode(data) else {
      Issue.record("manual context did not decode")
      return
    }
    #expect(decoded.location == location && decoded.weather == weather)
    #expect(try codec.encode(decoded) == data)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("location_latitude: 37.566535\n"))
    // A malformed partial group is preserved verbatim, not interpreted or dropped.
    let broken = text.replacingOccurrences(of: "location_longitude: 126.977969\n", with: "")
    guard case .supported(let partial) = codec.decode(Data(broken.utf8)) else {
      Issue.record("partial group should still decode")
      return
    }
    #expect(partial.location == nil)
    #expect(partial.preservedScalars.contains { $0.key == "location_latitude" })
    // Preserved scalars are re-emitted after known fields: stable on a second round trip.
    let again = try codec.encode(partial)
    guard case .supported(let reread) = codec.decode(again) else {
      Issue.record("re-encoded partial group should decode")
      return
    }
    #expect(reread.preservedScalars.map(\.key) == partial.preservedScalars.map(\.key))
    #expect(try codec.encode(reread) == again)
  }
}

@MainActor
struct OpenMeteoRequestTests {
  @Test func requestCarriesOnlyRoundedCoordinatesAndTwoVariablesOverHTTPS() throws {
    let url = try #require(
      OpenMeteoWeatherSource.requestURL(latitude: 37.566535, longitude: 126.977969))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.scheme == "https" && components.host == "api.open-meteo.com")
    let items = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(
      items == [
        "latitude": "37.57", "longitude": "126.98", "current": "temperature_2m,weather_code",
        "timeformat": "unixtime",
      ])
    #expect(components.user == nil && components.fragment == nil)
  }

  @Test func strictParsingRejectsMalformedOversizedAndIncompleteBodies() {
    let good = Data(
      #"{"current":{"time":1800000000,"interval":900,"temperature_2m":18.5,"weather_code":3}}"#
        .utf8)
    #expect(OpenMeteoWeatherSource.parse(good)?.weatherCode == 3)
    #expect(OpenMeteoWeatherSource.parse(good)?.temperatureCelsius == 18.5)
    #expect(OpenMeteoWeatherSource.parse(Data("{}".utf8)) == nil)
    #expect(OpenMeteoWeatherSource.parse(Data("not json".utf8)) == nil)
    #expect(
      OpenMeteoWeatherSource.parse(
        Data(#"{"current":{"time":"later","temperature_2m":1,"weather_code":1}}"#.utf8)) == nil)
    #expect(
      OpenMeteoWeatherSource.parse(
        Data(#"{"current":{"time":0,"temperature_2m":1,"weather_code":1}}"#.utf8)) == nil)
    #expect(
      OpenMeteoWeatherSource.parse(Data(repeating: 32, count: 17 * 1_024) + good) == nil)
  }
}

// swiftlint:enable trailing_comma
