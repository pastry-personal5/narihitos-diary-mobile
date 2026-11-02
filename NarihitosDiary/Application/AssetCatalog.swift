import Foundation

struct CatalogSessionID: Hashable, Sendable {
  let rawValue: UUID
  init() { rawValue = UUID() }
}

struct CatalogCursor: Hashable, Sendable {
  let session: CatalogSessionID
  let token: UUID
}

struct CatalogItemHandle: Hashable, Sendable, Identifiable {
  let session: CatalogSessionID
  let resource: UUID
  let version: UUID
  let kind: String
  var id: UUID { resource }
}

struct CatalogSummary: Equatable, Sendable, Identifiable {
  let handle: CatalogItemHandle
  let assetID: String?
  let resourceOrder: String
  let createdAt: Date
  let title: String
  let favorite: Bool?
  var id: UUID { handle.resource }
}

enum CatalogRecoveryDestination: String, CaseIterable, Hashable, Sendable, Identifiable {
  case pending = "Pending Recordings"
  case failed = "Failed Recordings"
  case incomplete = "Incomplete Diary Snippets"
  case conflicts = "Conflicting Versions"
  var id: String { rawValue }
}

enum CatalogIssue: String, Error, Equatable, Sendable {
  case unsupported
  case malformed
  case unsafe
  case missingMarkdown
  case missingAudio
  case invalidAudio
  case ambiguousAudio
  case duplicateID
  case conflict
  case unavailable
  case changed
  case legacyFormatUnconfirmed

  var message: String {
    switch self {
    case .unsupported: "This format isn’t supported."
    case .malformed: "The diary text needs review."
    case .unsafe: "This item contains an unsafe file reference."
    case .missingMarkdown: "The diary text file is missing."
    case .missingAudio: "The audio file is missing."
    case .invalidAudio: "The audio can’t be read safely."
    case .ambiguousAudio: "More than one audio file may belong to this diary."
    case .duplicateID: "Separate items claim the same diary identity."
    case .conflict: "Conflicting versions need review."
    case .unavailable: "This item is temporarily unavailable. Try again."
    case .changed: "This item changed. Refresh to open its current version."
    case .legacyFormatUnconfirmed: "This older diary format needs review."
    }
  }

  var destination: CatalogRecoveryDestination { self == .conflict ? .conflicts : .incomplete }
  var retryable: Bool { self == .unavailable || self == .changed }
}

struct CatalogRecovery: Equatable, Sendable, Identifiable {
  let handle: CatalogItemHandle
  let issue: CatalogIssue
  let hasText: Bool
  let hasAudio: Bool
  var id: UUID { handle.resource }
  var destination: CatalogRecoveryDestination { issue.destination }
}

protocol CatalogDetailPayload: Sendable {}

struct CatalogLocation: Equatable, Sendable {
  let latitude: Decimal
  let longitude: Decimal
  let placeName: String?
}

struct CatalogWeather: Equatable, Sendable {
  let summary: String
  let temperatureCelsius: Decimal
}

struct CatalogRecoveryText: CatalogDetailPayload {
  let body: String
}

struct DiaryCatalogDetail: CatalogDetailPayload, Equatable {
  let title: String
  let body: String
  let favorite: Bool?
  let recordedAt: Date?
  let duration: TimeInterval?
  let language: String?
  let location: CatalogLocation?
  let weather: CatalogWeather?
  let audioAvailable: Bool
  let isLegacy: Bool
}

struct CatalogDetail: Sendable {
  let handle: CatalogItemHandle
  let payload: any CatalogDetailPayload
}

struct CatalogPage: Sendable {
  let session: CatalogSessionID
  let summaries: [CatalogSummary]
  let recovery: [CatalogRecovery]
  let continuation: CatalogCursor?
  let examinedCandidates: Int
  let isDiscovering: Bool
}

enum CatalogStart: Sendable {
  case ready(CatalogSessionID, CatalogCursor)
  case noFolder
  case unavailable
}

enum CatalogEvent: Sendable {
  case invalidated
  case accessChanged
}

@MainActor
protocol AssetCatalogPort: AnyObject {
  var onEvent: (@MainActor (CatalogEvent) -> Void)? { get set }
  func begin() async -> CatalogStart
  func page(_ cursor: CatalogCursor) async throws -> CatalogPage
  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail
  func end()
}

/// Shared browse state contains summaries only. Full bodies live in the open detail.
struct CatalogCollection {
  private(set) var summaries: [UUID: CatalogSummary] = [:]
  private(set) var recovery: [UUID: CatalogRecovery] = [:]
  private var claims: [String: Set<UUID>] = [:]

  mutating func merge(_ page: CatalogPage) {
    for summary in page.summaries {
      removeClaim(for: summary.id)
      summaries[summary.id] = summary
      recovery[summary.id] = nil
      if let assetID = summary.assetID { claims[assetID, default: []].insert(summary.id) }
    }
    for item in page.recovery {
      removeClaim(for: item.id)
      summaries[item.id] = nil
      recovery[item.id] = item
    }
    for ids in claims.values where ids.count > 1 {
      for id in ids {
        guard let summary = summaries[id] else { continue }
        recovery[id] = CatalogRecovery(
          handle: summary.handle, issue: .duplicateID, hasText: true, hasAudio: true)
      }
    }
  }

  var ordered: [CatalogSummary] {
    summaries.values.filter { recovery[$0.id] == nil }.sorted {
      if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
      let left = $0.assetID ?? $0.resourceOrder
      let right = $1.assetID ?? $1.resourceOrder
      return left == right ? $0.resourceOrder < $1.resourceOrder : left < right
    }
  }

  private mutating func removeClaim(for resource: UUID) {
    guard let oldID = summaries[resource]?.assetID else { return }
    claims[oldID]?.remove(resource)
    guard let remaining = claims[oldID], remaining.count == 1, let id = remaining.first else {
      return
    }
    if recovery[id]?.issue == .duplicateID { recovery[id] = nil }
  }
}

@MainActor
final class InactiveAssetCatalog: AssetCatalogPort {
  var onEvent: (@MainActor (CatalogEvent) -> Void)?
  func begin() async -> CatalogStart { .noFolder }
  func page(_ cursor: CatalogCursor) async throws -> CatalogPage { throw CatalogIssue.unavailable }
  func detail(_ handle: CatalogItemHandle) async throws -> CatalogDetail {
    throw CatalogIssue.unavailable
  }
  func end() {}
}
