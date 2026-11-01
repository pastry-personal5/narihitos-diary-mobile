import Foundation

enum TrialValidationError: LocalizedError, Equatable {
  case missingModel
  case missingAudio
  case unsupportedModelExtension
  case unsupportedModelCandidate
  case modelArtifactMismatch
  case emptyAudio
  case modelIsNotCohere
  case preflightRequired
  case inputsChangedAfterPreflight
  case invalidAmbientTemperature

  var errorDescription: String? {
    switch self {
    case .missingModel: "Select a GGUF model."
    case .missingAudio: "Select an audio file."
    case .unsupportedModelExtension: "The model must be a .gguf file."
    case .unsupportedModelCandidate:
      "Select the approved Cohere Q4_K_M or Q5_K_M trial model."
    case .modelArtifactMismatch:
      "The model SHA-256 does not match the approved Git LFS artifact."
    case .emptyAudio: "The converted audio contains no samples."
    case .modelIsNotCohere: "The selected GGUF is not a Cohere model."
    case .preflightRequired: "Inspect the selected files before starting a run."
    case .inputsChangedAfterPreflight: "A selected file changed after inspection. Inspect it again."
    case .invalidAmbientTemperature:
      "Enter an ambient temperature from -50 to 60 °C, or leave it blank."
    }
  }
}

enum TrialInputValidator {
  static func validate(modelURL: URL?, audioURL: URL?) throws -> (URL, URL) {
    guard let modelURL else { throw TrialValidationError.missingModel }
    guard let audioURL else { throw TrialValidationError.missingAudio }
    guard modelURL.pathExtension.lowercased() == "gguf" else {
      throw TrialValidationError.unsupportedModelExtension
    }
    guard ModelQuantization.from(filename: modelURL.lastPathComponent) != nil else {
      throw TrialValidationError.unsupportedModelCandidate
    }
    return (modelURL, audioURL)
  }
}

enum CohereArchitecturePolicy {
  static func accepts(_ architecture: String) -> Bool {
    architecture == "cohere_asr" || architecture == "cohere"
  }
}

enum TranscriptCompletenessPolicy {
  static func outcome(statusCode: Int32, aborted: Bool, truncated: Bool) -> TrialOutcome {
    if aborted || statusCode == 13 { return .cancelled }
    if truncated || statusCode == 18 { return .outputTruncated }
    switch statusCode {
    case 0: return .success
    case 1: return .invalidInput
    case 7: return .outOfMemory
    case 17: return .inputTooLong
    default: return .runtimeFailure
    }
  }

  static func isPartial(outcome: TrialOutcome, transcript: String) -> Bool {
    !transcript.isEmpty && outcome != .success
  }
}
