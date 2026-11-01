import Foundation

@MainActor
protocol MicrophoneAuthorizationPort: AnyObject {
  func currentState() -> PermissionState
  func requestAccess() async -> PermissionState
}

@MainActor
protocol LocationAuthorizationPort: AnyObject {
  func currentState() -> PermissionState
  func requestWhenInUse() async -> PermissionState
}

@MainActor
protocol SystemSettingsPort: AnyObject {
  func openApplicationSettings()
}

enum FirstLaunchStep: String, Codable, Equatable, Sendable {
  case microphone
  case location
  case complete
}

struct FirstLaunchProgress: Codable, Equatable, Sendable {
  var step: FirstLaunchStep = .microphone
  var microphoneAttempted = false
  var locationAttempted = false
}

@MainActor
protocol FirstLaunchStorePort: AnyObject {
  func loadFirstLaunchProgress() -> FirstLaunchProgress
  func saveFirstLaunchProgress(_ progress: FirstLaunchProgress) throws
}

@MainActor
protocol DestinationPort: AnyObject {
  func activeDestination() async -> ActiveDestination
  func invalidateAccess()
}

enum DestinationSelectionOutcome: Equatable {
  case prepared(PreparedDestination)
  case rejected
  case temporarilyUnavailable
}

struct PreparedDestination: Equatable, Identifiable {
  let id: UUID
  let displayName: String
  let needsDisclosure: Bool
}

enum DestinationCommitOutcome: Equatable {
  case committed(DestinationSummary)
  case superseded
  case failed
}

@MainActor
final class FirstLaunchCoordinator {
  private let microphone: any MicrophoneAuthorizationPort
  private let location: any LocationAuthorizationPort
  private let store: any FirstLaunchStorePort
  private(set) var progress: FirstLaunchProgress

  init(
    microphone: any MicrophoneAuthorizationPort,
    location: any LocationAuthorizationPort,
    store: any FirstLaunchStorePort
  ) {
    self.microphone = microphone
    self.location = location
    self.store = store
    self.progress = store.loadFirstLaunchProgress()
    normalizeProgress()
  }

  var pendingExplanation: FirstLaunchStep? {
    switch progress.step {
    case .microphone:
      return microphone.currentState() == .notDetermined && !progress.microphoneAttempted
        ? .microphone : .location
    case .location:
      return location.currentState() == .notDetermined && !progress.locationAttempted
        ? .location : nil
    case .complete:
      return nil
    }
  }

  func continueCurrentStep() async {
    switch progress.step {
    case .microphone:
      if microphone.currentState() == .notDetermined && !progress.microphoneAttempted {
        var attempted = progress
        attempted.microphoneAttempted = true
        guard persist(attempted) else { return }
        progress = attempted
        advance(to: .location)
        Task { [microphone] in
          _ = await microphone.requestAccess()
        }
      } else {
        advance(to: .location)
      }
      normalizeProgress()
    case .location:
      if location.currentState() == .notDetermined && !progress.locationAttempted {
        var attempted = progress
        attempted.locationAttempted = true
        guard persist(attempted) else { return }
        progress = attempted
        advance(to: .complete)
        Task { [location] in
          _ = await location.requestWhenInUse()
        }
      } else {
        advance(to: .complete)
      }
    case .complete:
      break
    }
  }

  func refresh() {
    normalizeProgress()
  }

  private func normalizeProgress() {
    let microphoneIsSettled =
      microphone.currentState() != .notDetermined || progress.microphoneAttempted
    if progress.step == .microphone && microphoneIsSettled {
      advance(to: .location)
    }
    let locationIsSettled = location.currentState() != .notDetermined || progress.locationAttempted
    if progress.step == .location && locationIsSettled {
      advance(to: .complete)
    }
  }

  private func advance(to step: FirstLaunchStep) {
    var advanced = progress
    advanced.step = step
    guard persist(advanced) else { return }
    progress = advanced
  }

  private func persist(_ proposed: FirstLaunchProgress) -> Bool {
    do {
      try store.saveFirstLaunchProgress(proposed)
      return true
    } catch {
      return false
    }
  }
}
