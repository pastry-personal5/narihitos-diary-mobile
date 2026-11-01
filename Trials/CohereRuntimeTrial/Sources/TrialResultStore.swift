import Foundation

struct TrialResultStore {
  private let fileManager = FileManager.default

  func save(_ result: TrialResult) throws -> URL {
    let directory = try resultsDirectory()
    let url = directory.appendingPathComponent("\(result.id.uuidString).json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    return url
  }

  func resultURLs() throws -> [URL] {
    let directory = try resultsDirectory()
    return try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.creationDateKey],
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
  }

  func deleteAll() throws {
    for url in try resultURLs() {
      try fileManager.removeItem(at: url)
    }
  }

  private func resultsDirectory() throws -> URL {
    let documents = try fileManager.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = documents.appendingPathComponent("TrialResults", isDirectory: true)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete]
    )
    return directory
  }
}
