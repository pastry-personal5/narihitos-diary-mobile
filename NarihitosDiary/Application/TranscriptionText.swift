import Foundation

/// Collects finalized segments without retaining volatile results or truncating text.
struct TranscriptionText {
  enum Failure: Error, Equatable {
    case tooLarge
    case unusable
  }

  private var text = ""
  private var byteCount = 0

  mutating func append(_ segment: String, isFinal: Bool) throws {
    guard isFinal, !segment.isEmpty else { return }
    let separator = needsSeparator(before: segment) ? " " : ""
    let addedBytes = separator.utf8.count + segment.utf8.count
    guard addedBytes <= DiaryBody.maximumBytes - byteCount else { throw Failure.tooLarge }
    text.append(separator)
    text.append(segment)
    byteCount += addedBytes
  }

  func finish() throws -> String {
    let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
      throw Failure.unusable
    }
    return result
  }

  private func needsSeparator(before segment: String) -> Bool {
    guard let previous = text.unicodeScalars.last, let next = segment.unicodeScalars.first else {
      return false
    }
    let previousIsSpace = CharacterSet.whitespacesAndNewlines.contains(previous)
    let nextIsSpace = CharacterSet.whitespacesAndNewlines.contains(next)
    if previousIsSpace || nextIsSpace { return false }
    // Closing punctuation belongs to the preceding segment; opening punctuation
    // belongs to the next one. Other adjacent segments need a word boundary.
    let closing = CharacterSet(charactersIn: ".,!?;:%)]}’”。，！？、：；％）］｝」』")
    let opening = CharacterSet(charactersIn: "([{‘“（［｛「『")
    return !closing.contains(next) && !opening.contains(previous)
  }
}
