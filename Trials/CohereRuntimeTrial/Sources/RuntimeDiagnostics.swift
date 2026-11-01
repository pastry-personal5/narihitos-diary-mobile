import CTranscribe
import Foundation

enum RuntimeDiagnostics {
  static func runtimeIdentity() -> [String] {
    var messages: [String] = []
    messages.append("runtime version: \(string(transcribe_version()))")
    messages.append("runtime commit: \(string(transcribe_version_commit()))")
    messages.append("requested backend: metal")
    return messages
  }

  static func status(stage: String, _ status: transcribe_status) -> String {
    let code = Int32(status.rawValue)
    return "\(stage): \(string(transcribe_status_string(code))) (\(code))"
  }

  static func devices() -> [String] {
    let count = transcribe_device_count()
    var messages = ["registered devices: \(count)"]
    messages.append(
      "Metal available: \(transcribe_backend_available(TRANSCRIBE_BACKEND_METAL))"
    )
    guard count > 0 else { return messages }
    for index in 0..<count {
      guard let device = transcribe_device_get(index) else {
        messages.append("device \(index): missing handle")
        continue
      }
      messages.append(deviceDescription(device, label: "device \(index)"))
    }
    return messages
  }

  static func model(_ model: OpaquePointer) -> [String] {
    var messages: [String] = []
    messages.append("model architecture: \(string(transcribe_model_arch_string(model)))")
    messages.append("model variant: \(string(transcribe_model_variant_string(model)))")
    messages.append("model backend: \(string(transcribe_model_backend(model)))")
    if let device = transcribe_model_device(model) {
      messages.append(deviceDescription(device, label: "model device"))
    } else {
      messages.append("model device: unavailable")
    }
    return messages
  }

  private static func deviceDescription(_ device: OpaquePointer, label: String) -> String {
    var info = transcribe_device_info()
    transcribe_device_info_init(&info)
    let infoStatus = transcribe_device_get_info(device, &info)
    guard infoStatus == TRANSCRIBE_OK else {
      return status(stage: "\(label) inspection", infoStatus)
    }
    return "\(label): \(string(info.name)); \(string(info.description)); kind "
      + "\(string(info.kind)); type \(info.device_type.rawValue); memory "
      + "\(byteCount(info.memory_free)) free / \(byteCount(info.memory_total)) total"
  }

  private static func byteCount(_ count: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .memory)
  }

  private static func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.flatMap(String.init(validatingCString:)) ?? "unavailable"
  }
}
