import Foundation

/// Browse handles are deliberately absent from durable edit records. Only an
/// adapter may exchange one for a freshly checked committed-resource capability.
struct DiaryEditSession: Sendable {
  let id: UUID
  let resourceKey: String
  let bindingID: UUID
  let sourceVersion: DiaryPairVersion
  let snippet: DiarySnippetV1
}

enum DiaryEditChange: Equatable, Sendable {
  case body(String)
  case favorite(Bool)
}

struct DiaryEditSubmission: Equatable, Sendable {
  let id: UUID
  let sessionID: UUID
  let change: DiaryEditChange
}

enum DiaryEditStage: String, Codable, Sendable {
  case accepted
  case ready
  case published
  case completed
  case recovery
  case quarantined

  func permitsCheckpoint(_ next: DiaryEditStage) -> Bool {
    switch self {
    case .accepted: next == .accepted || next == .recovery || next == .quarantined
    case .ready: next == .ready || next == .published || next == .recovery || next == .quarantined
    case .published:
      next == .published || next == .completed || next == .recovery || next == .quarantined
    case .completed: next == .completed
    case .recovery: next == .recovery || next == .quarantined
    case .quarantined: next == .quarantined
    }
  }
}

enum DiaryEditIssue: String, Error, Codable, Equatable, Sendable {
  case unavailable
  case localData
  case storage
  case changed
  case conflict
  case unsupported
  case invalidCandidate
  case busy
  case upload
  case reviewRequired
  case submissionMismatch

  var message: String {
    switch self {
    case .unavailable: "Waiting for access to this diary’s iCloud folder."
    case .localData: "The edit is waiting for protected local data."
    case .storage: "The edit’s save status couldn’t be verified. Keep this text and try Save again."
    case .changed: "This diary changed. Review its current version before saving."
    case .conflict: "Conflicting versions need review. Your submitted text has been kept."
    case .unsupported: "This diary can’t be edited safely."
    case .invalidCandidate: "The edited diary exceeds the supported document limits."
    case .busy: "Another operation is still working on this diary. Try again when it finishes."
    case .upload: "Waiting for iCloud upload verification."
    case .reviewRequired: "This submitted edit was restored and needs review before saving."
    case .submissionMismatch: "This Save request no longer matches its submitted text."
    }
  }

  var recoveryDestination: CatalogRecoveryDestination? {
    switch self {
    case .changed, .conflict: .conflicts
    case .unsupported, .invalidCandidate: .incomplete
    default: nil
    }
  }

  var canRetryAutomatically: Bool {
    switch self {
    case .unavailable, .localData, .storage, .busy, .upload: true
    default: false
    }
  }
}

struct DiaryEditRecord: Codable, Equatable, Sendable, Identifiable {
  let schema: Int
  let id: UUID
  let installationBinding: String
  let resourceKey: String
  let bindingID: UUID
  let sourceVersion: DiaryPairVersion
  let regeneratesTitle: Bool
  let destinationID: String
  let assetID: String
  var stage: DiaryEditStage
  var candidateDigest: String
  var candidateByteCount: Int64
  var publishedVersion: DiaryPairVersion?
  var markdownUploaded: Bool
  var audioUploaded: Bool
  var issue: DiaryEditIssue?
}

struct DiaryEditInventory: Sendable {
  let records: [DiaryEditRecord]
  let continuation: String?
  let isolatedCount: Int
}

enum DiaryEditAcceptance: Sendable {
  case accepted(DiaryEditRecord)
  case unchanged
}

enum DiaryEditPublication: Sendable {
  case verified(DiaryPairVersion)
  case waiting(DiaryEditIssue)
  case recovery(DiaryEditIssue)
}

/// Methods return only after their file/provider accessors have relinquished.
/// The adapter verifies journal bindings before every read, update, and cleanup.
@MainActor
protocol DiaryEditStorePort: AnyObject {
  func open(_ handle: CatalogItemHandle) async throws -> DiaryEditSession
  func accepted(
    _ submission: DiaryEditSubmission, session: DiaryEditSession
  ) async throws -> DiaryEditRecord?
  func accept(
    _ submission: DiaryEditSubmission, session: DiaryEditSession, candidate: DiarySnippetV1
  ) async throws -> DiaryEditAcceptance
  func inventory(after cursor: String?) async throws -> DiaryEditInventory
  func candidate(for record: DiaryEditRecord) async throws -> DiarySnippetV1
  func finalize(_ record: DiaryEditRecord, candidate: DiarySnippetV1) async throws
    -> DiaryEditRecord
  func checkpoint(_ record: DiaryEditRecord) async throws
  func publish(_ record: DiaryEditRecord) async -> DiaryEditPublication
  func uploads(for record: DiaryEditRecord) async throws -> DiaryPairUploadObservation
  func verifyUnchanged(_ record: DiaryEditRecord) async throws -> Bool
  func cleanup(_ record: DiaryEditRecord) async throws
  func closeSession(_ id: UUID)
  func pauseSessions()
  func invalidateSessions()
}

extension DiaryEditStorePort {
  func closeSession(_ id: UUID) {}
  func pauseSessions() { invalidateSessions() }
}

enum DiaryEditRevision {
  static func make(
    source: DiarySnippetV1, change: DiaryEditChange, now: Date
  ) throws -> DiarySnippetV1 {
    var candidate = source
    switch change {
    case .body(let text):
      candidate.body = try DiaryBody(text)
      let title = DiaryTitlePolicy.fallback(text)
      candidate.title = title.text
      candidate.titleProvenance = title.provenance
    case .favorite(let desired):
      guard source.favorite != desired else { return source }
      candidate.favorite = desired
    }
    let formatter = ISO8601DateFormatter()
    guard let previous = formatter.date(from: source.updatedAt.description) else {
      throw DiaryEditIssue.invalidCandidate
    }
    do {
      let current = try SchemaInstant.from(date: now)
      candidate.updatedAt =
        current.description > source.updatedAt.description
        ? current : try SchemaInstant.from(date: previous.addingTimeInterval(1))
    } catch {
      throw DiaryEditIssue.invalidCandidate
    }
    return candidate
  }
}
