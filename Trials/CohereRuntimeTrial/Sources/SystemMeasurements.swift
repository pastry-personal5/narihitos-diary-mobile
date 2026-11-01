import Darwin
import Foundation
import UIKit

enum SystemMeasurements {
  static func resourceSample(
    elapsedSeconds: Double,
    phase: MeasurementPhase
  ) -> ResourceSample {
    ResourceSample(
      elapsedSeconds: elapsedSeconds,
      phase: phase,
      availableProcessMemoryBytes: UInt64(os_proc_available_memory()),
      physicalFootprintBytes: physicalFootprintBytes(),
      thermalState: thermalStateName(ProcessInfo.processInfo.thermalState)
    )
  }

  @MainActor
  static func batteryObservation() -> BatteryObservation {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let rawLevel = UIDevice.current.batteryLevel
    return BatteryObservation(
      level: rawLevel < 0 ? nil : Double(rawLevel),
      state: batteryStateName(UIDevice.current.batteryState),
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
    )
  }

  static func modelIdentifier() -> String {
    var size = 0
    guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
      return "unknown"
    }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else {
      return "unknown"
    }
    let identifierBytes = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: identifierBytes, encoding: .utf8) ?? "unknown"
  }

  private static func physicalFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
      }
    }
    return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
  }

  private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    @unknown default: "unknown"
    }
  }

  private static func batteryStateName(_ state: UIDevice.BatteryState) -> String {
    switch state {
    case .unknown: "unknown"
    case .unplugged: "unplugged"
    case .charging: "charging"
    case .full: "full"
    @unknown default: "unknown"
    }
  }
}

final class ResourceSampler: @unchecked Sendable {
  private let lock = NSLock()
  private var collected: [ResourceSample] = []
  private var timer: DispatchSourceTimer?
  private var phase = MeasurementPhase.inputVerification
  private let startUptime = ProcessInfo.processInfo.systemUptime

  func start() {
    appendSample()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
    timer.setEventHandler { [weak self] in self?.appendSample() }
    self.timer = timer
    timer.resume()
  }

  func stop() -> [ResourceSample] {
    timer?.cancel()
    timer = nil
    appendSample()
    lock.lock()
    defer { lock.unlock() }
    return collected
  }

  func setPhase(_ phase: MeasurementPhase) {
    lock.lock()
    self.phase = phase
    lock.unlock()
    appendSample()
  }

  private func appendSample() {
    lock.lock()
    let currentPhase = phase
    lock.unlock()
    let sample = SystemMeasurements.resourceSample(
      elapsedSeconds: ProcessInfo.processInfo.systemUptime - startUptime,
      phase: currentPhase
    )
    lock.lock()
    collected.append(sample)
    lock.unlock()
  }
}
