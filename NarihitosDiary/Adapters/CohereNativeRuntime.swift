import CTranscribe
import Foundation

final class CohereCancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() { lock.withLock { cancelled = true } }
  func isCancelled() -> Bool { lock.withLock { cancelled } }
}

enum CohereRuntimeFailure: Error, Equatable {
  case cancelled
  case runtimeIdentity
  case backendUnavailable
  case modelLoad
  case incompatibleModel
  case session
  case inference
  case truncated
  case backendMismatch
}

protocol CohereRuntimeRunning: Sendable {
  func transcribe(
    modelURL: URL, samples: [Float], plan: CohereChunkPlan, languageHint: String,
    cancellation: CohereCancellationFlag
  ) throws -> [String]
}

struct CohereRuntimeBackend {
  let name: String
  let deviceKind: String?
  let matchesRequestedDevice: Bool

  var isSelectedMetal: Bool {
    // The runtime can name a Metal backend "MTL0". Authorize its inspected
    // device kind and exact binding; a display name cannot prove Metal use.
    deviceKind == "metal" && matchesRequestedDevice
  }
}

struct NativeCohereRuntime: CohereRuntimeRunning, Sendable {
  private static let configureLogging: Void = { transcribe_log_set(nil, nil) }()
  private static let abortCallback: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { pointer in
    guard let pointer else { return false }
    return Unmanaged<CohereCancellationFlag>.fromOpaque(pointer).takeUnretainedValue()
      .isCancelled()
  }

  func transcribe(
    modelURL: URL, samples: [Float], plan: CohereChunkPlan, languageHint: String,
    cancellation: CohereCancellationFlag
  ) throws -> [String] {
    _ = Self.configureLogging
    guard languageHint == "en" || languageHint == "ko" else {
      throw CohereRuntimeFailure.incompatibleModel
    }
    guard !cancellation.isCancelled() else { throw CohereRuntimeFailure.cancelled }
    guard cString(transcribe_version()) == CohereRuntimeProvenance.version,
      cString(transcribe_version_commit()) == CohereRuntimeProvenance.commit,
      transcribe_init_backends_default() == TRANSCRIBE_OK,
      transcribe_backend_available(TRANSCRIBE_BACKEND_METAL),
      let metalDevice = exactMetalDevice()
    else { throw CohereRuntimeFailure.backendUnavailable }

    var load = transcribe_model_load_params()
    transcribe_model_load_params_init(&load)
    load.backend = TRANSCRIBE_BACKEND_METAL
    load.device = metalDevice
    var model: OpaquePointer?
    let loadStatus = modelURL.path.withCString {
      transcribe_model_load_file($0, &load, &model)
    }
    guard loadStatus == TRANSCRIBE_OK, let model else {
      throw CohereRuntimeFailure.modelLoad
    }
    defer { transcribe_model_free(model) }
    guard !cancellation.isCancelled() else { throw CohereRuntimeFailure.cancelled }
    guard cString(transcribe_model_arch_string(model)) == "cohere_asr",
      backend(model: model, requestedDevice: metalDevice).isSelectedMetal
    else { throw CohereRuntimeFailure.incompatibleModel }
    var capabilities = transcribe_capabilities()
    transcribe_capabilities_init(&capabilities)
    guard transcribe_model_get_capabilities(model, &capabilities) == TRANSCRIBE_OK,
      capabilities.native_sample_rate == Int32(CohereAudioConversion.sampleRate),
      capabilities.max_audio_ms == 0 || capabilities.max_audio_ms >= 45_000,
      transcribe_model_supports(model, TRANSCRIBE_FEATURE_CANCELLATION)
    else { throw CohereRuntimeFailure.incompatibleModel }

    var transcripts: [String] = []
    transcripts.reserveCapacity(plan.chunks.count)
    for chunk in plan.chunks {
      guard !cancellation.isCancelled() else { throw CohereRuntimeFailure.cancelled }
      let text = try runChunk(
        model: model, metalDevice: metalDevice,
        samples: Array(samples[chunk.runtime.lowerBound..<chunk.runtime.upperBound]),
        languageHint: languageHint, cancellation: cancellation)
      transcripts.append(text)
    }
    guard transcripts.count == plan.chunks.count else {
      throw CohereRuntimeFailure.inference
    }
    return transcripts
  }

  private func runChunk(
    model: OpaquePointer, metalDevice: OpaquePointer, samples: [Float], languageHint: String,
    cancellation: CohereCancellationFlag
  ) throws -> String {
    guard !samples.isEmpty, samples.count <= CohereChunkPlanner.maximumRuntimeSamples else {
      throw CohereRuntimeFailure.inference
    }
    var sessionParameters = transcribe_session_params()
    transcribe_session_params_init(&sessionParameters)
    var session: OpaquePointer?
    guard transcribe_session_init(model, &sessionParameters, &session) == TRANSCRIBE_OK,
      let session
    else { throw CohereRuntimeFailure.session }
    defer { transcribe_session_free(session) }
    let cancellationPointer = Unmanaged.passUnretained(cancellation).toOpaque()
    transcribe_set_abort_callback(session, Self.abortCallback, cancellationPointer)
    var runParameters = transcribe_run_params()
    transcribe_run_params_init(&runParameters)
    runParameters.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
    let status = languageHint.withCString { language in
      runParameters.language = language
      return samples.withUnsafeBufferPointer { buffer in
        transcribe_run(session, buffer.baseAddress, Int32(buffer.count), &runParameters)
      }
    }
    let aborted =
      status == TRANSCRIBE_ERR_ABORTED || transcribe_was_aborted(session)
      || cancellation.isCancelled()
    if aborted {
      throw CohereRuntimeFailure.cancelled
    }
    guard status != TRANSCRIBE_ERR_OUTPUT_TRUNCATED,
      !transcribe_was_truncated(session)
    else { throw CohereRuntimeFailure.truncated }
    guard status == TRANSCRIBE_OK else { throw CohereRuntimeFailure.inference }
    guard backend(model: model, requestedDevice: metalDevice).isSelectedMetal
    else { throw CohereRuntimeFailure.backendMismatch }
    return cString(transcribe_full_text(session))
  }

  private func backend(
    model: OpaquePointer, requestedDevice: OpaquePointer
  ) -> CohereRuntimeBackend {
    let name = cString(transcribe_model_backend(model))
    guard let device = transcribe_model_device(model) else {
      return CohereRuntimeBackend(name: name, deviceKind: nil, matchesRequestedDevice: false)
    }
    var info = transcribe_device_info()
    transcribe_device_info_init(&info)
    let kind =
      transcribe_device_get_info(device, &info) == TRANSCRIBE_OK ? cString(info.kind) : nil
    return CohereRuntimeBackend(
      name: name, deviceKind: kind, matchesRequestedDevice: device == requestedDevice)
  }

  private func exactMetalDevice() -> OpaquePointer? {
    let count = transcribe_device_count()
    guard count > 0 else { return nil }
    for index in 0..<count {
      guard let device = transcribe_device_get(index) else { continue }
      var info = transcribe_device_info()
      transcribe_device_info_init(&info)
      guard transcribe_device_get_info(device, &info) == TRANSCRIBE_OK else { continue }
      if cString(info.kind) == "metal" { return device }
    }
    return nil
  }

  private func cString(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.flatMap(String.init(validatingCString:)) ?? ""
  }
}
