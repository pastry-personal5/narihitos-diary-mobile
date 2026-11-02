import Foundation
import Testing

@testable import NarihitosDiary

struct DiaryPairRecoveryTests {
  @Test func strictlyLaterWholePairWins() {
    let earlier = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 10),
      audio: Date(timeIntervalSince1970: 12))
    let later = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 20),
      audio: Date(timeIntervalSince1970: 22))
    #expect(DiaryPairConflictPolicy.select(first: earlier, second: later) == .second)
    #expect(DiaryPairConflictPolicy.select(first: later, second: earlier) == .first)
  }

  @Test func equalMissingOrCrossOrderedTimesNeedUserChoice() {
    let baseline = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 10),
      audio: Date(timeIntervalSince1970: 20))
    let equalMarkdown = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 10),
      audio: Date(timeIntervalSince1970: 30))
    let missingAudio = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 30), audio: nil)
    let crossOrdered = DiaryPairModificationTimes(
      markdown: Date(timeIntervalSince1970: 30),
      audio: Date(timeIntervalSince1970: 5))
    for alternative in [equalMarkdown, missingAudio, crossOrdered] {
      #expect(
        DiaryPairConflictPolicy.select(first: baseline, second: alternative) == .userChoice)
      #expect(
        DiaryPairConflictPolicy.select(first: alternative, second: baseline) == .userChoice)
    }
  }
}
