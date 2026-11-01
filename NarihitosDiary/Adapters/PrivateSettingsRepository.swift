import Foundation

struct StoredDestinationRecord: Codable, Equatable {
  let id: String
  let displayName: String
  let bookmark: Data
  let identityArchive: Data
  let disclosureAcknowledged: Bool
}

private struct StoredApplicationSettings: Codable {
  var firstLaunch = FirstLaunchProgress()
  var destination: StoredDestinationRecord?
}

@MainActor
final class PrivateSettingsRepository: FirstLaunchStorePort {
  private static let maximumFileSize = 128 * 1_024
  private let fileURL: URL
  private var settings: StoredApplicationSettings

  init(fileManager: FileManager = .default, root: URL? = nil) {
    let base =
      root
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("NarihitosDiary", isDirectory: true)
    try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    fileURL = base.appendingPathComponent("private-settings.json", isDirectory: false)
    settings = Self.read(from: fileURL)
  }

  func loadFirstLaunchProgress() -> FirstLaunchProgress {
    settings.firstLaunch
  }

  func saveFirstLaunchProgress(_ progress: FirstLaunchProgress) throws {
    var proposed = settings
    proposed.firstLaunch = progress
    try persist(proposed)
    settings = proposed
  }

  func loadDestination() -> StoredDestinationRecord? {
    settings.destination
  }

  func saveDestination(_ destination: StoredDestinationRecord) throws {
    var proposed = settings
    proposed.destination = destination
    try persist(proposed)
    settings = proposed
  }

  private static func read(from url: URL) -> StoredApplicationSettings {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber,
      size.intValue <= maximumFileSize,
      let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
      let decoded = try? JSONDecoder().decode(StoredApplicationSettings.self, from: data)
    else { return StoredApplicationSettings() }
    return decoded
  }

  private func persist(_ value: StoredApplicationSettings) throws {
    let data = try JSONEncoder().encode(value)
    guard data.count <= Self.maximumFileSize else {
      throw CocoaError(.fileWriteOutOfSpace)
    }
    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
  }
}
