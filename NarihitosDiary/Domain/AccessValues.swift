import Foundation

enum PermissionState: String, Codable, Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

struct DestinationID: Codable, Equatable, Hashable, Sendable {
  let rawValue: String

  init?(rawValue: String) {
    guard
      let uuid = UUID(uuidString: rawValue),
      uuid.uuidString.lowercased() == rawValue
    else { return nil }
    self.rawValue = rawValue
  }

  static func make() -> DestinationID {
    DestinationID(rawValue: UUID().uuidString.lowercased())!
  }
}

struct DestinationSummary: Equatable, Sendable {
  let id: DestinationID
  let displayName: String
}

enum DestinationAccessState: String, Equatable, Sendable {
  case accessible
  case temporarilyUnavailable
  case restoreAccessRequired
  case invalidStoredReference
}

struct ActiveDestination: Equatable, Sendable {
  let summary: DestinationSummary?
  let accessState: DestinationAccessState
}

struct RecordPrerequisites: Equatable, Sendable {
  let microphone: PermissionState
  let destination: ActiveDestination

  var allowsCapture: Bool {
    microphone == .authorized && destination.summary != nil
      && destination.accessState == .accessible
  }
}

enum SafeFolderDisplayName {
  static let maximumLength = 80
  static let fallback = "Selected Folder"

  static func project(_ source: String) -> String {
    let unsafeDirectionals: Set<UInt32> =
      Set([0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C])
      .union([0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069])
    let sanitizedScalars = source.unicodeScalars.map { scalar -> Character in
      let isUnsafe =
        CharacterSet.controlCharacters.contains(scalar)
        || unsafeDirectionals.contains(scalar.value)
      if isUnsafe {
        return " "
      }
      return Character(String(scalar))
    }
    let collapsed = String(sanitizedScalars)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
    guard !collapsed.isEmpty else { return fallback }
    return String(collapsed.prefix(maximumLength))
  }
}
