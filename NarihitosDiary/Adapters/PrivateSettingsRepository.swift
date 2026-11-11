// swiftlint:disable opening_brace
import Foundation

struct StoredDestinationRecord: Codable, Equatable, Sendable {
  let id: String
  let displayName: String
  let bookmark: Data
  let identityArchive: Data
  let disclosureAcknowledged: Bool
}

@MainActor
protocol DestinationSettingsStore: AnyObject {
  func loadDestination() -> StoredDestinationRecord?
  func saveDestination(_ destination: StoredDestinationRecord) throws
}

private struct StoredApplicationSettings: Codable {
  var firstLaunch = FirstLaunchProgress()
  var destination: StoredDestinationRecord?
  var selectedTranscriptionMethodID: String?
  var selectedTranscriptionModel: String? = .none
  // Optional so settings written before M18b still decode; nil means "not chosen".
  var locationContextEnabled: Bool?
  var weatherContextEnabled: Bool?
}

@MainActor
final class PrivateSettingsRepository: FirstLaunchStorePort, DestinationSettingsStore,
  ContextPreferenceStore
{
  private static let maximumFileSize = 128 * 1_024
  private let fileManager: FileManager
  private let fileURL: URL

  init(fileManager: FileManager = .default, root: URL? = nil) {
    self.fileManager = fileManager
    let base =
      root
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("NarihitosDiary", isDirectory: true)
    fileURL = base.appendingPathComponent("private-settings.json", isDirectory: false)
  }

  func loadFirstLaunchProgress() -> FirstLaunchProgress {
    (try? read())?.firstLaunch ?? FirstLaunchProgress()
  }

  func saveFirstLaunchProgress(_ progress: FirstLaunchProgress) throws {
    var proposed = try read()
    proposed.firstLaunch = progress
    try persist(proposed)
  }

  func loadDestination() -> StoredDestinationRecord? {
    (try? read())?.destination
  }

  func saveDestination(_ destination: StoredDestinationRecord) throws {
    var proposed = try read()
    proposed.destination = destination
    try persist(proposed)
  }

  func selectedTranscriptionMethodID() -> String? {
    switch loadTranscriptionModelSelection() {
    case .value(let selection): selection.methodID
    case .unavailable: nil
    }
  }

  func selectTranscriptionMethod(_ id: String) throws {
    guard !id.isEmpty, id.utf8.count <= 128,
      id.utf8.allSatisfy({
        (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
      })
    else { throw QueueStoreFailure.corrupt }
    var proposed = try read()
    proposed.selectedTranscriptionMethodID = id
    try persist(proposed)
  }

  func loadTranscriptionModelSelection() -> StoredTranscriptionModelSelection {
    do {
      let settings = try read()
      if let raw = settings.selectedTranscriptionModel {
        guard let selection = TranscriptionModelSelection(rawValue: raw) else {
          return .unavailable
        }
        return .value(selection)
      }
      switch settings.selectedTranscriptionMethodID {
      case TranscriptionMethodIdentifiers.apple: return .value(.appleLocal)
      case TranscriptionMethodIdentifiers.cohere: return .value(.cohereQ4)
      case nil: return .value(.none)
      default: return .unavailable
      }
    } catch {
      return .unavailable
    }
  }

  func selectTranscriptionModel(_ selection: TranscriptionModelSelection) throws {
    var proposed = try read()
    proposed.selectedTranscriptionModel = selection.rawValue
    proposed.selectedTranscriptionMethodID = nil
    try persist(proposed)
  }

  /// nil inherits permission-based opt-in; an explicit Off stays Off.
  func loadLocationContextEnabled() -> Bool? { (try? read())?.locationContextEnabled }

  /// Weather is Off until the user turns it on.
  func loadWeatherContextEnabled() -> Bool { (try? read())?.weatherContextEnabled ?? false }

  func saveLocationContextEnabled(_ value: Bool) throws {
    var proposed = try read()
    proposed.locationContextEnabled = value
    try persist(proposed)
  }

  func saveWeatherContextEnabled(_ value: Bool) throws {
    var proposed = try read()
    proposed.weatherContextEnabled = value
    try persist(proposed)
  }

  private func read() throws -> StoredApplicationSettings {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: fileURL)
    } catch let error as CocoaError {
      guard error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile else { throw error }
      return StoredApplicationSettings()
    }
    defer { try? handle.close() }
    // A temporary protected-data/read failure must remain retryable. In particular,
    // a later write must not replace existing settings with cached empty defaults.
    let data = try handle.read(upToCount: Self.maximumFileSize + 1) ?? Data()
    guard data.count <= Self.maximumFileSize else { throw CocoaError(.fileReadTooLarge) }
    return try JSONDecoder().decode(StoredApplicationSettings.self, from: data)
  }

  private func persist(_ value: StoredApplicationSettings) throws {
    let data = try JSONEncoder().encode(value)
    guard data.count <= Self.maximumFileSize else {
      throw CocoaError(.fileWriteOutOfSpace)
    }
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
  }
}

// swiftlint:enable opening_brace
