import Foundation

@testable import NarihitosDiary

/// Simulator attributes cannot establish iPhone Data Protection. Device runs
/// exercise the same complete-protection policy used by edit and replay storage.
struct DiaryFixtureProtection: DraftFileProtectionPolicy {
  func applyAndVerify(to url: URL) throws {
    #if !targetEnvironment(simulator)
      try AppleDraftProtectionPolicy().applyAndVerify(to: url)
    #endif
  }

  func verify(_ url: URL) throws {
    #if !targetEnvironment(simulator)
      try AppleDraftProtectionPolicy().verify(url)
    #endif
  }
}
