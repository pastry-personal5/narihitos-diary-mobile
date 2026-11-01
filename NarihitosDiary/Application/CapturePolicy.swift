import Foundation

enum CaptureLanguage: String, Codable, Sendable {
  case english = "en-US"
  case korean = "ko-KR"
}

enum CaptureEndReason: String, Codable, Sendable {
  case user
  case timeLimit
  case interruption
  case recovery
}

enum CaptureGateFailure: Equatable, Error {
  case microphone
  case destination
  case insufficientSpace
  case storage
}

enum CaptureDestinationState: Equatable {
  case accessible
  case verifiedOffline
  case unavailable
}

struct CaptureIdentity: Equatable, Sendable {
  let id: WorkspaceID
  let startedAt: Date
  let language: CaptureLanguage
  let destinationReference: UUID
}

enum CapturePhase: Equatable {
  case idle
  case capturing(CaptureIdentity)
  case settling(CaptureIdentity, CaptureEndReason)
  case pending(CaptureIdentity)
  case failed(CaptureIdentity)
  case paused(CaptureIdentity)
}

struct CaptureInspection: Codable, Equatable {
  let byteCount: Int64
  let duration: TimeInterval
  let isMonoAAC: Bool
  let isPlayable: Bool
  let sampleRate: Double?
  let channelCount: Int?
  let codecIdentifier: UInt32?
  let approximateBitRate: Int?

  init(
    byteCount: Int64, duration: TimeInterval, isMonoAAC: Bool, isPlayable: Bool,
    sampleRate: Double? = nil, channelCount: Int? = nil,
    codecIdentifier: UInt32? = nil, approximateBitRate: Int? = nil
  ) {
    self.byteCount = byteCount
    self.duration = duration
    self.isMonoAAC = isMonoAAC
    self.isPlayable = isPlayable
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.codecIdentifier = codecIdentifier
    self.approximateBitRate = approximateBitRate
  }

  var isAccepted: Bool {
    byteCount > 0 && byteCount <= 64 * 1_024 * 1_024 && duration > 0
      && duration <= 301 && isMonoAAC && isPlayable
  }
}

@MainActor
protocol CaptureEnvironmentPort: AnyObject {
  func microphoneState() -> PermissionState
  func destinationState() async -> CaptureDestinationState
  func freeBytes() -> Int64?
  func snapshotDestination() async throws -> UUID
  func persistStart(_ identity: CaptureIdentity) throws
  func startAudio(id: WorkspaceID) throws
  func stopAudio() throws -> CaptureInspection
  func persistOutcome(_ identity: CaptureIdentity, inspection: CaptureInspection) throws -> Bool
  func currentAudioBytes() -> Int64?
}

@MainActor
final class CaptureCoordinator {
  static let minimumFreeBytes: Int64 = 100 * 1_024 * 1_024
  private let environment: any CaptureEnvironmentPort
  private let now: () -> Date
  private let uptime: () -> TimeInterval
  private var isStarting = false
  private var startedUptime: TimeInterval?
  private var deadlineTask: Task<Void, Never>?
  private(set) var phase: CapturePhase = .idle
  var onSettlement: ((CapturePhase) -> Void)?

  init(
    environment: any CaptureEnvironmentPort,
    now: @escaping () -> Date = Date.init,
    uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.environment = environment
    self.now = now
    self.uptime = uptime
  }

  func start(language: CaptureLanguage) async throws {
    guard phase == .idle, !isStarting else { return }
    isStarting = true
    defer { isStarting = false }
    try await checkPrerequisites()
    // The adapter persists its own independent reference before audio may begin.
    let reference = try await environment.snapshotDestination()
    guard environment.microphoneState() == .authorized else {
      throw CaptureGateFailure.microphone
    }
    let identity = CaptureIdentity(
      id: try WorkspaceID.random(), startedAt: now(), language: language,
      destinationReference: reference)
    do {
      try environment.persistStart(identity)
      try environment.startAudio(id: identity.id)
    } catch {
      phase = .paused(identity)
      throw error
    }
    phase = .capturing(identity)
    startedUptime = uptime()
    deadlineTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard let self else { return }
        self.poll()
        guard case .capturing = self.phase else { return }
      }
    }
  }

  private func checkPrerequisites() async throws {
    guard environment.microphoneState() == .authorized else {
      throw CaptureGateFailure.microphone
    }
    guard await environment.destinationState() != .unavailable else {
      throw CaptureGateFailure.destination
    }
    guard environment.microphoneState() == .authorized else {
      throw CaptureGateFailure.microphone
    }
    guard let free = environment.freeBytes() else { throw CaptureGateFailure.storage }
    guard free >= Self.minimumFreeBytes else {
      throw CaptureGateFailure.insufficientSpace
    }
  }

  var elapsedSeconds: Int {
    guard let startedUptime else { return 0 }
    return max(0, Int(uptime() - startedUptime))
  }

  func poll() {
    guard case .capturing = phase else { return }
    let sizeLimitExceeded = (environment.currentAudioBytes() ?? 0) > 64 * 1_024 * 1_024
    if elapsedSeconds >= 300 || sizeLimitExceeded {
      end(.timeLimit)
    }
  }

  func end(_ reason: CaptureEndReason) {
    guard case .capturing(let identity) = phase else { return }
    deadlineTask?.cancel()
    deadlineTask = nil
    phase = .settling(identity, reason)
    let inspection: CaptureInspection
    do {
      inspection = try environment.stopAudio()
    } catch {
      phase = .paused(identity)
      onSettlement?(phase)
      return
    }
    do {
      let isPending = try environment.persistOutcome(identity, inspection: inspection)
      phase = isPending ? .pending(identity) : .failed(identity)
    } catch {
      phase = .paused(identity)
    }
    onSettlement?(phase)
  }
}
