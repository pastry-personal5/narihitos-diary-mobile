import Foundation

struct DestinationCandidateFacts: Equatable {
  let isDirectory: Bool?
  let isSymbolicLink: Bool?
  let isUbiquitousItem: Bool?
  let hasICloudIdentity: Bool
}

@MainActor
final class AppleDestinationService: DestinationSelectionPort {
  static let maximumBookmarkSize = 64 * 1_024
  static let maximumIdentityArchiveSize = 16 * 1_024

  private struct PreparedRecord {
    let publicValue: PreparedDestination
    let generation: UInt64
    let bookmark: Data
    let identityArchive: Data
  }

  private let repository: PrivateSettingsRepository
  private let fileManager: FileManager
  private var generation: UInt64 = 0
  private var prepared: [UUID: PreparedRecord] = [:]

  init(repository: PrivateSettingsRepository, fileManager: FileManager = .default) {
    self.repository = repository
    self.fileManager = fileManager
  }

  func invalidateAccess() {
    generation &+= 1
    prepared.removeAll()
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

  private func resolveStoredDestination(
    _ stored: StoredDestinationRecord,
    id: DestinationID,
    summary: DestinationSummary
  ) -> ActiveDestination {
    let loanGeneration = generation
    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: stored.bookmark,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else {
        return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
      }
      defer { url.stopAccessingSecurityScopedResource() }
      let identity = try currentIdentityArchive()
      guard try identitiesMatch(stored.identityArchive, identity) else {
        return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
      }
      let name = try validateAndProject(url)
      let finalIdentity = try currentIdentityArchive()
      guard try identitiesMatch(stored.identityArchive, finalIdentity) else {
        return ActiveDestination(summary: summary, accessState: .restoreAccessRequired)
      }
      guard generation == loanGeneration else {
        return ActiveDestination(summary: summary, accessState: .temporarilyUnavailable)
      }
      if stale {
        let refreshed = try makeBookmark(for: url)
        let replacement = StoredDestinationRecord(
          id: id.rawValue,
          displayName: name,
          bookmark: refreshed,
          identityArchive: finalIdentity,
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
    guard url.startAccessingSecurityScopedResource() else { return .temporarilyUnavailable }
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      let name = try validateAndProject(url)
      let identity = try currentIdentityArchive()
      let bookmark = try makeBookmark(for: url)
      let token = UUID()
      let publicValue = PreparedDestination(
        id: token,
        displayName: name,
        needsDisclosure: repository.loadDestination()?.disclosureAcknowledged != true)
      prepared[token] = PreparedRecord(
        publicValue: publicValue,
        generation: transactionGeneration,
        bookmark: bookmark,
        identityArchive: identity)
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
      var stale = false
      let url = try URL(
        resolvingBookmarkData: candidate.bookmark,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else { return .failed }
      defer { url.stopAccessingSecurityScopedResource() }
      let name = try validateAndProject(url)
      let currentIdentity = try currentIdentityArchive()
      guard try identitiesMatch(candidate.identityArchive, currentIdentity) else {
        return .superseded
      }
      let finalBookmark = stale ? try makeBookmark(for: url) : candidate.bookmark
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
    var coordinationError: NSError?
    var result: Result<String, Error>?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordinationError
    ) { coordinatedURL in
      do {
        let basicKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let iCloudKeys: Set<URLResourceKey> = [.isUbiquitousItemKey, .nameKey]
        let keys = basicKeys.union(iCloudKeys)
        let values = try coordinatedURL.resourceValues(forKeys: keys)
        try Self.validate(
          DestinationCandidateFacts(
            isDirectory: values.isDirectory,
            isSymbolicLink: values.isSymbolicLink,
            isUbiquitousItem: values.isUbiquitousItem,
            hasICloudIdentity: fileManager.ubiquityIdentityToken != nil))
        result = .success(SafeFolderDisplayName.project(values.name ?? ""))
      } catch {
        result = .failure(error)
      }
    }
    if coordinationError != nil { throw DestinationValidationError.providerUnavailable }
    guard let result else { throw DestinationValidationError.providerUnavailable }
    return try result.get()
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
    let data = try url.bookmarkData(options: [.minimalBookmark])
    guard !data.isEmpty, data.count <= Self.maximumBookmarkSize else {
      throw DestinationValidationError.invalidReference
    }
    return data
  }

  private func currentIdentityArchive() throws -> Data {
    guard let token = fileManager.ubiquityIdentityToken else {
      throw DestinationValidationError.identityUnavailable
    }
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: token, requiringSecureCoding: false)
    guard !data.isEmpty, data.count <= Self.maximumIdentityArchiveSize else {
      throw DestinationValidationError.invalidReference
    }
    return data
  }

  private func identitiesMatch(_ stored: Data, _ current: Data) throws -> Bool {
    let allowedClasses: [AnyClass] = [NSObject.self]
    guard
      stored.count <= Self.maximumIdentityArchiveSize,
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
