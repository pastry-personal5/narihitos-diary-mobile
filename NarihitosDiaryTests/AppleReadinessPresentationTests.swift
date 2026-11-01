import Testing

@testable import NarihitosDiary

struct AppleReadinessPresentationTests {
  @Test func statesHaveDistinctAccessibleLabelsWithoutPlatformDetails() {
    #expect(AppleReadinessPresentation.label(nil) == "Checking")
    #expect(AppleReadinessPresentation.label(.ready(resolvedLocale: "en-US")) == "Ready")
    #expect(
      AppleReadinessPresentation.label(.downloadable) == "Model not installed; download unavailable"
    )
    #expect(AppleReadinessPresentation.label(.downloading) == "Downloading")
    #expect(AppleReadinessPresentation.label(.unsupported) == "Language not supported")
    #expect(AppleReadinessPresentation.label(.unavailable) == "Unavailable on this device")
    #expect(AppleReadinessPresentation.label(.temporarilyUnavailable) == "Temporarily unavailable")
  }
}
