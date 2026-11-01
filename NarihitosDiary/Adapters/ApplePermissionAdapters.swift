import AVFoundation
import CoreLocation
import UIKit

@MainActor
final class AppleMicrophoneAuthorization: MicrophoneAuthorizationPort {
  func currentState() -> PermissionState {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }

  func requestAccess() async -> PermissionState {
    guard currentState() == .notDetermined else { return currentState() }
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    return granted ? .authorized : currentState()
  }
}

@MainActor
final class AppleLocationAuthorization: NSObject, LocationAuthorizationPort {
  private let manager = CLLocationManager()
  private var requestContinuation: CheckedContinuation<PermissionState, Never>?
  private var requestID: UUID?

  override init() {
    super.init()
    manager.delegate = self
  }

  func currentState() -> PermissionState {
    switch manager.authorizationStatus {
    case .notDetermined: .notDetermined
    case .authorizedAlways, .authorizedWhenInUse: .authorized
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }

  func requestWhenInUse() async -> PermissionState {
    guard currentState() == .notDetermined else { return currentState() }
    guard requestContinuation == nil else { return currentState() }
    let requestID = UUID()
    return await withCheckedContinuation { continuation in
      self.requestID = requestID
      requestContinuation = continuation
      manager.requestWhenInUseAuthorization()
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(2))
        self?.finishRequest(ifCurrent: requestID)
      }
    }
  }

  private func finishRequest() {
    requestContinuation?.resume(returning: currentState())
    requestContinuation = nil
    requestID = nil
  }

  private func finishRequest(ifCurrent requestID: UUID) {
    guard self.requestID == requestID else { return }
    finishRequest()
  }
}

extension AppleLocationAuthorization: @preconcurrency CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager.authorizationStatus != .notDetermined else { return }
    finishRequest()
  }
}

@MainActor
final class AppleSystemSettings: SystemSettingsPort {
  func openApplicationSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}
