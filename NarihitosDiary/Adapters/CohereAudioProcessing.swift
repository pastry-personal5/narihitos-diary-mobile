import AVFAudio
import Foundation

enum CohereAudioConversion {
  static let identity = "ndm.cohere.pcm-f32-16khz-mono-v1"
  static let sampleRate = 16_000
  static let maximumSamples = sampleRate * 300

  enum Failure: Error, Equatable {
    case invalidInput
    case noProgress
    case tooLong
    case cancelled
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  static func convert(url: URL, cancelled: @Sendable () -> Bool) throws -> [Float] {
    if cancelled() { throw Failure.cancelled }
    let input: AVAudioFile
    do { input = try AVAudioFile(forReading: url) } catch { throw Failure.invalidInput }
    guard input.processingFormat.sampleRate > 0, input.processingFormat.channelCount > 0,
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1,
        interleaved: false),
      let converter = AVAudioConverter(from: input.processingFormat, to: outputFormat)
    else { throw Failure.invalidInput }

    let outputCapacity: AVAudioFrameCount = 4_096
    var result: [Float] = []
    let estimatedSamples =
      Int(Double(input.length) * Double(sampleRate) / input.processingFormat.sampleRate)
    result.reserveCapacity(min(maximumSamples, max(0, estimatedSamples)))
    var reachedEnd = false
    var inputFailure = false
    var noProgressCount = 0

    while true {
      if cancelled() { throw Failure.cancelled }
      guard
        let output = AVAudioPCMBuffer(
          pcmFormat: outputFormat, frameCapacity: outputCapacity)
      else { throw Failure.invalidInput }
      var conversionError: NSError?
      let status = converter.convert(
        to: output,
        error: &conversionError
      ) { requestedPackets, inputStatus in
        if cancelled() {
          inputStatus.pointee = .noDataNow
          return nil
        }
        if reachedEnd {
          inputStatus.pointee = .endOfStream
          return nil
        }
        let capacity = max(AVAudioFrameCount(1_024), requestedPackets)
        guard
          let buffer = AVAudioPCMBuffer(
            pcmFormat: input.processingFormat, frameCapacity: capacity)
        else {
          inputFailure = true
          inputStatus.pointee = .noDataNow
          return nil
        }
        do { try input.read(into: buffer, frameCount: capacity) } catch {
          if input.framePosition > 0, AudioFileReadFailure.isEndOfFile(error) {
            reachedEnd = true
            inputStatus.pointee = .endOfStream
          } else {
            inputFailure = true
            inputStatus.pointee = .noDataNow
          }
          return nil
        }
        guard buffer.frameLength > 0 else {
          reachedEnd = true
          inputStatus.pointee = .endOfStream
          return nil
        }
        inputStatus.pointee = .haveData
        return buffer
      }
      if cancelled() { throw Failure.cancelled }
      guard !inputFailure, conversionError == nil else { throw Failure.invalidInput }
      if output.frameLength > 0 {
        guard let channel = output.floatChannelData?[0] else { throw Failure.invalidInput }
        let count = Int(output.frameLength)
        guard count <= maximumSamples - result.count else { throw Failure.tooLong }
        result.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        noProgressCount = 0
      } else {
        noProgressCount += 1
      }
      switch status {
      case .endOfStream:
        return result
      case .error:
        throw Failure.invalidInput
      case .haveData, .inputRanDry:
        guard noProgressCount <= 16 else { throw Failure.noProgress }
      @unknown default:
        throw Failure.invalidInput
      }
    }
  }
}

struct CohereSampleSpan: Equatable, Sendable {
  let lowerBound: Int
  let upperBound: Int

  var count: Int { upperBound - lowerBound }
}

enum CohereChunkBoundary: String, Equatable, Sendable {
  case silence
  case hardSpeech
  case end
}

struct CohereChunk: Equatable, Sendable {
  let index: Int
  let primary: CohereSampleSpan
  let runtime: CohereSampleSpan
  let boundaryAfter: CohereChunkBoundary
}

struct CohereChunkPlan: Equatable, Sendable {
  let sampleCount: Int
  let chunks: [CohereChunk]
}

enum CohereChunkPlanner {
  static let identity = "ndm.cohere.silence-44s-overlap-500ms-v1"
  static let maximumRuntimeSamples = CohereAudioConversion.sampleRate * 45
  static let maximumPrimarySamples = CohereAudioConversion.sampleRate * 44
  static let minimumPrimarySamples = CohereAudioConversion.sampleRate * 10
  static let silenceSearchSamples = CohereAudioConversion.sampleRate * 4
  static let overlapSamples = CohereAudioConversion.sampleRate / 2
  static let energyWindowSamples = CohereAudioConversion.sampleRate / 50
  static let silenceRMSThreshold: Float = 0.003

  enum Failure: Error, Equatable {
    case empty
    case invalidCoverage
  }

  static func plan(samples: [Float]) throws -> CohereChunkPlan {
    guard !samples.isEmpty else { throw Failure.empty }
    var primaries: [CohereSampleSpan] = []
    var boundaries: [CohereChunkBoundary] = []
    var start = 0
    while start < samples.count {
      let hardEnd = min(samples.count, start + maximumPrimarySamples)
      if hardEnd == samples.count {
        primaries.append(CohereSampleSpan(lowerBound: start, upperBound: hardEnd))
        boundaries.append(.end)
        break
      }
      let searchStart = max(start + minimumPrimarySamples, hardEnd - silenceSearchSamples)
      let silence = quietestCut(samples: samples, lowerBound: searchStart, upperBound: hardEnd)
      let useSilence = silence.map { $0.rms <= silenceRMSThreshold } ?? false
      let end = useSilence ? silence!.sample : hardEnd
      guard end > start else { throw Failure.invalidCoverage }
      primaries.append(CohereSampleSpan(lowerBound: start, upperBound: end))
      boundaries.append(useSilence ? .silence : .hardSpeech)
      start = end
    }

    var chunks: [CohereChunk] = []
    for index in primaries.indices {
      let primary = primaries[index]
      let boundaryBefore = index == 0 ? .silence : boundaries[index - 1]
      let runtimeStart =
        boundaryBefore == .hardSpeech
        ? max(0, primary.lowerBound - overlapSamples) : primary.lowerBound
      let runtimeEnd =
        boundaries[index] == .hardSpeech
        ? min(samples.count, primary.upperBound + overlapSamples) : primary.upperBound
      let runtime = CohereSampleSpan(lowerBound: runtimeStart, upperBound: runtimeEnd)
      guard primary.lowerBound == (index == 0 ? 0 : primaries[index - 1].upperBound),
        primary.count > 0, primary.count <= maximumPrimarySamples,
        runtime.lowerBound <= primary.lowerBound, runtime.upperBound >= primary.upperBound,
        runtime.count <= maximumRuntimeSamples
      else { throw Failure.invalidCoverage }
      chunks.append(
        CohereChunk(
          index: index, primary: primary, runtime: runtime,
          boundaryAfter: boundaries[index]))
    }
    guard chunks.first?.primary.lowerBound == 0,
      chunks.last?.primary.upperBound == samples.count,
      chunks.reduce(0, { $0 + $1.primary.count }) == samples.count
    else { throw Failure.invalidCoverage }
    return CohereChunkPlan(sampleCount: samples.count, chunks: chunks)
  }

  private static func quietestCut(
    samples: [Float], lowerBound: Int, upperBound: Int
  ) -> (sample: Int, rms: Float)? {
    guard lowerBound < upperBound else { return nil }
    var best: (sample: Int, rms: Float)?
    var start = max(0, lowerBound - energyWindowSamples / 2)
    var end = min(samples.count, start + energyWindowSamples)
    var sum = samples[start..<end].reduce(0.0) { total, sample in
      total + Double(sample) * Double(sample)
    }
    for center in lowerBound..<upperBound {
      let nextStart = max(0, center - energyWindowSamples / 2)
      let nextEnd = min(samples.count, nextStart + energyWindowSamples)
      while start < nextStart {
        let sample = Double(samples[start])
        sum -= sample * sample
        start += 1
      }
      while end < nextEnd {
        let sample = Double(samples[end])
        sum += sample * sample
        end += 1
      }
      let rms = Float(sqrt(max(0, sum) / Double(end - start)))
      if best == nil || rms < best!.rms {
        best = (center, rms)
      }
    }
    return best
  }
}

enum CohereSeamAssembler {
  enum Failure: Error, Equatable {
    case countMismatch
    case ambiguousOverlap
    case tooLarge
    case unusable
  }

  private struct Token {
    let normalized: String
    let range: Range<String.Index>
  }

  static func assemble(plan: CohereChunkPlan, transcripts: [String]) throws -> String {
    guard plan.chunks.count == transcripts.count, !transcripts.isEmpty else {
      throw Failure.countMismatch
    }
    var combined = transcripts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    guard combined.utf8.count <= DiaryBody.maximumBytes else { throw Failure.tooLarge }
    for index in 1..<transcripts.count {
      let next = transcripts[index].trimmingCharacters(in: .whitespacesAndNewlines)
      switch plan.chunks[index - 1].boundaryAfter {
      case .silence:
        combined = try join(combined, next)
      case .hardSpeech:
        combined = try joinOverlapping(combined, next)
      case .end:
        throw Failure.countMismatch
      }
      guard combined.utf8.count <= DiaryBody.maximumBytes else { throw Failure.tooLarge }
    }
    let finished = combined.trimmingCharacters(in: .whitespacesAndNewlines)
    guard finished.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else {
      throw Failure.unusable
    }
    return finished
  }

  private static func joinOverlapping(_ left: String, _ right: String) throws -> String {
    guard !left.isEmpty, !right.isEmpty else { throw Failure.ambiguousOverlap }
    let leftTokens = tokens(in: left)
    let rightTokens = tokens(in: right)
    let maximum = min(24, leftTokens.count, rightTokens.count)
    guard maximum >= 2 else { throw Failure.ambiguousOverlap }
    let matches = (2...maximum).filter { count in
      leftTokens.suffix(count).map(\.normalized) == rightTokens.prefix(count).map(\.normalized)
    }
    guard matches.count == 1, let count = matches.first else {
      throw Failure.ambiguousOverlap
    }
    let suffix = String(right[rightTokens[count - 1].range.upperBound...])
    return try join(left, suffix)
  }

  private static func join(_ left: String, _ right: String) throws -> String {
    if left.isEmpty { return right }
    if right.isEmpty { return left }
    var text = TranscriptionText()
    do {
      try text.append(left, isFinal: true)
      try text.append(right, isFinal: true)
      return try text.finish()
    } catch TranscriptionText.Failure.tooLarge {
      throw Failure.tooLarge
    } catch {
      throw Failure.unusable
    }
  }

  private static func tokens(in text: String) -> [Token] {
    var result: [Token] = []
    var start: String.Index?
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      let isAlphanumeric = character.unicodeScalars.contains(where: {
        CharacterSet.alphanumerics.contains($0)
      })
      if isAlphanumeric, start == nil { start = index }
      if !isAlphanumeric, let tokenStart = start {
        let range = tokenStart..<index
        result.append(
          Token(
            normalized: String(text[range]).precomposedStringWithCanonicalMapping,
            range: range))
        start = nil
      }
      index = text.index(after: index)
    }
    if let start {
      let range = start..<text.endIndex
      result.append(
        Token(
          normalized: String(text[range]).precomposedStringWithCanonicalMapping,
          range: range))
    }
    return result
  }
}
