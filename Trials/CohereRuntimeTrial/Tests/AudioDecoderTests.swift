import AVFoundation
import Foundation
import Testing
@testable import CohereRuntimeTrial

struct AudioDecoderTests {
  @Test
  func stereo44100AudioIsCompletelyResampledToMono16K() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("caf")
    defer { try? FileManager.default.removeItem(at: url) }

    let sampleRate = 44_100.0
    let frameCount = AVAudioFrameCount(sampleRate)
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 2,
        interleaved: false
      )
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    for channelIndex in 0..<Int(format.channelCount) {
      let channel = try #require(buffer.floatChannelData?[channelIndex])
      for frame in 0..<Int(frameCount) {
        channel[frame] = sin(2 * .pi * 440 * Float(frame) / Float(sampleRate))
      }
    }
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }

    let decoded = try AudioDecoder.decode(url: url)
    #expect(abs(decoded.samples.count - 16_000) <= 2)
    #expect(abs(decoded.sourceDurationSeconds - 1) < 0.001)
  }

  @Test
  func hashingHonorsCancellation() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 1, count: 32).write(to: url)
    let cancellation = CancellationFlag()
    cancellation.cancel()

    #expect(throws: CancellationError.self) {
      try FileIdentityReader.read(url: url, cancellation: cancellation)
    }
  }
}
