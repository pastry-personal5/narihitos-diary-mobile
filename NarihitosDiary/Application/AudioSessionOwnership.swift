import Foundation

enum AudioSessionRole: Sendable {
  case recording
  case replay
}

struct AudioSessionToken: Equatable, Sendable {
  let id: UUID
  let role: AudioSessionRole
}

@MainActor
protocol AudioSessionConfigurationPort: AnyObject {
  func activate(_ role: AudioSessionRole) throws
  func deactivate() throws
}

/// Ownership, rather than a view/task's lifetime, authorizes session changes.
/// Capture reserves priority before waiting for a replay accessor to settle.
@MainActor
final class AudioSessionOwnership {
  private let platform: any AudioSessionConfigurationPort
  private(set) var owner: AudioSessionToken?
  private(set) var captureReserved = false

  init(platform: any AudioSessionConfigurationPort) { self.platform = platform }

  func reserveCapture() { captureReserved = true }
  func cancelCaptureReservation() { captureReserved = false }

  func acquire(_ role: AudioSessionRole) throws -> AudioSessionToken {
    guard owner == nil, role == .recording || !captureReserved else { throw DiaryEditIssue.busy }
    let token = AudioSessionToken(id: UUID(), role: role)
    owner = token
    do {
      try platform.activate(role)
      if role == .recording { captureReserved = false }
      return token
    } catch {
      try? platform.deactivate()
      owner = nil
      if role == .recording { captureReserved = false }
      throw error
    }
  }

  func release(_ token: AudioSessionToken) {
    guard owner == token else { return }
    try? platform.deactivate()
    owner = nil
  }
}
