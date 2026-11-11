import CoreLocation
import Foundation
import MapKit

/// One short When In Use fix. Never requests authorization, accuracy upgrades or background mode.
@MainActor
final class AppleLocationSampleSource: NSObject, LocationSamplePort {
  private var manager: CLLocationManager?
  private var continuation: CheckedContinuation<LocationSample?, Never>?

  func currentLocation() async -> LocationSample? {
    guard continuation == nil else { return nil }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else { return continuation.resume(returning: nil) }
        self.continuation = continuation
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.manager = manager
        manager.requestLocation()
      }
    } onCancel: {
      Task { @MainActor in self.finish(nil) }
    }
  }

  private func finish(_ sample: LocationSample?) {
    manager?.stopUpdatingLocation()
    manager?.delegate = nil
    manager = nil
    continuation?.resume(returning: sample)
    continuation = nil
  }
}

extension AppleLocationSampleSource: @preconcurrency CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let last = locations.last else { return finish(nil) }
    finish(
      LocationSample(
        latitude: last.coordinate.latitude, longitude: last.coordinate.longitude,
        horizontalAccuracy: last.horizontalAccuracy, timestamp: last.timestamp))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finish(nil)
  }
}

/// Place label only; coordinates stay the accepted ones.
@MainActor
final class AppleMapKitPlaceSource: PlaceNamePort {
  func placeName(latitude: Double, longitude: Double) async -> String? {
    let location = CLLocation(latitude: latitude, longitude: longitude)
    guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
    return await withTaskCancellationHandler {
      guard let items = try? await request.mapItems, let item = items.first else { return nil }
      return item.addressRepresentations?.cityWithContext ?? item.name
    } onCancel: {
      request.cancel()
    }
  }
}
