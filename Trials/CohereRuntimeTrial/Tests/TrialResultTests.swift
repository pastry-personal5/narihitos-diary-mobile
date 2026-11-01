import Foundation
import Testing
@testable import CohereRuntimeTrial

struct TrialResultTests {
  @Test
  func resultRoundTripsThroughJSON() throws {
    let result = sampleResult()
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(TrialResult.self, from: data)
    #expect(decoded == result)
  }

  private func sampleResult() -> TrialResult {
    let file = FileIdentity(
      filename: "sample",
      byteCount: 42,
      sha256: "abc",
      modifiedAt: Date(timeIntervalSince1970: 0)
    )
    let battery = BatteryObservation(level: 0.5, state: "unplugged", lowPowerMode: false)
    return TrialResult(
      schemaVersion: TrialResult.currentSchemaVersion,
      id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      startedAt: Date(timeIntervalSince1970: 1),
      endedAt: Date(timeIntervalSince1970: 2),
      trialBuildRevision: "test",
      runClass: .coldLaunch,
      language: .english,
      model: ModelIdentity(file: file, quantization: .q4KM),
      audio: AudioIdentity(file: file, sourceDurationSeconds: 30, convertedSampleCount: 480_000),
      device: sampleDevice(),
      conditions: TrialConditions(
        screenBrightness: 0.5,
        network: .offline,
        ambientTemperatureCelsius: 22
      ),
      runtimeCapabilities: RuntimeCapabilities(
        maxAudioMilliseconds: 400_000,
        supportsCancellation: true
      ),
      outcome: .success,
      runtimeStatusCode: 0,
      runtimeStatus: "ok",
      runtimeDiagnostics: ["run: ok (0)"],
      transcript: "hello",
      partialTranscript: false,
      truncated: false,
      durations: sampleDurations(),
      resources: [
        ResourceSample(
          elapsedSeconds: 0,
          phase: .inference,
          availableProcessMemoryBytes: 1,
          physicalFootprintBytes: 2,
          thermalState: "nominal"
        )
      ],
      initialBattery: battery,
      finalBattery: battery
    )
  }

  private func sampleDevice() -> DeviceIdentity {
    DeviceIdentity(
      modelIdentifier: "iPhone",
      operatingSystem: "iOS",
      runtimeVersion: "0.2.4",
      runtimeCommit: "4807eda",
      runtimeArtifactSHA256: "def",
      requestedBackend: "metal",
      actualBackend: "metal"
    )
  }

  private func sampleDurations() -> StageDurations {
    StageDurations(
      preflightInspectionSeconds: 1,
      inputVerificationSeconds: 0.1,
      conversionSeconds: 1,
      modelLoadSeconds: 1,
      inferenceSeconds: 1,
      totalSeconds: 4,
      runtimeMelMilliseconds: 1,
      runtimeEncodeMilliseconds: 2,
      runtimeDecodeMilliseconds: 3
    )
  }
}
