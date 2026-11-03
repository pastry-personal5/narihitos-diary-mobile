import Combine
import Foundation

@MainActor
final class DiaryEditorModel: ObservableObject, Identifiable {
  let id = UUID()
  let session: DiaryEditSession
  let original: String
  @Published var body: String
  @Published private(set) var isSaving = false
  @Published private(set) var issue: DiaryEditIssue?
  private var submission: DiaryEditSubmission?
  private let edits: DiaryEditCoordinator
  private let accepted: @MainActor () -> Void

  init(
    session: DiaryEditSession, edits: DiaryEditCoordinator,
    accepted: @escaping @MainActor () -> Void
  ) {
    self.session = session
    self.edits = edits
    self.accepted = accepted
    original = session.snippet.body.text
    body = original
  }

  var dirty: Bool { body != original }
  var locksBody: Bool { isSaving || submission != nil }

  func save() async {
    guard !isSaving else { return }
    guard body.utf8.count <= DiaryBody.maximumBytes else {
      issue = .invalidCandidate
      return
    }
    if submission == nil {
      submission = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .body(body))
    }
    guard let submission else { return }
    isSaving = true
    issue = nil
    defer { isSaving = false }
    switch await edits.submit(submission, session: session) {
    case .accepted, .unchanged: accepted()
    case .rejected(let issue):
      self.issue = issue
      self.submission = nil
    case .uncertain(let issue):
      self.issue = issue
    // An unreadable acknowledgement is not proof that no journal committed.
    // Retry this exact value/identity until acceptance can be reconciled.
    }
  }
}

@MainActor
final class DiaryActionsModel: ObservableObject {
  private struct FavoriteRequest {
    let handle: CatalogItemHandle
    let session: DiaryEditSession
    let submission: DiaryEditSubmission
  }
  @Published var editor: DiaryEditorModel? {
    didSet {
      if let oldValue, oldValue.id != editor?.id { edits?.closeSession(oldValue.session.id) }
    }
  }
  @Published private(set) var revision = 0
  @Published private(set) var isOpening = false
  @Published private(set) var message: String?
  @Published private(set) var deletionConfirmation: CatalogItemHandle?
  @Published private(set) var isDeleting = false
  @Published private(set) var deletionMessage: String?
  private var deletion: (any DiaryDeletionPort)?
  private var didDelete: (@MainActor () -> Void)?
  private(set) var edits: DiaryEditCoordinator?
  private(set) var replay: DiaryReplayCoordinator?
  private var openGeneration = UUID()
  private var destinationID: String?
  private var pendingFavorite: FavoriteRequest?
  private var visibleHandle: CatalogItemHandle?

  func configure(
    edits: DiaryEditCoordinator, replay: DiaryReplayCoordinator,
    changed: @escaping @MainActor () -> Void
  ) {
    self.edits = edits
    self.replay = replay
    edits.onChange = { [weak self] in
      self?.revision += 1
      changed()
    }
    replay.onChange = { [weak self] in self?.revision += 1 }
  }

  func openEditor(_ handle: CatalogItemHandle) async {
    guard let edits, !isOpening, !isDeleting, editor == nil, visibleHandle == handle else { return }
    cancelDeletion()
    isOpening = true
    message = nil
    let generation = openGeneration
    defer { isOpening = false }
    do {
      let session = try await edits.open(handle)
      guard generation == openGeneration else {
        edits.closeSession(session.id)
        return
      }
      editor = DiaryEditorModel(session: session, edits: edits) { [weak self] in self?.editor = nil
      }
    } catch {
      if generation == openGeneration {
        message = ((error as? DiaryEditIssue) ?? .unavailable).message
      }
    }
  }

  func setFavorite(_ desired: Bool, handle: CatalogItemHandle) async {
    guard let edits, !isOpening, !isDeleting, editor == nil, visibleHandle == handle else { return }
    cancelDeletion()
    isOpening = true
    message = nil
    let generation = openGeneration
    defer { isOpening = false }
    do {
      if let pendingFavorite, pendingFavorite.handle != handle { throw DiaryEditIssue.busy }
      let session: DiaryEditSession
      let intent: DiaryEditSubmission
      if let pendingFavorite {
        session = pendingFavorite.session
        intent = pendingFavorite.submission
      } else {
        session = try await edits.open(handle)
        intent = DiaryEditSubmission(id: UUID(), sessionID: session.id, change: .favorite(desired))
        pendingFavorite = FavoriteRequest(handle: handle, session: session, submission: intent)
      }
      guard generation == openGeneration else {
        pendingFavorite = nil
        edits.closeSession(session.id)
        return
      }
      switch await edits.submit(intent, session: session) {
      case .accepted, .unchanged:
        pendingFavorite = nil
        edits.closeSession(session.id)
      case .rejected(let issue):
        pendingFavorite = nil
        edits.closeSession(session.id)
        message = issue.message
      case .uncertain(let issue): message = issue.message
      }
    } catch {
      if generation == openGeneration {
        message = ((error as? DiaryEditIssue) ?? .unavailable).message
      }
    }
  }

  func invalidateVisibleActions() {
    cancelDeletion()
    openGeneration = UUID()
    message = nil
    if let pendingFavorite { edits?.closeSession(pendingFavorite.session.id) }
    pendingFavorite = nil
    visibleHandle = nil
    replay?.setVisibleItem(nil)
    // The editor owns its buffer independently of catalog/navigation lifetime.
    replay?.deactivate()
  }

  func activate() { replay?.activate() }

  func showDetail(_ handle: CatalogItemHandle) {
    if visibleHandle != handle {
      cancelDeletion()
      openGeneration = UUID()
      message = nil
    }
    visibleHandle = handle
    replay?.setVisibleItem(handle)
  }

  func hideDetail(_ handle: CatalogItemHandle) {
    guard visibleHandle == handle else { return }
    cancelDeletion()
    visibleHandle = nil
    openGeneration = UUID()
    replay?.setVisibleItem(nil)
  }

  func updateScope(_ id: DestinationID?) { destinationID = id?.rawValue }

  func configureDeletion(
    _ deletion: any DiaryDeletionPort, didDelete: @escaping @MainActor () -> Void
  ) {
    self.deletion = deletion
    self.didDelete = didDelete
  }

  var canDelete: Bool {
    deletion != nil && edits != nil && !isOpening && editor == nil && !isDeleting
  }

  func requestDeletion(_ handle: CatalogItemHandle) {
    guard canDelete, visibleHandle == handle else { return }
    deletionMessage = nil
    deletionConfirmation = handle
  }

  func cancelDeletion() {
    deletionConfirmation = nil
    deletionMessage = nil
  }

  func confirmDeletion(_ handle: CatalogItemHandle) async {
    guard deletionConfirmation == handle, visibleHandle == handle, canDelete,
      let deletion, let edits
    else { return }
    deletionConfirmation = nil
    deletionMessage = nil
    guard edits.beginDeletion() else {
      deletionMessage = DiaryDeletionIssue.busy.message
      return
    }
    isDeleting = true
    let generation = openGeneration
    defer {
      isDeleting = false
      edits.endDeletion()
    }
    await replay?.stop(for: handle)
    guard generation == openGeneration, visibleHandle == handle else { return }
    do {
      try await deletion.delete(handle)
      didDelete?()
    } catch {
      if generation == openGeneration, visibleHandle == handle {
        deletionMessage = ((error as? DiaryDeletionIssue) ?? .unavailable).message
      }
    }
  }

  func pending(assetID: String) -> DiaryEditRecord? {
    _ = revision
    return edits?.pending.first { $0.assetID == assetID && $0.destinationID == destinationID }
  }
}
