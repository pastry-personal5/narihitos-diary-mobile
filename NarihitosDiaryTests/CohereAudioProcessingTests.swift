import AVFAudio
import XCTest

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

final class CohereAudioProcessingTests: XCTestCase {
  func testFullAACConversionConsumesNormalAndShortEnglishCaptureFiles() throws {
    for frameCount in [441, 44_100] {
      let url = FileManager.default.temporaryDirectory.appending(
        path: "cohere-conversion-\(UUID()).m4a")
      defer { try? FileManager.default.removeItem(at: url) }
      try writeAAC(url: url, frameCount: AVAudioFrameCount(frameCount))

      let samples = try CohereAudioConversion.convert(url: url, cancelled: { false })

      XCTAssertFalse(samples.isEmpty)
      XCTAssertLessThanOrEqual(samples.count, CohereAudioConversion.maximumSamples)
      XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }
  }

  func testFullAACConversionRejectsSourceTruncatedAfterCaptureAcceptance() throws {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "cohere-conversion-\(UUID()).m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    try writeAAC(url: url, frameCount: 44_100)
    let bytes = try Data(contentsOf: url)
    try bytes.prefix(bytes.count / 2).write(to: url)

    XCTAssertThrowsError(try CohereAudioConversion.convert(url: url, cancelled: { false }))
  }

  func testPlannerCoversEverySampleOnceAndBoundsRuntimeInputs() throws {
    let sampleCount = CohereAudioConversion.sampleRate * 300
    let samples = [Float](repeating: 0.1, count: sampleCount)

    let plan = try CohereChunkPlanner.plan(samples: samples)

    XCTAssertEqual(plan.chunks.first?.primary.lowerBound, 0)
    XCTAssertEqual(plan.chunks.last?.primary.upperBound, sampleCount)
    XCTAssertEqual(plan.chunks.reduce(0) { $0 + $1.primary.count }, sampleCount)
    for pair in zip(plan.chunks, plan.chunks.dropFirst()) {
      XCTAssertEqual(pair.0.primary.upperBound, pair.1.primary.lowerBound)
    }
    XCTAssertTrue(
      plan.chunks.allSatisfy { $0.runtime.count <= CohereChunkPlanner.maximumRuntimeSamples })
    XCTAssertTrue(plan.chunks.dropLast().allSatisfy { $0.boundaryAfter == .hardSpeech })
  }

  func testPlannerPrefersDeterministicSilenceBoundary() throws {
    var samples = [Float](
      repeating: 0.1, count: CohereChunkPlanner.maximumPrimarySamples + 10_000)
    let silenceStart = CohereChunkPlanner.maximumPrimarySamples - 2_000
    for index in silenceStart..<(silenceStart + CohereChunkPlanner.energyWindowSamples) {
      samples[index] = 0
    }

    let first = try CohereChunkPlanner.plan(samples: samples)
    let second = try CohereChunkPlanner.plan(samples: samples)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.chunks.first?.boundaryAfter, .silence)
    XCTAssertLessThan(first.chunks.first?.primary.upperBound ?? .max, samples.count)
  }

  func testPlannerRejectsEmptyInput() {
    XCTAssertThrowsError(try CohereChunkPlanner.plan(samples: [])) { error in
      XCTAssertEqual(error as? CohereChunkPlanner.Failure, .empty)
    }
  }

  func testSilenceSeamsPreserveEnglishAndKoreanUnicode() throws {
    let plan = plan(boundary: .silence)

    XCTAssertEqual(
      try CohereSeamAssembler.assemble(
        plan: plan, transcripts: ["A complete sentence.", "다음 문장입니다."]),
      "A complete sentence. 다음 문장입니다.")
  }

  func testEmptySilenceChunkDoesNotDiscardUsableSpeech() throws {
    let plan = plan(boundary: .silence)
    XCTAssertEqual(
      try CohereSeamAssembler.assemble(plan: plan, transcripts: ["", "다음 문장입니다."]),
      "다음 문장입니다.")
  }

  func testHardSeamRemovesOneUniqueExactOverlap() throws {
    let plan = plan(boundary: .hardSpeech)

    XCTAssertEqual(
      try CohereSeamAssembler.assemble(
        plan: plan,
        transcripts: ["before 경계를 넘는 정확한 구절", "경계를 넘는 정확한 구절 after"]),
      "before 경계를 넘는 정확한 구절 after")
  }

  func testHardSeamKeepsPunctuationAfterMatchedWords() throws {
    let plan = plan(boundary: .hardSpeech)
    XCTAssertEqual(
      try CohereSeamAssembler.assemble(
        plan: plan, transcripts: ["before repeated exact words", "repeated exact words, after"]),
      "before repeated exact words, after")
  }

  func testHardSeamDoesNotGuessAtSingleRepeatedWord() {
    let plan = plan(boundary: .hardSpeech)

    XCTAssertThrowsError(
      try CohereSeamAssembler.assemble(
        plan: plan, transcripts: ["I said go", "go home now"])
    ) { error in
      XCTAssertEqual(error as? CohereSeamAssembler.Failure, .ambiguousOverlap)
    }
  }

  func testHardSeamRejectsAmbiguousRepeatedPhrase() {
    let plan = plan(boundary: .hardSpeech)

    XCTAssertThrowsError(
      try CohereSeamAssembler.assemble(
        plan: plan, transcripts: ["red blue red blue", "red blue red blue today"])
    ) { error in
      XCTAssertEqual(error as? CohereSeamAssembler.Failure, .ambiguousOverlap)
    }
  }

  private func plan(boundary: CohereChunkBoundary) -> CohereChunkPlan {
    CohereChunkPlan(
      sampleCount: 200,
      chunks: [
        CohereChunk(
          index: 0, primary: CohereSampleSpan(lowerBound: 0, upperBound: 100),
          runtime: CohereSampleSpan(lowerBound: 0, upperBound: 110), boundaryAfter: boundary),
        CohereChunk(
          index: 1, primary: CohereSampleSpan(lowerBound: 100, upperBound: 200),
          runtime: CohereSampleSpan(lowerBound: 90, upperBound: 200), boundaryAfter: .end),
      ])
  }

  private func writeAAC(url: URL, frameCount: AVAudioFrameCount) throws {
    let format = try XCTUnwrap(
      AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    if let samples = buffer.floatChannelData {
      for index in 0..<Int(frameCount) {
        samples[0][index] = 0.08 * sin(Float(index) * 2 * .pi * 440 / 44_100)
      }
    }
    let writer = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
      ])
    try writer.write(from: buffer)
  }
}

// swiftlint:enable trailing_comma
