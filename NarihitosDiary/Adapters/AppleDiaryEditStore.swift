import Foundation
import UIKit

// swift-format wraps multiline closure parameters and result-type braces.
// swiftlint:disable closure_parameter_position opening_brace

@MainActor
final class AppleDiaryEditStore: DiaryEditStorePort, DiaryEditRecoveryPort {
  private struct LiveSession {
    let session: DiaryEditSession
    let catalog: CatalogActionBinding
    let facts: CommittedDiaryFacts
  }

  private let catalog: AppleAssetCatalog
  private let destination: AppleDestinationService
  private let installation: any InstallationIdentityPort
  private let observer: any DiaryFileObserverPort
  let journal: DiaryEditJournal
  private let protectedDataAvailable: () -> Bool
  private var sessions: [UUID: LiveSession] = [:]
  private var epoch = UUID()

  init(
    catalog: AppleAssetCatalog, destination: AppleDestinationService,
    installation: any InstallationIdentityPort,
    root: URL? = nil,
    protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver(),
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
  ) {
    self.catalog = catalog
    self.destination = destination
    self.installation = installation
    self.observer = observer
    self.protectedDataAvailable = protectedDataAvailable
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    journal = DiaryEditJournal(
      files: DiaryEditPrivateFiles(
        root: root ?? support.appending(path: "NarihitosDiary/PrivateWorkspaces/DiaryEdits"),
        protection: protection))
  }

  func open(_ handle: CatalogItemHandle) async throws -> DiaryEditSession {
    try requireAccess()
    let generation = epoch
    do {
      let binding = try await catalog.actionBinding(handle)
      let facts = try await destination.withCommittedDestination(binding.destination) { root in
        try await CommittedDiaryResource.coordinated(binding.resource, root: root) {
          root, control in
          try CommittedDiaryResource.inspect(binding.resource, root: root, control: control)
        }
      }
      guard generation == epoch, !Task.isCancelled, let snippet = facts.snippet else {
        throw DiaryEditIssue.unsupported
      }
      let key = CommittedDiaryResource.resourceKey(
        destinationID: binding.destination.id, rootIdentity: facts.rootIdentity,
        candidate: binding.resource.candidate)
      try await journal.assertAvailable(resourceKey: key)
      let session = DiaryEditSession(
        id: UUID(), resourceKey: key, bindingID: UUID(), sourceVersion: facts.version,
        snippet: snippet)
      sessions[session.id] = LiveSession(session: session, catalog: binding, facts: facts)
      return session
    } catch { throw Self.issue(error) }
  }

  func accepted(
    _ submission: DiaryEditSubmission, session: DiaryEditSession
  ) async throws -> DiaryEditRecord? {
    try requireAccess()
    return try await journal.existing(submission, session: session)
  }

  func accept(
    _ submission: DiaryEditSubmission, session: DiaryEditSession, candidate: DiarySnippetV1
  ) async throws -> DiaryEditAcceptance {
    try requireAccess()
    if let record = try await accepted(submission, session: session) { return .accepted(record) }
    guard let live = sessions[session.id], live.session.sourceVersion == session.sourceVersion,
      live.session.resourceKey == session.resourceKey, live.session.snippet == session.snippet,
      submission.sessionID == session.id
    else { throw DiaryEditIssue.changed }
    let generation = epoch
    let installationBinding = try currentInstallation()
    let activeDestination = try await destination.committedDestinationRecord()
    guard activeDestination.id == live.catalog.destination.id, generation == epoch else {
      throw DiaryEditIssue.changed
    }
    let binding = DiaryEditBinding(
      schema: 1, id: session.bindingID, transactionID: submission.id,
      installationBinding: installationBinding, resourceKey: session.resourceKey,
      destination: live.catalog.destination, rootIdentity: live.facts.rootIdentity,
      candidate: live.catalog.resource.candidate, sourceVersion: session.sourceVersion,
      markdownContentIdentity: live.facts.markdownContentIdentity,
      audioContentIdentity: live.facts.audioContentIdentity,
      audioComponents: live.facts.audioComponents, audioByteCount: live.facts.audioBytes,
      submissionDigest: CommittedDiaryResource.submissionDigest(submission.change),
      publicationToken: UUID())
    do {
      let noOp = try validateCandidate(candidate, submission: submission, session: session)
      if noOp {
        try await revalidate(live)
        guard generation == epoch, !Task.isCancelled else { throw DiaryEditIssue.changed }
        return .unchanged
      }
      try await retainSourceAudio(live, binding: binding)
      guard generation == epoch, !Task.isCancelled else { throw DiaryEditIssue.changed }
      let regeneratesTitle: Bool
      if case .body = submission.change {
        regeneratesTitle = true
      } else {
        regeneratesTitle = false
      }
      let record = try await journal.accept(
        binding, candidate: candidate, regeneratesTitle: regeneratesTitle)
      sessions[session.id] = nil
      return .accepted(record)
    } catch {
      try? await journal.abandonUnaccepted(binding)
      throw Self.issue(error)
    }
  }

  private func validateCandidate(
    _ candidate: DiarySnippetV1, submission: DiaryEditSubmission, session: DiaryEditSession
  ) throws -> Bool {
    var expected = try DiaryEditRevision.make(
      source: session.snippet, change: submission.change, now: Date(timeIntervalSince1970: 0))
    expected.updatedAt = candidate.updatedAt
    guard candidate == expected else { throw DiaryEditIssue.invalidCandidate }
    do { _ = try DiarySnippetMarkdownCodec().encode(candidate) } catch {
      throw DiaryEditIssue.invalidCandidate
    }
    return candidate == session.snippet
  }

  private func retainSourceAudio(_ live: LiveSession, binding: DiaryEditBinding) async throws {
    let directory = try await journal.prepare(binding)
    let files = journal.files
    _ = try await destination.withCommittedDestination(binding.destination) { root in
      try await CommittedDiaryResource.coordinated(live.catalog.resource, root: root) {
        root, control in
        let current = try CommittedDiaryResource.inspect(
          live.catalog.resource, root: root, control: control)
        guard current.rootIdentity == binding.rootIdentity else { throw DiaryEditIssue.changed }
        try files.copyAudio(
          root: root, components: binding.audioComponents,
          expected: current.audioVersion, to: directory, control: control)
        _ = try CommittedDiaryResource.inspect(live.catalog.resource, root: root, control: control)
        return true
      }
    }
  }

  func inventory(after cursor: String?) async throws -> DiaryEditInventory {
    try requireAccess()
    return try await journal.inventory(after: cursor, installation: currentInstallation())
  }

  func candidate(for record: DiaryEditRecord) async throws -> DiarySnippetV1 {
    try requireCurrentInstallation(record)
    return try await journal.candidate(record)
  }

  func finalize(_ record: DiaryEditRecord, candidate: DiarySnippetV1) async throws
    -> DiaryEditRecord
  {
    try requireCurrentInstallation(record)
    return try await journal.finalize(record, candidate: candidate)
  }

  func checkpoint(_ record: DiaryEditRecord) async throws {
    try requireCurrentInstallation(record)
    try await journal.checkpoint(record)
  }

  func publish(_ record: DiaryEditRecord) async -> DiaryEditPublication {
    do {
      try requireCurrentInstallation(record)
      try await journal.assertAvailable(resourceKey: record.resourceKey, transactionID: record.id)
      let binding = try await journal.binding(record)
      let candidate = try await journal.candidate(record)
      let files = journal.files
      return try await destination.withCommittedDestination(binding.destination) { root in
        try await DiaryEditPublicationAdapter.publish(
          record, binding: binding, candidate: candidate, root: root, files: files)
      }
    } catch {
      let issue = Self.issue(error)
      if issue == .changed || issue == .conflict {
        do { try await retainExternalSnapshot(record) } catch {
          let snapshotIssue = Self.issue(error)
          return snapshotIssue == .unsupported ? .recovery(.unsupported) : .waiting(.localData)
        }
      }
      return issue == .changed || issue == .conflict || issue == .unsupported
        ? .recovery(issue) : .waiting(issue)
    }
  }

  func uploads(for record: DiaryEditRecord) async throws -> DiaryPairUploadObservation {
    try requireCurrentInstallation(record)
    let binding = try await journal.binding(record)
    let files = journal.files
    let observer = observer
    return try await destination.withCommittedDestination(binding.destination) { root in
      try await DiaryEditPublicationAdapter.uploads(
        record, binding: binding, root: root, files: files, observer: observer)
    }
  }

  func verifyUnchanged(_ record: DiaryEditRecord) async throws -> Bool {
    try requireCurrentInstallation(record)
    let binding = try await journal.binding(record)
    let files = journal.files
    return try await destination.withCommittedDestination(binding.destination) { root in
      try await DiaryEditPublicationAdapter.verify(
        record, binding: binding, root: root, files: files)
    }
  }

  func cleanup(_ record: DiaryEditRecord) async throws {
    try requireCurrentInstallation(record)
    try await journal.cleanup(record)
  }

  func invalidateSessions() {
    epoch = UUID()
    sessions.removeAll()
  }

  func closeSession(_ id: UUID) { sessions[id] = nil }

  func pauseSessions() { epoch = UUID() }

  func recoverySnapshots(for recordID: UUID) async throws -> [DiaryEditRecoverySnapshot] {
    try requireAccess()
    let record = try await journal.record(recordID)
    let snapshots = DiaryEditConflictSnapshots(files: journal.files)
    return try await Task.detached(priority: .utility) { try snapshots.list(record) }.value
  }

  func recoveryCandidate(recordID: UUID, snapshotID: UUID?) async throws -> DiarySnippetV1 {
    try requireAccess()
    let record = try await journal.record(recordID)
    guard let snapshotID else { return try await journal.candidate(record) }
    let snapshots = DiaryEditConflictSnapshots(files: journal.files)
    return try await Task.detached(priority: .utility) {
      try snapshots.preview(record, snapshotID: snapshotID)
    }.value
  }

  private func retainExternalSnapshot(_ record: DiaryEditRecord) async throws {
    let binding = try await journal.binding(record)
    let snapshots = DiaryEditConflictSnapshots(files: journal.files)
    let resource = CatalogActionResource(candidate: binding.candidate, version: "")
    _ = try await destination.withCommittedDestination(binding.destination) { root in
      try await CommittedDiaryResource.coordinated(resource, root: root) { root, control in
        try snapshots.capture(record, binding: binding, root: root, control: control)
      }
    }
  }

}

extension AppleDiaryEditStore {
  private func revalidate(_ live: LiveSession) async throws {
    _ = try await destination.withCommittedDestination(live.catalog.destination) { root in
      try await CommittedDiaryResource.coordinated(live.catalog.resource, root: root) {
        root, control in
        _ = try CommittedDiaryResource.inspect(live.catalog.resource, root: root, control: control)
        return true
      }
    }
  }

  private func requireAccess() throws {
    guard protectedDataAvailable() else { throw DiaryEditIssue.localData }
  }

  private func currentInstallation() throws -> String {
    guard case .available(let binding) = installation.currentOrCreate() else {
      throw DiaryEditIssue.localData
    }
    return binding
  }

  private func requireCurrentInstallation(_ record: DiaryEditRecord) throws {
    try requireAccess()
    guard record.installationBinding == (try currentInstallation()), record.stage != .quarantined
    else {
      throw DiaryEditIssue.reviewRequired
    }
  }

  static func issue(_ error: Error) -> DiaryEditIssue {
    if let issue = error as? DiaryEditIssue { return issue }
    switch error as? CatalogIssue {
    case .changed: return .changed
    case .conflict, .duplicateID: return .conflict
    case .unsafe, .unsupported, .malformed, .missingAudio, .missingMarkdown, .invalidAudio,
      .ambiguousAudio, .legacyFormatUnconfirmed:
      return .unsupported
    default: return .unavailable
    }
  }
}

// swiftlint:enable closure_parameter_position opening_brace
