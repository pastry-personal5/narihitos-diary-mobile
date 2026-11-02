import Foundation

// The selection transaction and capture-snapshot loan share one identity predicate.
// swiftlint:disable file_length

@MainActor
protocol DestinationSelectionPort: DestinationPort {
  func prepareSelection(of url: URL) -> DestinationSelectionOutcome
  func cancelPreparedSelection(_ id: UUID)
  func commitPreparedSelection(_ id: UUID) -> DestinationCommitOutcome
}

struct DestinationCandidateFacts: Equatable {
  let isDirectory: Bool?
  let isSymbolicLink: Bool?
  let isUbiquitousItem: Bool?
  let hasICloudIdentity: Bool
}

struct DestinationCandidateInspection: Equatable {
  let facts: DestinationCandidateFacts
  let displayName: String
}

struct ResolvedDestinationBookmark: Equatable {
  let url: URL
  let isStale: Bool
}

@MainActor
protocol DestinationPlatform: AnyObject {
  func startAccessing(_ url: URL) -> Bool
  func stopAccessing(_ url: URL)
  func inspect(_ url: URL) throws -> DestinationCandidateInspection
  func makeBookmark(for url: URL) throws -> Data
  func resolveBookmark(_ data: Data) throws -> ResolvedDestinationBookmark
  func currentIdentityArchive() throws -> Data
  func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool
}

@MainActor
// swiftlint:disable:next type_body_length
final class AppleDestinationService: DestinationSelectionPort {
  static let maximumBookmarkSize = 64 * 1_024
  static let maximumIdentityArchiveSize = 16 * 1_024

  private struct PreparedRecord {
    let publicValue: PreparedDestination
    let generation: UInt64
    let bookmark: Data
    let identityArchive: Data
  }

  private let repository: any DestinationSettingsStore
  private let platform: any DestinationPlatform
  private var generation: UInt64 = 0
  private var prepared: [UUID: PreparedRecord] = [:]

  init(
    repository: any DestinationSettingsStore,
    platform: any DestinationPlatform = AppleDestinationPlatform()
  ) {
    self.repository = repository
    self.platform = platform
  }

  func invalidateAccess() {
    generation &+= 1
    prepared.removeAll()
  }

  /// Selection-fenced catalog access differs from a capture's immutable destination.
  func withActiveCatalog<Value: Sendable>(
    expectedID: DestinationID? = nil,
    operation: (URL) async throws -> Value
  ) async throws -> Value {
    let loanGeneration = generation
    guard let stored = repository.loadDestination(),
      let (id, _) = validateStoredRecord(stored),
      expectedID == nil || expectedID == id
    else { throw DestinationValidationError.invalidReference }
    let access = await activeDestination()
    guard access.accessState == .accessible, generation == loanGeneration else {
      throw DestinationValidationError.providerUnavailable
    }
    return try await withCaptureSnapshotAsync(stored) { root in
      guard generation == loanGeneration, repository.loadDestination()?.id == stored.id else {
        throw CatalogIssue.changed
      }
      let value = try await operation(root)
      guard generation == loanGeneration,
        repository.loadDestination()?.id == stored.id
      else { throw CatalogIssue.changed }
      return value
    }
  }

  func activeDestination() async -> ActiveDestination {
    guard let stored = repository.loadDestination() else {
      return ActiveDestination(summary: nil, accessState: .restoreAccessRequired)
    }
    guard let (id, summary) = validateStoredRecord(stored) else {
      return ActiveDestination(summary: nil, accessState: .invalidStoredReference)
    }
    guard stored.disclosureAcknowledged else {
      return ActiveDestination(summary: summary, accessState: .invalidStoredReference)
    }
    return resolveStoredDestination(stored, id: id, summary: summary)
  }

  // Capture needs a stable copy of the accepted record, even if Settings later
  // replaces the active folder. Provider reachability is checked separately.
  func captureSnapshotRecord() async throws -> (StoredDestinationRecord, CaptureDestinationState) {
    guard let stored = repository.loadDestination(),
      validateStoredRecord(stored) != nil, stored.disclosureAcknowledged
    else { throw CaptureGateFailure.destination }
    let initial = try currentIdentityArchive()
    guard try identitiesMatch(stored.identityArchive, initial) else {
      throw CaptureGateFailure.destination
    }
    let access = await activeDestination()
    let eligibility: CaptureDestinationState
    switch access.accessState {
    case .accessible:
      eligibility = .accessible
    case .temporarilyUnavailable:
      eligibility = .verifiedOffline
    case .restoreAccessRequired, .invalidStoredReference:
      throw CaptureGateFailure.destination
    }
    let finalIdentity = try currentIdentityArchive()
    guard try identitiesMatch(stored.identityArchive, finalIdentity) else {
      throw CaptureGateFailure.destination
    }
    guard let effective = repository.loadDestination(),
      effective.id == stored.id,
      validateStoredRecord(effective) != nil,
      try identitiesMatch(effective.identityArchive, finalIdentity)
    else { throw CaptureGateFailure.destination }
    return (effective, eligibility)
  }

  /// A capture's private snapshot is independent of Settings' later selection.
  /// The caller must keep all coordinated provider work inside this loan.
  func withCaptureSnapshot<Value>(
    _ stored: StoredDestinationRecord, operation: (URL) throws -> Value
  ) throws -> Value {
    let url = try beginCaptureLoan(stored)
    defer { platform.stopAccessing(url) }
    let value = try operation(url)
    try verifyCaptureIdentity(stored)
    return value
  }

  func withCaptureSnapshotAsync<Value: Sendable>(
    _ stored: StoredDestinationRecord,
    operation: (URL) async throws -> Value
  ) async throws -> Value {
    let url = try beginCaptureLoan(stored)
    defer { platform.stopAccessing(url) }
    let value = try await operation(url)
    try verifyCaptureIdentity(stored)
    return value
  }

  private func beginCaptureLoan(_ stored: StoredDestinationRecord) throws -> URL {
    guard validateStoredRecord(stored) != nil, stored.disclosureAcknowledged else {
      throw DestinationValidationError.invalidReference
    }
    let initialIdentity = try currentIdentityArchive()
    guard try identitiesMatch(stored.identityArchive, initialIdentity) else {
      throw DestinationValidationError.identityUnavailable
    }
    let resolved = try platform.resolveBookmark(stored.bookmark)
    guard platform.startAccessing(resolved.url) else {
      throw DestinationValidationError.providerUnavailable
    }
    do {
      _ = try validateAndProject(resolved.url)
      try verifyCaptureIdentity(stored)
      return resolved.url
    } catch {
      platform.stopAccessing(resolved.url)
      throw error
    }
  }

  private func verifyCaptureIdentity(_ stored: StoredDestinationRecord) throws {
    let identity = try currentIdentityArchive()
    guard try identitiesMatch(stored.identityArchive, identity) else {
      throw DestinationValidationError.identityUnavailable
    }
  }

  private func resolveStoredDestination(
    _ stored: StoredDestinationRecord,
    id: DestinationID,
    summary: DestinationSummary
  ) -> ActiveDestination {
    let loanGeneration = generation
    do {
      let resolved = try platform.resolveBookmark(stored.bookmark)
      guard platform.startAccessing(resolved.url) else {
        return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
      }
      defer { platform.stopAccessing(resolved.url) }
      let identity = try currentIdentityArchive()
      guard try identitiesMatch(stored.identityArchive, identity) else {
        return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
      }
      let name = try validateAndProject(resolved.url)
      let finalIdentity = try currentIdentityArchive()
      guard try identitiesMatch(stored.identityArchive, finalIdentity) else {
        return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
      }
      guard generation == loanGeneration else {
        return ActiveDestination(summary: summary, accessState: .temporarilyUnavailable)
      }
      if resolved.isStale {
        let refreshed = try makeBookmark(for: resolved.url)
        let refreshIdentity = try currentIdentityArchive()
        guard try identitiesMatch(stored.identityArchive, refreshIdentity),
          generation == loanGeneration
        else {
          return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
        }
        let replacement = StoredDestinationRecord(
          id: id.rawValue,
          displayName: name,
          bookmark: refreshed,
          identityArchive: refreshIdentity,
          disclosureAcknowledged: stored.disclosureAcknowledged)
        try repository.saveDestination(replacement)
      }
      return ActiveDestination(
        summary: DestinationSummary(id: id, displayName: name), accessState: .accessible)
    } catch let error as DestinationValidationError {
      return ActiveDestination(summary: summary, accessState: error.accessState)
    } catch {
      return ActiveDestination(summary: summary, accessState: .temporarilyUnavailable)
    }
  }

  private func validateStoredRecord(
    _ stored: StoredDestinationRecord
  ) -> (DestinationID, DestinationSummary)? {
    guard
      let id = DestinationID(rawValue: stored.id),
      !stored.bookmark.isEmpty,
      stored.bookmark.count <= Self.maximumBookmarkSize,
      !stored.identityArchive.isEmpty,
      stored.identityArchive.count <= Self.maximumIdentityArchiveSize
    else { return nil }
    let summary = DestinationSummary(
      id: id, displayName: SafeFolderDisplayName.project(stored.displayName))
    return (id, summary)
  }

  func prepareSelection(of url: URL) -> DestinationSelectionOutcome {
    generation &+= 1
    prepared.removeAll()
    let transactionGeneration = generation
    guard platform.startAccessing(url) else { return .temporarilyUnavailable }
    defer { platform.stopAccessing(url) }
    do {
      let initialIdentity = try currentIdentityArchive()
      let name = try validateAndProject(url)
      let inspectedIdentity = try currentIdentityArchive()
      guard try identitiesMatch(initialIdentity, inspectedIdentity) else {
        return .temporarilyUnavailable
      }
      let bookmark = try makeBookmark(for: url)
      let finalIdentity = try currentIdentityArchive()
      guard try identitiesMatch(initialIdentity, finalIdentity), generation == transactionGeneration
      else { return .temporarilyUnavailable }
      let token = UUID()
      let publicValue = PreparedDestination(
        id: token,
        displayName: name,
        needsDisclosure: repository.loadDestination()?.disclosureAcknowledged != true)
      prepared[token] = PreparedRecord(
        publicValue: publicValue,
        generation: transactionGeneration,
        bookmark: bookmark,
        identityArchive: finalIdentity)
      return .prepared(publicValue)
    } catch let error as DestinationValidationError {
      switch error.accessState {
      case .temporarilyUnavailable, .restoreAccessRequired: return .temporarilyUnavailable
      case .accessible, .invalidStoredReference: return .rejected
      }
    } catch {
      return .temporarilyUnavailable
    }
  }

  func cancelPreparedSelection(_ id: UUID) {
    prepared.removeValue(forKey: id)
  }

  func commitPreparedSelection(_ id: UUID) -> DestinationCommitOutcome {
    guard let candidate = prepared.removeValue(forKey: id) else { return .superseded }
    guard candidate.generation == generation else { return .superseded }
    do {
      let resolved = try platform.resolveBookmark(candidate.bookmark)
      guard platform.startAccessing(resolved.url) else { return .failed }
      defer { platform.stopAccessing(resolved.url) }
      let name = try validateAndProject(resolved.url)
      let currentIdentity = try currentIdentityArchive()
      guard try identitiesMatch(candidate.identityArchive, currentIdentity) else {
        return .superseded
      }
      let finalBookmark =
        resolved.isStale ? try makeBookmark(for: resolved.url) : candidate.bookmark
      let commitIdentity = try currentIdentityArchive()
      guard try identitiesMatch(candidate.identityArchive, commitIdentity) else {
        return .superseded
      }
      guard candidate.generation == generation else { return .superseded }
      let destinationID = DestinationID.make()
      try repository.saveDestination(
        StoredDestinationRecord(
          id: destinationID.rawValue,
          displayName: name,
          bookmark: finalBookmark,
          identityArchive: commitIdentity,
          disclosureAcknowledged: true))
      return .committed(DestinationSummary(id: destinationID, displayName: name))
    } catch {
      return .failed
    }
  }

  private func validateAndProject(_ url: URL) throws -> String {
    let inspection = try platform.inspect(url)
    try Self.validate(inspection.facts)
    return SafeFolderDisplayName.project(inspection.displayName)
  }

  static func validate(_ facts: DestinationCandidateFacts) throws {
    guard facts.isDirectory == true, facts.isSymbolicLink == false else {
      throw DestinationValidationError.invalidReference
    }
    guard facts.isUbiquitousItem == true else {
      throw DestinationValidationError.notICloud
    }
    guard facts.hasICloudIdentity else {
      throw DestinationValidationError.identityUnavailable
    }
  }

  private func makeBookmark(for url: URL) throws -> Data {
    let data = try platform.makeBookmark(for: url)
    guard !data.isEmpty, data.count <= Self.maximumBookmarkSize else {
      throw DestinationValidationError.invalidReference
    }
    return data
  }

  private func currentIdentityArchive() throws -> Data {
    let data = try platform.currentIdentityArchive()
    guard !data.isEmpty, data.count <= Self.maximumIdentityArchiveSize else {
      throw DestinationValidationError.invalidReference
    }
    return data
  }

  private func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool {
    guard
      stored.count <= Self.maximumIdentityArchiveSize,
      current.count <= Self.maximumIdentityArchiveSize
    else { throw DestinationValidationError.invalidReference }
    return try platform.identitiesMatch(stored, current)
  }
}

@MainActor
final class AppleDestinationPlatform: DestinationPlatform {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func startAccessing(_ url: URL) -> Bool {
    url.startAccessingSecurityScopedResource()
  }

  func stopAccessing(_ url: URL) {
    url.stopAccessingSecurityScopedResource()
  }

  func inspect(_ url: URL) throws -> DestinationCandidateInspection {
    var coordinationError: NSError?
    var result: Result<DestinationCandidateInspection, Error>?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordinationError
    ) { coordinatedURL in
      do {
        var keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        keys.formUnion([.isUbiquitousItemKey, .nameKey])
        let values = try coordinatedURL.resourceValues(forKeys: keys)
        result = .success(
          DestinationCandidateInspection(
            facts: DestinationCandidateFacts(
              isDirectory: values.isDirectory,
              isSymbolicLink: values.isSymbolicLink,
              isUbiquitousItem: values.isUbiquitousItem,
              hasICloudIdentity: fileManager.ubiquityIdentityToken != nil),
            displayName: values.name ?? ""))
      } catch {
        result = .failure(error)
      }
    }
    if coordinationError != nil { throw DestinationValidationError.providerUnavailable }
    guard let result else { throw DestinationValidationError.providerUnavailable }
    return try result.get()
  }

  func makeBookmark(for url: URL) throws -> Data {
    try url.bookmarkData(options: [.minimalBookmark])
  }

  func resolveBookmark(_ data: Data) throws -> ResolvedDestinationBookmark {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale)
    return ResolvedDestinationBookmark(url: url, isStale: isStale)
  }

  func currentIdentityArchive() throws -> Data {
    guard let token = fileManager.ubiquityIdentityToken else {
      throw DestinationValidationError.identityUnavailable
    }
    return try NSKeyedArchiver.archivedData(
      withRootObject: token, requiringSecureCoding: false)
  }

  func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool {
    let allowedClasses: [AnyClass] = [NSObject.self]
    guard
      let storedToken = try NSKeyedUnarchiver.unarchivedObject(
        ofClasses: allowedClasses, from: stored) as? NSObject,
      let currentToken = try NSKeyedUnarchiver.unarchivedObject(
        ofClasses: allowedClasses, from: current) as? NSObject
    else { throw DestinationValidationError.invalidReference }
    return storedToken.isEqual(currentToken)
  }
}

enum DestinationValidationError: Error {
  case invalidReference
  case notICloud
  case identityUnavailable
  case providerUnavailable

  var accessState: DestinationAccessState {
    switch self {
    case .invalidReference, .notICloud: .invalidStoredReference
    case .identityUnavailable: .restoreAccessRequired
    case .providerUnavailable: .temporarilyUnavailable
    }
  }
}
