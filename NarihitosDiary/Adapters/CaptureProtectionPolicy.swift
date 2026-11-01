import Foundation

protocol CaptureProtectionPolicy: Sendable {
  func applyAndVerify(to url: URL, open: Bool, manager: FileManager) throws
  func verify(to url: URL, open: Bool, manager: FileManager) throws
}

struct AppleCaptureProtectionPolicy: CaptureProtectionPolicy {
  func applyAndVerify(to url: URL, open: Bool, manager: FileManager) throws {
    let expected: FileProtectionType =
      open ? .completeUnlessOpen : .completeUntilFirstUserAuthentication
    try manager.setAttributes([.protectionKey: expected], ofItemAtPath: url.path)
    try verify(to: url, open: open, manager: manager)
  }

  func verify(to url: URL, open: Bool, manager: FileManager) throws {
    let expected: FileProtectionType =
      open ? .completeUnlessOpen : .completeUntilFirstUserAuthentication
    let attributes = try manager.attributesOfItem(atPath: url.path)
    guard (attributes[.protectionKey] as? FileProtectionType) == expected else {
      throw CaptureGateFailure.storage
    }
  }
}

struct NoCaptureProtectionPolicy: CaptureProtectionPolicy {
  func applyAndVerify(to _: URL, open _: Bool, manager _: FileManager) throws {}
  func verify(to _: URL, open _: Bool, manager _: FileManager) throws {}
}
