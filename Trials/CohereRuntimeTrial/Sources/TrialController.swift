import Foundation
import Observation
import UIKit

private struct TrialExecution: Sendable {
  let model: ModelIdentity
  let audio: AudioIdentity
  let runtime: RuntimeResult
  let resources: [ResourceSample]
  let preflightInspectionSeconds: Double
  let inputVerificationSeconds: Double
  let conversionSeconds: Double
  let totalSeconds: Double
}

private struct TrialResultContext {
  let startedAt: Date
  let endedAt: Date
  let runClass: TrialRunClass
  let language: TrialLanguage
  let initialBattery: BatteryObservation
  let finalBattery: BatteryObservation
  let conditions: TrialConditions
}

private struct TrialRunRequest: Sendable {
  let modelURL: URL
  let audioURL: URL
  let language: TrialLanguage
  let runClass: TrialRunClass
  let expectedInputs: TrialInputSummary
  let conditions: TrialConditions
}

private enum TrialExecutor {
  static func execute(
    modelURL: URL,
    audioURL: URL,
    language: TrialLanguage,
    cancellation: CancellationFlag,
    expectedInputs: TrialInputSummary
  ) throws -> TrialExecution {
    let totalStarted = ProcessInfo.processInfo.systemUptime
    let sampler = ResourceSampler()
    sampler.start()
    var didStopSampler = false
    defer {
      if !didStopSampler {
        _ = sampler.stop()
      }
    }

    sampler.setPhase(.inputVerification)
    let verificationStarted = ProcessInfo.processInfo.systemUptime
    try TrialPreflight.verifyUnchanged(
      summary: expectedInputs,
      modelURL: modelURL,
      audioURL: audioURL,
      cancellation: cancellation
    )
    let inputVerificationSeconds = ProcessInfo.processInfo.systemUptime - verificationStarted

    sampler.setPhase(.audioConversion)
    let conversionStarted = ProcessInfo.processInfo.systemUptime
    let decodedAudio = try AudioDecoder.decode(url: audioURL, cancellation: cancellation)
    let conversionSeconds = ProcessInfo.processInfo.systemUptime - conversionStarted

    let runtime = try CohereRuntime.transcribe(
      modelURL: modelURL,
      samples: decodedAudio.samples,
      language: language,
      cancellation: cancellation,
      phaseChanged: { sampler.setPhase($0) }
    )
    sampler.setPhase(.settled)
    let resources = sampler.stop()
    didStopSampler = true

    return TrialExecution(
      model: expectedInputs.model,
      audio: AudioIdentity(
        file: expectedInputs.audioFile,
        sourceDurationSeconds: decodedAudio.sourceDurationSeconds,
        convertedSampleCount: decodedAudio.samples.count
      ),
      runtime: runtime,
      resources: resources,
      preflightInspectionSeconds: expectedInputs.inspectionSeconds,
      inputVerificationSeconds: inputVerificationSeconds,
      conversionSeconds: conversionSeconds,
      totalSeconds: ProcessInfo.processInfo.systemUptime - totalStarted
    )
  }
}

@MainActor
@Observable
final class TrialController {
  var selectedModelURL: URL?
  var selectedAudioURL: URL?
  var language = TrialLanguage.english
  var runClass = TrialRunClass.coldLaunch
  var networkCondition = TrialNetworkCondition.unknown
  var ambientTemperatureCelsius = ""
  private(set) var inputSummary: TrialInputSummary?
  private(set) var isInspecting = false
  private(set) var status = "Ready"
  private(set) var isRunning = false
  private(set) var isCancelling = false
  private(set) var lastResult: TrialResult?
  private(set) var lastResultURL: URL?
  private(set) var savedResultURLs: [URL] = []
  var errorMessage: String?

  private let store = TrialResultStore()
  private var cancellation: CancellationFlag?

  init() {
    refreshResults()
  }

  func selectModel(_ url: URL?) {
    selectedModelURL = url
    inputSummary = nil
    status = "Inspect the selected files"
  }

  func selectAudio(_ url: URL?) {
    selectedAudioURL = url
    inputSummary = nil
    status = "Inspect the selected files"
  }

  func inspectInputs() {
    guard !isRunning, !isInspecting else { return }
    do {
      let (modelURL, audioURL) = try TrialInputValidator.validate(
        modelURL: selectedModelURL,
        audioURL: selectedAudioURL
      )
      isInspecting = true
      errorMessage = nil
      status = "Inspecting hashes and duration…"
      Task {
        await performInspection(modelURL: modelURL, audioURL: audioURL)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func run() {
    guard !isRunning, !isInspecting else { return }
    do {
      let (modelURL, audioURL) = try TrialInputValidator.validate(
        modelURL: selectedModelURL,
        audioURL: selectedAudioURL
      )
      guard let inputSummary else { throw TrialValidationError.preflightRequired }
      let request = TrialRunRequest(
        modelURL: modelURL,
        audioURL: audioURL,
        language: language,
        runClass: runClass,
        expectedInputs: inputSummary,
        conditions: try currentConditions()
      )
      let cancellation = CancellationFlag()
      self.cancellation = cancellation
      isRunning = true
      isCancelling = false
      errorMessage = nil
      status = "Preparing files…"

      Task {
        await performRun(request: request, cancellation: cancellation)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func cancel() {
    guard isRunning, !isCancelling else { return }
    isCancelling = true
    status = "Cancelling…"
    cancellation?.cancel()
  }

  func deleteAllResults() {
    do {
      try store.deleteAll()
      lastResult = nil
      lastResultURL = nil
      refreshResults()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func refreshResults() {
    do {
      savedResultURLs = try store.resultURLs()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func performRun(
    request: TrialRunRequest,
    cancellation: CancellationFlag
  ) async {
    let modelAccess = request.modelURL.startAccessingSecurityScopedResource()
    let audioAccess = request.audioURL.startAccessingSecurityScopedResource()
    defer {
      if modelAccess { request.modelURL.stopAccessingSecurityScopedResource() }
      if audioAccess { request.audioURL.stopAccessingSecurityScopedResource() }
      self.cancellation = nil
      isRunning = false
      isCancelling = false
    }

    let startedAt = Date()
    let initialBattery = SystemMeasurements.batteryObservation()
    status = "Verifying, converting, and transcribing…"

    do {
      let execution = try await Task.detached(priority: .userInitiated) {
        try TrialExecutor.execute(
          modelURL: request.modelURL,
          audioURL: request.audioURL,
          language: request.language,
          cancellation: cancellation,
          expectedInputs: request.expectedInputs
        )
      }.value
      let endedAt = Date()
      let finalBattery = SystemMeasurements.batteryObservation()
      let result = TrialResultFactory.make(
        context: TrialResultContext(
          startedAt: startedAt,
          endedAt: endedAt,
          runClass: request.runClass,
          language: request.language,
          initialBattery: initialBattery,
          finalBattery: finalBattery,
          conditions: request.conditions
        ),
        execution: execution
      )
      lastResult = result
      lastResultURL = try store.save(result)
      refreshResults()
      status =
        "Settled: \(execution.runtime.outcome.rawValue) — "
        + "\(execution.runtime.status) (\(execution.runtime.statusCode))"
    } catch {
      errorMessage = error.localizedDescription
      status = "Failed before a result could be saved"
    }
  }

  private func performInspection(modelURL: URL, audioURL: URL) async {
    let modelAccess = modelURL.startAccessingSecurityScopedResource()
    let audioAccess = audioURL.startAccessingSecurityScopedResource()
    defer {
      if modelAccess { modelURL.stopAccessingSecurityScopedResource() }
      if audioAccess { audioURL.stopAccessingSecurityScopedResource() }
      isInspecting = false
    }
    do {
      inputSummary = try await Task.detached(priority: .userInitiated) {
        try TrialPreflight.inspect(modelURL: modelURL, audioURL: audioURL)
      }.value
      status = "Inputs inspected — ready"
    } catch {
      inputSummary = nil
      errorMessage = error.localizedDescription
      status = "Input inspection failed"
    }
  }

  private func currentConditions() throws -> TrialConditions {
    let trimmedTemperature = ambientTemperatureCelsius.trimmingCharacters(in: .whitespaces)
    let temperature: Double?
    if trimmedTemperature.isEmpty {
      temperature = nil
    } else {
      guard let value = Double(trimmedTemperature), (-50...60).contains(value) else {
        throw TrialValidationError.invalidAmbientTemperature
      }
      temperature = value
    }
    return TrialConditions(
      screenBrightness: activeScreenBrightness(),
      network: networkCondition,
      ambientTemperatureCelsius: temperature
    )
  }

  private func activeScreenBrightness() -> Double {
    let screen = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.screen }
      .first
    return Double(screen?.brightness ?? 0)
  }
}

private enum TrialResultFactory {
  static func make(
    context: TrialResultContext,
    execution: TrialExecution
  ) -> TrialResult {
    let runtime = execution.runtime
    return TrialResult(
      schemaVersion: TrialResult.currentSchemaVersion,
      id: UUID(),
      startedAt: context.startedAt,
      endedAt: context.endedAt,
      trialBuildRevision: buildValue(key: "TrialBuildRevision"),
      runClass: context.runClass,
      language: context.language,
      model: execution.model,
      audio: execution.audio,
      device: makeDeviceIdentity(runtime: runtime),
      conditions: context.conditions,
      runtimeCapabilities: runtime.capabilities,
      outcome: runtime.outcome,
      runtimeStatusCode: runtime.statusCode,
      runtimeStatus: runtime.status,
      runtimeDiagnostics: runtime.diagnostics,
      transcript: runtime.transcript,
      partialTranscript: runtime.partialTranscript,
      truncated: runtime.truncated,
      durations: makeDurations(execution: execution),
      resources: execution.resources,
      initialBattery: context.initialBattery,
      finalBattery: context.finalBattery
    )
  }

  private static func makeDeviceIdentity(runtime: RuntimeResult) -> DeviceIdentity {
    DeviceIdentity(
      modelIdentifier: SystemMeasurements.modelIdentifier(),
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      runtimeVersion: runtime.runtimeVersion,
      runtimeCommit: runtime.runtimeCommit,
      runtimeArtifactSHA256: buildValue(key: "TranscribeArtifactSHA256"),
      requestedBackend: "metal",
      actualBackend: runtime.actualBackend
    )
  }

  private static func makeDurations(execution: TrialExecution) -> StageDurations {
    let runtime = execution.runtime
    return StageDurations(
      preflightInspectionSeconds: execution.preflightInspectionSeconds,
      inputVerificationSeconds: execution.inputVerificationSeconds,
      conversionSeconds: execution.conversionSeconds,
      modelLoadSeconds: runtime.loadSeconds,
      inferenceSeconds: runtime.inferenceSeconds,
      totalSeconds: execution.totalSeconds,
      runtimeMelMilliseconds: runtime.melMilliseconds,
      runtimeEncodeMilliseconds: runtime.encodeMilliseconds,
      runtimeDecodeMilliseconds: runtime.decodeMilliseconds
    )
  }

  private static func buildValue(key: String) -> String {
    Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
  }
}
