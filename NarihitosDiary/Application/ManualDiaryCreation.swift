// swiftlint:disable opening_brace
import Foundation

struct ManualDiarySubmission: Equatable, Sendable {
  let id: UUID
  let createdAt: Date
  let body: String
}

struct ManualDiaryRecord: Equatable, Sendable, Identifiable {
  let id: UUID
  let destinationID: String
  let folderName: String
  var needsTitle: Bool
  var issue: DiaryEditIssue?
  var completed = false

  var assetID: String { id.uuidString.lowercased() }
}

@MainActor
protocol ManualDiaryStorePort: AnyObject {
  func accept(_ submission: ManualDiarySubmission) async throws -> ManualDiaryRecord
  func inventory() async throws -> [ManualDiaryRecord]
  func body(_ record: ManualDiaryRecord) async throws -> DiaryBody
  func finalize(_ record: ManualDiaryRecord, title: GeneratedDiaryTitle) async throws
    -> ManualDiaryRecord
  /// `context` is the already-sealed snapshot; nil means omission.
  func finalize(_ record: ManualDiaryRecord, title: GeneratedDiaryTitle, context: ContextSnapshot?)
    async throws -> ManualDiaryRecord
  /// True only after the exact Markdown version has verified upload and local cleanup.
  func publish(_ record: ManualDiaryRecord) async throws -> Bool
}

extension ManualDiaryStorePort {
  func finalize(_ record: ManualDiaryRecord, title: GeneratedDiaryTitle, context: ContextSnapshot?)
    async throws -> ManualDiaryRecord
  { try await finalize(record, title: title) }
}

/// Manual creation owns submissions independently of audio capture and edit sessions.
/// Durable acceptance is the editor's acknowledgment; upload remains foreground work.
@MainActor
final class ManualDiaryCreation {
  private let store: any ManualDiaryStorePort
  private let titles: DiaryTitlePolicy
  private var work: Task<Void, Never>?
  private var retry: Task<Void, Never>?
  private var active = false
  private var suspended = false
  private var discovered = false
  private var accepting: Set<UUID> = []
  private var retryIndex = 0
  private(set) var pending: [ManualDiaryRecord] = []
  private(set) var discoveryIssue: DiaryEditIssue?
  var onChange: (() -> Void)?
  var onSaved: ((ManualDiaryRecord) -> Void)?
  /// The first Save is the context instant. Acquisition never delays acknowledgment.
  var beginContext: ((ManualDiarySubmission) -> Void)?
  /// Synchronously seals what was accepted, evaluated after the title await.
  var sealContext: ((ManualDiaryRecord) -> ContextSnapshot?)?

  init(store: any ManualDiaryStorePort, titles: DiaryTitlePolicy) {
    self.store = store
    self.titles = titles
  }

  var isObserved: Bool { discovered && discoveryIssue == nil }

  var hasActiveWork: Bool { work != nil || !accepting.isEmpty || titles.hasActiveWork }

  func isSettled(_ assetID: String) -> Bool {
    discovered && discoveryIssue == nil
      && !accepting.contains(where: { $0.uuidString.lowercased() == assetID })
      && !pending.contains(where: { $0.assetID == assetID })
  }

  func activate() {
    guard !suspended else { return }
    active = true
    retry?.cancel()
    retry = nil
    retryIndex = 0
    discovered = false
    pump()
  }

  func deactivate() {
    active = false
    retry?.cancel()
    retry = nil
  }

  func suspendForMaintenance() {
    suspended = true
    deactivate()
  }

  func endMaintenance() {
    guard !hasActiveWork else { return }
    suspended = false
    discovered = false
    pending = []
    discoveryIssue = nil
  }

  func submit(_ submission: ManualDiarySubmission) async throws {
    if let work { await work.value }
    guard active, !suspended, !accepting.contains(submission.id) else { throw DiaryEditIssue.busy }
    guard !submission.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      submission.body.utf8.count <= DiaryBody.maximumBytes
    else { throw DiaryEditIssue.invalidCandidate }
    accepting.insert(submission.id)
    defer {
      accepting.remove(submission.id)
      pump()
    }
    do {
      let record = try await store.accept(submission)
      beginContext?(submission)
      pending.removeAll { $0.id == record.id }
      pending.append(record)
      onChange?()
    } catch {
      // Acceptance may have reached disk before its acknowledgment failed.
      discovered = false
      throw error
    }
  }

  private func pump() {
    guard active, !suspended, work == nil, accepting.isEmpty else { return }
    work = Task { [self] in
      if !discovered {
        do {
          pending = try await store.inventory()
          discovered = true
          discoveryIssue = nil
        } catch { discoveryIssue = (error as? DiaryEditIssue) ?? .localData }
        onChange?()
      }
      if discovered {
        for initial in pending {
          guard active, !suspended else { break }
          guard initial.issue?.canRetryAutomatically != false else { continue }
          await process(initial)
          onChange?()
        }
      }
      work = nil
      scheduleRetry()
    }
  }

  private func process(_ initial: ManualDiaryRecord) async {
    var record = initial
    do {
      if record.needsTitle {
        let body = try await store.body(record)
        let title = await titles.title(for: body, owner: .manual(submissionID: record.id))
        record = try await store.finalize(
          record, title: title, context: sealContext?(record))
      }
      guard active, !suspended else {
        update(record)
        return
      }
      if try await store.publish(record) {
        pending.removeAll { $0.id == record.id }
        onSaved?(record)
      } else {
        record.issue = .upload
        update(record)
      }
    } catch {
      record.issue = (error as? DiaryEditIssue) ?? .unavailable
      update(record)
    }
  }

  private func update(_ record: ManualDiaryRecord) {
    pending.removeAll { $0.id == record.id }
    pending.append(record)
  }

  private func scheduleRetry() {
    guard active, !suspended,
      !discovered || discoveryIssue != nil
        || pending.contains(where: { $0.issue?.canRetryAutomatically != false })
    else { return }
    let delays = [2, 5, 15, 30, 60]
    let seconds = delays[min(retryIndex, delays.count - 1)]
    retryIndex += 1
    retry = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      self?.retry = nil
      self?.pump()
    }
  }
}

extension DiaryEditIssue {
  var manualCreationMessage: String {
    switch self {
    case .localData: "Diary text is waiting for protected local data."
    case .storage:
      "The save status couldn’t be verified. Your submitted text has been kept. Try Save again."
    case .reviewRequired: "Submitted diary text was restored and needs review before saving."
    case .invalidCandidate: "The diary exceeds the supported text limit."
    default: message
    }
  }
}

// swiftlint:enable opening_brace
