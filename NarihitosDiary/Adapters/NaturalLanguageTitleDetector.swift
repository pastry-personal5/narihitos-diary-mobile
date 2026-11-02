import Foundation
import NaturalLanguage

@MainActor
struct NaturalLanguageTitleDetector: DiaryTitleLanguageDetector {
  func assess(_ text: String) -> TitleLanguageAssessment? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage,
      language == .english || language == .korean
    else { return nil }
    let confidence = recognizer.languageHypotheses(withMaximum: 2)[language] ?? 0
    return TitleLanguageAssessment(
      language: language == .english ? "en" : "ko", confidence: confidence)
  }
}
