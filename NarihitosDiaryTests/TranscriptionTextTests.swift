import Testing

@testable import NarihitosDiary

struct TranscriptionTextTests {
  @Test func joinsFinalSegmentsAndPreservesUnicode() throws {
    var text = TranscriptionText()
    try text.append(" Hello", isFinal: true)
    try text.append("ignored", isFinal: false)
    try text.append(",", isFinal: true)
    try text.append("world!", isFinal: true)
    try text.append(" 안녕하세요", isFinal: true)
    try text.append("세계", isFinal: true)
    try text.append("。 ", isFinal: true)
    #expect(try text.finish() == "Hello, world! 안녕하세요 세계。")
  }

  @Test func preservesExistingBoundariesAndOpeningPunctuation() throws {
    var text = TranscriptionText()
    try text.append("First ", isFinal: true)
    try text.append("(다음", isFinal: true)
    try text.append(")", isFinal: true)
    #expect(try text.finish() == "First (다음)")
  }

  @Test func rejectsNoUsableText() throws {
    var text = TranscriptionText()
    try text.append(" \n…?!", isFinal: true)
    #expect(throws: TranscriptionText.Failure.unusable) { try text.finish() }
  }

  @Test func rejectsOversizedUTF8WithoutTruncating() throws {
    var text = TranscriptionText()
    let exact = String(repeating: "a", count: DiaryBody.maximumBytes)
    try text.append(exact, isFinal: true)
    #expect(throws: TranscriptionText.Failure.tooLarge) {
      try text.append("한", isFinal: true)
    }
    #expect(try text.finish() == exact)
  }
}
