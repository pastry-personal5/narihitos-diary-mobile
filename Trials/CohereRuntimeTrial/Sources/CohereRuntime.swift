import CTranscribe
import Foundation

final class CancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  func isCancelled() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

private struct RuntimeRequest {
  let samples: [Float]
  let language: TrialLanguage
  let cancellation: CancellationFlag
  let phaseChanged: @Sendable (MeasurementPhase) -> Void
}

private struct PreparedRuntimeContext {
  let actualBackend: String
  let capabilities: RuntimeCapabilities
  let diagnostics: [String]
  let loadSeconds: Double
}

private struct RuntimeRunCapture {
  let status: transcribe_status
  let inferenceSeconds: Double
  let transcript: String
  let aborted: Bool
  let truncated: Bool
  let timings: transcribe_timings
}

enum CohereRuntime {
  private struct LoadedModel {
    let status: transcribe_status
    let pointer: OpaquePointer?
    let loadSeconds: Double
  }

  private static let abortCallback: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { pointer in
    guard let pointer else { return false }
    return Unmanaged<CancellationFlag>.fromOpaque(pointer).takeUnretainedValue().isCancelled()
  }

  static func transcribe(
    modelURL: URL,
    samples: [Float],
    language: TrialLanguage,
    cancellation: CancellationFlag,
    phaseChanged: @escaping @Sendable (MeasurementPhase) -> Void
  ) throws -> RuntimeResult {
    phaseChanged(.modelLoad)
    var diagnostics = RuntimeDiagnostics.runtimeIdentity()
    let backendStatus = transcribe_init_backends_default()
    diagnostics.append(RuntimeDiagnostics.status(stage: "backend initialization", backendStatus))
    diagnostics.append(contentsOf: RuntimeDiagnostics.devices())
    guard backendStatus == TRANSCRIBE_OK else {
      return RuntimeResultBuilder.failure(
        status: backendStatus,
        diagnostics: diagnostics,
        loadSeconds: 0
      )
    }
    let request = RuntimeRequest(
      samples: samples,
      language: language,
      cancellation: cancellation,
      phaseChanged: phaseChanged
    )
    return transcribeWithInitializedBackend(
      modelURL: modelURL,
      request: request,
      diagnostics: diagnostics
    )
  }

  private static func transcribeWithInitializedBackend(
    modelURL: URL,
    request: RuntimeRequest,
    diagnostics initialDiagnostics: [String]
  ) -> RuntimeResult {
    var diagnostics = initialDiagnostics
    let loadedModel = loadModel(at: modelURL)
    diagnostics.append(RuntimeDiagnostics.status(stage: "model load", loadedModel.status))
    diagnostics.append(
      "model load seconds: \(loadedModel.loadSeconds.formatted(.number.precision(.fractionLength(3))))"
    )
    guard loadedModel.status == TRANSCRIBE_OK, let model = loadedModel.pointer else {
      return RuntimeResultBuilder.failure(
        status: loadedModel.status,
        diagnostics: diagnostics,
        loadSeconds: loadedModel.loadSeconds
      )
    }
    defer { transcribe_model_free(model) }
    diagnostics.append(contentsOf: RuntimeDiagnostics.model(model))
    let architecture = string(transcribe_model_arch_string(model))
    guard CohereArchitecturePolicy.accepts(architecture) else {
      return RuntimeResultBuilder.failure(
        status: TRANSCRIBE_ERR_UNSUPPORTED_ARCH,
        diagnostics: diagnostics,
        loadSeconds: loadedModel.loadSeconds
      )
    }
    return transcribeLoadedModel(
      model: model,
      request: request,
      loadSeconds: loadedModel.loadSeconds,
      diagnostics: diagnostics
    )
  }

  private static func transcribeLoadedModel(
    model: OpaquePointer,
    request: RuntimeRequest,
    loadSeconds: Double,
    diagnostics initialDiagnostics: [String]
  ) -> RuntimeResult {
    var diagnostics = initialDiagnostics
    let actualBackend = string(transcribe_model_backend(model))
    let (capabilities, capabilitiesStatus) = readCapabilities(model: model)
    diagnostics.append(RuntimeDiagnostics.status(stage: "capabilities", capabilitiesStatus))
    diagnostics.append(
      "capabilities: max audio \(capabilities.maxAudioMilliseconds) ms; cancellation "
        + "\(capabilities.supportsCancellation)"
    )
    let (sessionStatus, sessionPointer) = makeSession(model: model)
    diagnostics.append(RuntimeDiagnostics.status(stage: "session initialization", sessionStatus))
    guard sessionStatus == TRANSCRIBE_OK, let session = sessionPointer else {
      return RuntimeResultBuilder.failure(
        status: sessionStatus,
        actualBackend: actualBackend,
        capabilities: capabilities,
        diagnostics: diagnostics,
        loadSeconds: loadSeconds
      )
    }
    defer { transcribe_session_free(session) }
    let context = PreparedRuntimeContext(
      actualBackend: actualBackend,
      capabilities: capabilities,
      diagnostics: diagnostics,
      loadSeconds: loadSeconds
    )
    return runPreparedSession(
      session: session,
      request: request,
      context: context
    )
  }

  private static func runPreparedSession(
    session: OpaquePointer,
    request: RuntimeRequest,
    context: PreparedRuntimeContext
  ) -> RuntimeResult {
    var diagnostics = context.diagnostics
    request.phaseChanged(.inference)
    let capture = run(
      session: session,
      samples: request.samples,
      language: request.language,
      cancellation: request.cancellation
    )
    diagnostics.append(
      "run input: \(request.samples.count) mono Float32 samples at 16000 Hz; language "
        + request.language.rawValue
    )
    diagnostics.append(RuntimeDiagnostics.status(stage: "inference", capture.status))
    diagnostics.append(
      "run flags: aborted \(capture.aborted); truncated \(capture.truncated); transcript bytes "
        + "\(capture.transcript.utf8.count)"
    )
    return RuntimeResultBuilder.success(
      capture: capture,
      actualBackend: context.actualBackend,
      capabilities: context.capabilities,
      diagnostics: diagnostics,
      loadSeconds: context.loadSeconds
    )
  }

  private static func loadModel(at url: URL) -> LoadedModel {
    let started = ProcessInfo.processInfo.systemUptime
    var params = transcribe_model_load_params()
    transcribe_model_load_params_init(&params)
    params.backend = TRANSCRIBE_BACKEND_METAL
    var model: OpaquePointer?
    let status = url.path.withCString { path in
      transcribe_model_load_file(path, &params, &model)
    }
    return LoadedModel(
      status: status,
      pointer: model,
      loadSeconds: ProcessInfo.processInfo.systemUptime - started
    )
  }

  private static func makeSession(
    model: OpaquePointer
  ) -> (transcribe_status, OpaquePointer?) {
    var params = transcribe_session_params()
    transcribe_session_params_init(&params)
    var session: OpaquePointer?
    let status = transcribe_session_init(model, &params, &session)
    return (status, session)
  }

  private static func run(
    session: OpaquePointer,
    samples: [Float],
    language: TrialLanguage,
    cancellation: CancellationFlag
  ) -> RuntimeRunCapture {
    let cancellationPointer = Unmanaged.passUnretained(cancellation).toOpaque()
    transcribe_set_abort_callback(session, abortCallback, cancellationPointer)
    var params = transcribe_run_params()
    transcribe_run_params_init(&params)
    params.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
    let started = ProcessInfo.processInfo.systemUptime
    let status = language.rawValue.withCString { code in
      params.language = code
      return samples.withUnsafeBufferPointer { buffer in
        transcribe_run(session, buffer.baseAddress, Int32(buffer.count), &params)
      }
    }
    var timings = transcribe_timings()
    transcribe_timings_init(&timings)
    _ = transcribe_get_timings(session, &timings)
    return RuntimeRunCapture(
      status: status,
      inferenceSeconds: ProcessInfo.processInfo.systemUptime - started,
      transcript: string(transcribe_full_text(session)),
      aborted: transcribe_was_aborted(session),
      truncated: transcribe_was_truncated(session),
      timings: timings
    )
  }

  private static func readCapabilities(
    model: OpaquePointer
  ) -> (RuntimeCapabilities, transcribe_status) {
    var capabilities = transcribe_capabilities()
    transcribe_capabilities_init(&capabilities)
    let status = transcribe_model_get_capabilities(model, &capabilities)
    return (
      RuntimeCapabilities(
        maxAudioMilliseconds: capabilities.max_audio_ms,
        supportsCancellation: transcribe_model_supports(
          model,
          TRANSCRIBE_FEATURE_CANCELLATION
        )
      ),
      status
    )
  }

  private static func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.flatMap(String.init(validatingCString:)) ?? ""
  }
}

private enum RuntimeResultBuilder {
  static func success(
    capture: RuntimeRunCapture,
    actualBackend: String,
    capabilities: RuntimeCapabilities,
    diagnostics: [String],
    loadSeconds: Double
  ) -> RuntimeResult {
    let statusCode = Int32(capture.status.rawValue)
    let outcome = TranscriptCompletenessPolicy.outcome(
      statusCode: statusCode,
      aborted: capture.aborted,
      truncated: capture.truncated
    )
    return RuntimeResult(
      outcome: outcome,
      statusCode: statusCode,
      status: statusDescription(capture.status),
      diagnostics: diagnostics,
      transcript: capture.transcript,
      partialTranscript: TranscriptCompletenessPolicy.isPartial(
        outcome: outcome,
        transcript: capture.transcript
      ),
      truncated: capture.truncated,
      runtimeVersion: cString(transcribe_version()),
      runtimeCommit: cString(transcribe_version_commit()),
      actualBackend: actualBackend,
      capabilities: capabilities,
      loadSeconds: loadSeconds,
      inferenceSeconds: capture.inferenceSeconds,
      melMilliseconds: Double(capture.timings.mel_ms),
      encodeMilliseconds: Double(capture.timings.encode_ms),
      decodeMilliseconds: Double(capture.timings.decode_ms)
    )
  }

  static func failure(
    status: transcribe_status,
    actualBackend: String = "",
    capabilities: RuntimeCapabilities = RuntimeCapabilities(
      maxAudioMilliseconds: 0,
      supportsCancellation: false
    ),
    diagnostics: [String],
    loadSeconds: Double
  ) -> RuntimeResult {
    let statusCode = Int32(status.rawValue)
    var settledDiagnostics = diagnostics
    settledDiagnostics.append(RuntimeDiagnostics.status(stage: "settled failure", status))
    return RuntimeResult(
      outcome: TranscriptCompletenessPolicy.outcome(
        statusCode: statusCode,
        aborted: false,
        truncated: false
      ),
      statusCode: statusCode,
      status: statusDescription(status),
      diagnostics: settledDiagnostics,
      transcript: "",
      partialTranscript: false,
      truncated: false,
      runtimeVersion: cString(transcribe_version()),
      runtimeCommit: cString(transcribe_version_commit()),
      actualBackend: actualBackend,
      capabilities: capabilities,
      loadSeconds: loadSeconds,
      inferenceSeconds: 0,
      melMilliseconds: 0,
      encodeMilliseconds: 0,
      decodeMilliseconds: 0
    )
  }

  private static func statusDescription(_ status: transcribe_status) -> String {
    cString(transcribe_status_string(Int32(status.rawValue)))
  }

  private static func cString(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.flatMap(String.init(validatingCString:)) ?? ""
  }
}
