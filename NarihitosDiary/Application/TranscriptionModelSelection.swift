import Foundation

enum TranscriptionModelSelection: String, Codable, CaseIterable, Identifiable, Sendable {
  case none = "none"
  case appleLocal = "apple-local"
  case cohereQ4 = "cohere-q4"
  case cohereQ5 = "cohere-q5"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: "None"
    case .appleLocal: "Apple Local"
    case .cohereQ4: "Cohere Q4"
    case .cohereQ5: "Cohere Q5"
    }
  }

  var methodID: String? {
    switch self {
    case .none: nil
    case .appleLocal: TranscriptionMethodIdentifiers.apple
    case .cohereQ4, .cohereQ5: TranscriptionMethodIdentifiers.cohere
    }
  }
}

enum StoredTranscriptionModelSelection: Equatable, Sendable {
  case value(TranscriptionModelSelection)
  case unavailable
}
