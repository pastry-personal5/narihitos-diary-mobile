import Foundation
import Testing
@testable import NarihitosDiary

struct LaunchVersionPolicyTests {
  @Test func requiresApprovedPatchVersion() {
    #expect(
      !LaunchVersionPolicy.isSupported(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 9, patchVersion: 9)))
    #expect(
      !LaunchVersionPolicy.isSupported(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
    #expect(
      LaunchVersionPolicy.isSupported(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)))
    #expect(
      LaunchVersionPolicy.isSupported(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0)))
    #expect(
      LaunchVersionPolicy.isSupported(
        OperatingSystemVersion(majorVersion: 28, minorVersion: 0, patchVersion: 0)))
  }
}
