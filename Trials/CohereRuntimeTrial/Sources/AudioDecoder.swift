import AVFoundation
import Foundation

struct DecodedAudio: Sendable {
  let samples: [Float]
  let sourceDurationSeconds: Double
}

enum AudioDecoder {
  static let targetSampleRate = 16_000.0

  private struct ConversionBuffers {
    let source: AVAudioPCMBuffer
    let output: AVAudioPCMBuffer
  }

  private final class ConverterInput {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let cancellation: CancellationFlag?
    private var reachedEndOfFile = false
    private(set) var error: Error?

    init(file: AVAudioFile, buffer: AVAudioPCMBuffer, cancellation: CancellationFlag?) {
      self.file = file
      self.buffer = buffer
      self.cancellation = cancellation
    }

    func provide(
      requestedPackets: AVAudioPacketCount,
      status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
      if cancellation?.isCancelled() == true {
        error = CancellationError()
        status.pointee = .endOfStream
        return nil
      }
      guard !reachedEndOfFile, error == nil else {
        status.pointee = .endOfStream
        return nil
      }

      let remainingFrames = file.length - file.framePosition
      guard remainingFrames > 0 else {
        reachedEndOfFile = true
        status.pointee = .endOfStream
        return nil
      }

      do {
        let request = max(1, requestedPackets)
        let frameCount = AVAudioFrameCount(
          min(Int64(request), min(Int64(buffer.frameCapacity), remainingFrames))
        )
        try file.read(into: buffer, frameCount: frameCount)
      } catch {
        self.error = error
        status.pointee = .endOfStream
        return nil
      }

      guard buffer.frameLength > 0 else {
        reachedEndOfFile = true
        status.pointee = .endOfStream
        return nil
      }
      status.pointee = .haveData
      return buffer
    }
  }

  static func sourceDuration(url: URL) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.processingFormat.sampleRate > 0 else {
      throw TrialValidationError.emptyAudio
    }
    return Double(file.length) / file.processingFormat.sampleRate
  }

  static func decode(url: URL, cancellation: CancellationFlag? = nil) throws -> DecodedAudio {
    let file = try AVAudioFile(forReading: url)
    let sourceFormat = file.processingFormat
    guard file.length > 0, sourceFormat.sampleRate > 0 else {
      throw TrialValidationError.emptyAudio
    }
    let duration = Double(file.length) / sourceFormat.sampleRate
    let (converter, targetFormat) = try makeConverter(sourceFormat: sourceFormat)
    let buffers = try makeBuffers(
      sourceFormat: sourceFormat,
      targetFormat: targetFormat
    )
    let samples = try convert(
      file: file,
      converter: converter,
      buffers: buffers,
      expectedDuration: duration,
      cancellation: cancellation
    )
    guard !samples.isEmpty else { throw TrialValidationError.emptyAudio }
    return DecodedAudio(samples: samples, sourceDurationSeconds: duration)
  }

  private static func makeConverter(
    sourceFormat: AVAudioFormat
  ) throws -> (AVAudioConverter, AVAudioFormat) {
    guard
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
      ),
      let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
    else {
      throw CocoaError(.fileReadUnknown)
    }
    return (converter, targetFormat)
  }

  private static func makeBuffers(
    sourceFormat: AVAudioFormat,
    targetFormat: AVAudioFormat
  ) throws -> ConversionBuffers {
    let sourceCapacity: AVAudioFrameCount = 8_192
    guard
      let sourceBuffer = AVAudioPCMBuffer(
        pcmFormat: sourceFormat,
        frameCapacity: sourceCapacity
      )
    else {
      throw CocoaError(.fileReadUnknown)
    }

    let outputCapacity = AVAudioFrameCount(
      ceil(Double(sourceCapacity) * targetSampleRate / sourceFormat.sampleRate) + 32
    )
    guard
      let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: outputCapacity
      )
    else {
      throw CocoaError(.fileReadUnknown)
    }
    return ConversionBuffers(source: sourceBuffer, output: outputBuffer)
  }

  private static func convert(
    file: AVAudioFile,
    converter: AVAudioConverter,
    buffers: ConversionBuffers,
    expectedDuration: Double,
    cancellation: CancellationFlag?
  ) throws -> [Float] {
    var samples: [Float] = []
    samples.reserveCapacity(Int(expectedDuration * targetSampleRate))
    let input = ConverterInput(
      file: file,
      buffer: buffers.source,
      cancellation: cancellation
    )
    var noProgressCount = 0

    while true {
      if cancellation?.isCancelled() == true { throw CancellationError() }
      buffers.output.frameLength = 0
      var conversionError: NSError?
      let status = converter.convert(
        to: buffers.output,
        error: &conversionError
      ) { requestedPackets, inputStatus in
        input.provide(requestedPackets: requestedPackets, status: inputStatus)
      }
      if let inputError = input.error { throw inputError }
      if let conversionError { throw conversionError }
      let previousCount = samples.count
      try appendOutput(buffers.output, to: &samples)
      noProgressCount = samples.count == previousCount ? noProgressCount + 1 : 0
      if try conversionFinished(status: status, noProgressCount: noProgressCount) {
        return samples
      }
    }
  }

  private static func conversionFinished(
    status: AVAudioConverterOutputStatus,
    noProgressCount: Int
  ) throws -> Bool {
    switch status {
    case .haveData, .inputRanDry:
      guard noProgressCount < 8 else { throw CocoaError(.fileReadCorruptFile) }
      return false
    case .endOfStream:
      return true
    case .error:
      throw CocoaError(.fileReadCorruptFile)
    @unknown default:
      throw CocoaError(.fileReadUnknown)
    }
  }

  private static func appendOutput(
    _ outputBuffer: AVAudioPCMBuffer,
    to samples: inout [Float]
  ) throws {
    guard outputBuffer.frameLength == 0 || outputBuffer.floatChannelData?[0] != nil else {
      throw CocoaError(.fileReadUnknown)
    }
    guard outputBuffer.frameLength > 0, let channel = outputBuffer.floatChannelData?[0] else {
      return
    }
    samples.append(
      contentsOf: UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength))
    )
  }
}
