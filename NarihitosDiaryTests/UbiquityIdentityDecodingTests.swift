import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct UbiquityIdentityDecodingTests {
  @Test func existingArchivesMatchUsingTheLiveTokenCodingClass() throws {
    let token = NSData(data: Data([0x10, 0x20]))
    let platform = platform(token: token)
    // Existing stored tokens were archived without requiring secure coding.
    let stored = try archive(token)
    let current = try platform.currentIdentityArchive()

    #expect(try platform.identitiesMatch(stored, current))
    #expect(try platform.identitiesMatch(stored, platform.currentIdentityArchive()))
  }

  @Test func differentAccountsDoNotMatch() throws {
    let platform = platform(token: NSData(data: Data([0x20])))
    let stored = try archive(NSData(data: Data([0x10])))

    #expect(try !platform.identitiesMatch(stored, platform.currentIdentityArchive()))
  }

  @Test func unexpectedRootClassIsRejectedInEitherArchive() throws {
    let platform = platform(token: NSData(data: Data([0x10])))
    let valid = try platform.currentIdentityArchive()
    let unexpected = try archive(NSDate(timeIntervalSince1970: 0))

    #expect(throws: (any Error).self) { try platform.identitiesMatch(unexpected, valid) }
    #expect(throws: (any Error).self) { try platform.identitiesMatch(valid, unexpected) }
  }

  @Test func malformedArchivesAreRejected() throws {
    let platform = platform(token: NSData(data: Data([0x10])))
    let valid = try platform.currentIdentityArchive()

    for invalid in [Data(), Data([0x01, 0x02]), Data(valid.prefix(valid.count / 2))] {
      #expect(throws: (any Error).self) { try platform.identitiesMatch(invalid, valid) }
      #expect(throws: (any Error).self) { try platform.identitiesMatch(valid, invalid) }
    }
  }

  @Test func missingLiveIdentityRequiresRestore() throws {
    let platform = platform(token: nil)
    let stored = try archive(NSData(data: Data([0x10])))

    #expect(throws: DestinationValidationError.identityUnavailable) {
      try platform.identitiesMatch(stored, stored)
    }
  }

  @Test func broadCodingClassIsRejectedBeforeDecoding() throws {
    let platform = platform(token: BroadIdentityToken())
    let stored = try archive(NSData(data: Data([0x10])))

    #expect(throws: DestinationValidationError.invalidReference) {
      try platform.identitiesMatch(stored, stored)
    }
  }

  @Test func secureTokenControlsItsNestedClasses() throws {
    let platform = platform(token: SyntheticIdentityToken(value: "synthetic" as NSString))
    let current = try platform.currentIdentityArchive()
    let stored = try archive(SyntheticIdentityToken(value: "synthetic" as NSString))
    let changed = try archive(SyntheticIdentityToken(value: "changed" as NSString))
    let unexpected = try archive(SyntheticIdentityToken(value: NSDate(timeIntervalSince1970: 0)))

    #expect(try platform.identitiesMatch(stored, current))
    #expect(try !platform.identitiesMatch(changed, current))
    #expect(throws: (any Error).self) { try platform.identitiesMatch(unexpected, current) }
  }

  private func platform(
    token: (any NSCoding & NSCopying & NSObjectProtocol)?
  ) -> AppleDestinationPlatform {
    AppleDestinationPlatform(fileManager: IdentityFileManager(token: token))
  }

  private func archive(_ token: NSObject) throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
  }
}

private final class IdentityFileManager: FileManager, @unchecked Sendable {
  private let token: (any NSCoding & NSCopying & NSObjectProtocol)?

  init(token: (any NSCoding & NSCopying & NSObjectProtocol)?) {
    self.token = token
    super.init()
  }

  override var ubiquityIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)? { token }
}

@objc(NDMBroadIdentityToken)
private final class BroadIdentityToken: NSObject, NSCoding, NSCopying {
  override var classForCoder: AnyClass { NSObject.self }

  override init() { super.init() }
  required init?(coder: NSCoder) { super.init() }
  func encode(with coder: NSCoder) {}
  func copy(with zone: NSZone? = nil) -> Any { self }
}

@objc(NDMSyntheticIdentityToken)
private final class SyntheticIdentityToken: NSObject, NSSecureCoding, NSCopying {
  static var supportsSecureCoding: Bool { true }
  private let value: NSObject

  init(value: NSObject) { self.value = value }

  required init?(coder: NSCoder) {
    guard let value = coder.decodeObject(of: NSString.self, forKey: "value") else { return nil }
    self.value = value
  }

  func encode(with coder: NSCoder) { coder.encode(value, forKey: "value") }
  func copy(with zone: NSZone? = nil) -> Any { self }
  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? SyntheticIdentityToken else { return false }
    return value.isEqual(other.value)
  }
}
