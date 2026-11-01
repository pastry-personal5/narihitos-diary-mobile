import Foundation

enum TrialLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
  case english = "en"
  case korean = "ko"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .english: "English (en)"
    case .korean: "Korean (ko)"
    }
  }
}

enum TrialRunClass: String, CaseIterable, Codable, Identifiable, Sendable {
  case coldLaunch
  case warmReload
  case backToBack
  case cancellationProbe

  var id: String { rawValue }

  var label: String {
    switch self {
    case .coldLaunch: "Cold launch"
    case .warmReload: "Warm reload"
    case .backToBack: "Back to back"
    case .cancellationProbe: "Cancellation probe"
    }
  }
}

enum ModelQuantization: String, CaseIterable, Codable, Sendable {
  case q4KM = "Q4_K_M"
  case q5KM = "Q5_K_M"

  static func from(filename: String) -> ModelQuantization? {
    allCases.first { filename.uppercased().contains($0.rawValue) }
  }

  var expectedSHA256: String {
    switch self {
    case .q4KM: "0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb"
    case .q5KM: "14d02f1ad6dd77b3a60f82639879012c3adb4fe25c50a5a47a2c4c661daf1558"
    }
  }
}

enum MeasurementPhase: String, Codable, Sendable {
  case inputVerification
  case audioConversion
  case modelLoad
  case inference
  case settled
}

enum TrialNetworkCondition: String, CaseIterable, Codable, Identifiable, Sendable {
  case offline
  case wifi
  case cellular
  case unknown

  var id: String { rawValue }

  var label: String { rawValue.capitalized }
}

enum TrialOutcome: String, Codable, Sendable {
  case success
  case cancelled
  case inputTooLong
  case outputTruncated
  case outOfMemory
  case invalidInput
  case runtimeFailure
}

struct FileIdentity: Codable, Equatable, Sendable {
  let filename: String
  let byteCount: Int64
  let sha256: String
  let modifiedAt: Date?
}

struct ModelIdentity: Codable, Equatable, Sendable {
  let file: FileIdentity
  let quantization: ModelQuantization
}

struct TrialInputSummary: Equatable, Sendable {
  let model: ModelIdentity
  let audioFile: FileIdentity
  let audioDurationSeconds: Double
  let inspectionSeconds: Double
}

struct AudioIdentity: Codable, Equatable, Sendable {
  let file: FileIdentity
  let sourceDurationSeconds: Double
  let convertedSampleCount: Int
}

struct DeviceIdentity: Codable, Equatable, Sendable {
  let modelIdentifier: String
  let operatingSystem: String
  let runtimeVersion: String
  let runtimeCommit: String
  let runtimeArtifactSHA256: String
  let requestedBackend: String
  let actualBackend: String
}

struct TrialConditions: Codable, Equatable, Sendable {
  let screenBrightness: Double
  let network: TrialNetworkCondition
  let ambientTemperatureCelsius: Double?
}

struct RuntimeCapabilities: Codable, Equatable, Sendable {
  let maxAudioMilliseconds: Int64
  let supportsCancellation: Bool
}

struct StageDurations: Codable, Equatable, Sendable {
  let preflightInspectionSeconds: Double
  let inputVerificationSeconds: Double
  let conversionSeconds: Double
  let modelLoadSeconds: Double
  let inferenceSeconds: Double
  let totalSeconds: Double
  let runtimeMelMilliseconds: Double
  let runtimeEncodeMilliseconds: Double
  let runtimeDecodeMilliseconds: Double
}

struct ResourceSample: Codable, Equatable, Sendable {
  let elapsedSeconds: Double
  let phase: MeasurementPhase
  let availableProcessMemoryBytes: UInt64
  let physicalFootprintBytes: UInt64
  let thermalState: String
}

struct BatteryObservation: Codable, Equatable, Sendable {
  let level: Double?
  let state: String
  let lowPowerMode: Bool
}

struct TrialResult: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 3

  let schemaVersion: Int
  let id: UUID
  let startedAt: Date
  let endedAt: Date
  let trialBuildRevision: String
  let runClass: TrialRunClass
  let language: TrialLanguage
  let model: ModelIdentity
  let audio: AudioIdentity
  let device: DeviceIdentity
  let conditions: TrialConditions
  let runtimeCapabilities: RuntimeCapabilities
  let outcome: TrialOutcome
  let runtimeStatusCode: Int32?
  let runtimeStatus: String?
  let runtimeDiagnostics: [String]
  let transcript: String
  let partialTranscript: Bool
  let truncated: Bool
  let durations: StageDurations
  let resources: [ResourceSample]
  let initialBattery: BatteryObservation
  let finalBattery: BatteryObservation
}

struct RuntimeResult: Sendable {
  let outcome: TrialOutcome
  let statusCode: Int32
  let status: String
  let diagnostics: [String]
  let transcript: String
  let partialTranscript: Bool
  let truncated: Bool
  let runtimeVersion: String
  let runtimeCommit: String
  let actualBackend: String
  let capabilities: RuntimeCapabilities
  let loadSeconds: Double
  let inferenceSeconds: Double
  let melMilliseconds: Double
  let encodeMilliseconds: Double
  let decodeMilliseconds: Double
}
