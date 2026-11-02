import Testing

@testable import NarihitosDiary

struct CohereRuntimeBackendTests {
  @Test func targetPhoneBackendNameAcceptsTheVerifiedRequestedMetalDevice() {
    let observed = CohereRuntimeBackend(
      name: "MTL0", deviceKind: "metal", matchesRequestedDevice: true)

    #expect(observed.isSelectedMetal)
  }

  @Test func backendLabelCannotAuthorizeCPUOrMissingDeviceInspection() {
    for kind in ["cpu", "accel", "cuda", "unknown", nil] {
      let misleadingLabel = CohereRuntimeBackend(
        name: "metal", deviceKind: kind, matchesRequestedDevice: true)

      #expect(!misleadingLabel.isSelectedMetal)
    }
  }

  @Test func anotherMetalDeviceCannotSubstituteForTheRequestedDevice() {
    let replacement = CohereRuntimeBackend(
      name: "metal", deviceKind: "metal", matchesRequestedDevice: false)

    #expect(!replacement.isSelectedMetal)
  }

  @Test func semanticMetalNameAlsoRequiresVerifiedDeviceBinding() {
    let verified = CohereRuntimeBackend(
      name: "metal", deviceKind: "metal", matchesRequestedDevice: true)

    #expect(verified.isSelectedMetal)
  }
}
