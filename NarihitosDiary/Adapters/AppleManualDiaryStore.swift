// swift-format wraps multiline declarations and collections.
// swiftlint:disable opening_brace
import Foundation
import UIKit

@MainActor
final class AppleManualDiaryStore: ManualDiaryStorePort {
  let journal: ManualDiaryJournal
  private let destination: AppleDestinationService
  private let installation: any InstallationIdentityPort
  private let observer: any DiaryFileObserverPort
  private let protectedDataAvailable: () -> Bool

  init(
    destination: AppleDestinationService, installation: any InstallationIdentityPort,
    root: URL? = nil, protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver(),
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
  ) {
    self.destination = destination
    self.installation = installation
    self.observer = observer
    self.protectedDataAvailable = protectedDataAvailable
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    journal = ManualDiaryJournal(
      files: DiaryEditPrivateFiles(
        root: root ?? support.appending(path: "NarihitosDiary/PrivateWorkspaces/ManualDiaries"),
        protection: protection))
  }

  private func identity() throws -> String {
    guard protectedDataAvailable(), case .available(let binding) = installation.currentOrCreate()
    else {
      throw DiaryEditIssue.localData
    }
    return binding
  }

  func accept(_ submission: ManualDiarySubmission) async throws -> ManualDiaryRecord {
    let identity = try identity()
    if let completed = try await journal.completion(submission.id, installation: identity) {
      guard completed.submissionDigest == ManualDiaryJournal.digest(submission) else {
        throw DiaryEditIssue.submissionMismatch
      }
      return completed.record
    }
    // Reconcile an uncertain acceptance before resolving today's selected folder.
    if let prior = try? await journal.envelope(submission.id, installation: identity) {
      guard prior.submissionDigest == ManualDiaryJournal.digest(submission) else {
        throw DiaryEditIssue.submissionMismatch
      }
      return prior.record
    }
    let stored = try await destination.committedDestinationRecord()
    let rootIdentity = try await destination.withCommittedDestination(stored) { root in
      try await Task.detached(priority: .utility) { try CommittedDiaryResource.rootIdentity(root) }
        .value
    }
    return try await journal.accept(
      submission, destination: stored, rootIdentity: rootIdentity, installation: identity)
  }

  func inventory() async throws -> [ManualDiaryRecord] {
    try await journal.inventory(installation: identity())
  }

  func body(_ record: ManualDiaryRecord) async throws -> DiaryBody {
    let envelope = try await journal.envelope(record.id, installation: identity())
    guard case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(envelope.markdown)
    else {
      throw DiaryEditIssue.invalidCandidate
    }
    return snippet.body
  }

  func finalize(_ record: ManualDiaryRecord, title: GeneratedDiaryTitle) async throws
    -> ManualDiaryRecord
  {
    try await journal.finalize(record.id, installation: identity(), title: title)
  }

  func publish(_ record: ManualDiaryRecord) async throws -> Bool {
    let identity = try identity()
    if try await journal.retireCompleted(record.id, installation: identity) { return true }
    let envelope = try await journal.envelope(record.id, installation: identity)
    if envelope.completed {
      try await journal.complete(record.id, installation: identity)
      return true
    }
    let observer = observer
    let files = journal.files
    let complete = try await destination.withCommittedDestination(envelope.destination) { root in
      try await ManualDiaryPublication.publish(
        envelope, root: root, files: files, observer: observer)
    }
    if complete { try await journal.complete(record.id, installation: identity) }
    return complete
  }
}

// swiftlint:enable opening_brace
