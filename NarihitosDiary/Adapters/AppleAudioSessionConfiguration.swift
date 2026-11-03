import AVFAudio

@MainActor
final class AppleAudioSessionConfiguration: AudioSessionConfigurationPort {
  func activate(_ role: AudioSessionRole) throws {
    let session = AVAudioSession.sharedInstance()
    switch role {
    case .recording:
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    case .replay:
      try session.setCategory(.playback, mode: .spokenAudio)
    }
    try session.setActive(true)
  }

  func deactivate() throws {
    try AVAudioSession.sharedInstance().setActive(false)
  }
}
