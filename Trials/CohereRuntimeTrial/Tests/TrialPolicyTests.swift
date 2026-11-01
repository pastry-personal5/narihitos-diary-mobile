import Foundation
import Testing
@testable import CohereRuntimeTrial

struct TrialPolicyTests {
  @Test
  func completeSuccessIsTheOnlyScoreableOutcome() {
    #expect(
      TranscriptCompletenessPolicy.outcome(statusCode: 0, aborted: false, truncated: false)
        == .success
    )
    #expect(
      TranscriptCompletenessPolicy.outcome(statusCode: 0, aborted: false, truncated: true)
        == .outputTruncated
    )
    #expect(
      TranscriptCompletenessPolicy.outcome(statusCode: 0, aborted: true, truncated: false)
        == .cancelled
    )
  }

  @Test
  func runtimeFailuresKeepTheirStableMeaning() {
    #expect(
      TranscriptCompletenessPolicy.outcome(statusCode: 7, aborted: false, truncated: false)
        == .outOfMemory
    )
    #expect(
      TranscriptCompletenessPolicy.outcome(statusCode: 17, aborted: false, truncated: false)
        == .inputTooLong
    )
    #expect(
      TranscriptCompletenessPolicy.outcome(statusCode: 18, aborted: false, truncated: false)
        == .outputTruncated
    )
  }

  @Test
  func inputValidationRequiresBothFilesAndGGUFModel() throws {
    let audio = URL(fileURLWithPath: "/tmp/audio.m4a")
    #expect(throws: TrialValidationError.missingModel) {
      try TrialInputValidator.validate(modelURL: nil, audioURL: audio)
    }
    #expect(throws: TrialValidationError.missingAudio) {
      try TrialInputValidator.validate(
        modelURL: URL(fileURLWithPath: "/tmp/model-Q4_K_M.gguf"),
        audioURL: nil
      )
    }
    #expect(throws: TrialValidationError.unsupportedModelExtension) {
      try TrialInputValidator.validate(
        modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
        audioURL: audio
      )
    }
    #expect(throws: TrialValidationError.unsupportedModelCandidate) {
      try TrialInputValidator.validate(
        modelURL: URL(fileURLWithPath: "/tmp/other-model.gguf"),
        audioURL: audio
      )
    }
  }

  @Test
  func quantizationComesFromTheCandidateFilename() {
    #expect(ModelQuantization.from(filename: "cohere-Q4_K_M.gguf") == .q4KM)
    #expect(ModelQuantization.from(filename: "cohere-q5_k_m.gguf") == .q5KM)
    #expect(ModelQuantization.from(filename: "cohere-Q8_0.gguf") == nil)
    #expect(ModelQuantization.q4KM.expectedSHA256.count == 64)
    #expect(ModelQuantization.q5KM.expectedSHA256.count == 64)
    #expect(ModelQuantization.q4KM.expectedSHA256 != ModelQuantization.q5KM.expectedSHA256)
  }

  @Test
  func acceptsCanonicalAndLegacyCohereArchitectureNames() {
    #expect(CohereArchitecturePolicy.accepts("cohere_asr"))
    #expect(CohereArchitecturePolicy.accepts("cohere"))
    #expect(!CohereArchitecturePolicy.accepts("whisper"))
  }
}
