import SwiftUI

@MainActor
final class ManualDiaryEditorModel: ObservableObject, Identifiable {
  let id = UUID()
  @Published var body = ""
  @Published private(set) var isSaving = false
  @Published private(set) var message: String?
  @Published private(set) var submission: ManualDiarySubmission?
  private let creation: ManualDiaryCreation
  private let now: () -> Date
  var onAccepted: (() -> Void)?

  init(creation: ManualDiaryCreation, now: @escaping () -> Date = Date.init) {
    self.creation = creation
    self.now = now
  }

  var dirty: Bool { !body.isEmpty }
  var canSave: Bool {
    !isSaving && (!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      && body.utf8.count <= DiaryBody.maximumBytes
  }

  func save() async {
    guard canSave else { return }
    isSaving = true
    defer { isSaving = false }
    if submission == nil {
      submission = ManualDiarySubmission(id: id, createdAt: now(), body: body)
    }
    guard let submission else { return }
    do {
      try await creation.submit(submission)
      message = nil
      onAccepted?()
    } catch {
      if let issue = error as? DiaryEditIssue {
        message =
          issue.manualCreationMessage
      } else {
        message = "Your text is still here. Check your iCloud folder, then try Save again."
      }
    }
  }
}

struct ManualDiaryEditorView: View {
  @ObservedObject var editor: ManualDiaryEditorModel
  var cancel: () -> Void
  var chooseFolder: () -> Void
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var bodyFocused: Bool
  @State private var confirmsDiscard = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        if let message = editor.message {
          Text(message).foregroundStyle(.secondary).padding(.horizontal)
          Button("Choose iCloud Folder", action: chooseFolder)
            .frame(minHeight: 44).padding(.horizontal).disabled(editor.isSaving)
        }
        if editor.body.utf8.count > DiaryBody.maximumBytes {
          Text("The diary exceeds the supported text limit.").foregroundStyle(.secondary).padding(
            .horizontal)
        }
        if confirmsDiscard {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              Text(
                editor.submission == nil
                  ? "Discard this unsaved diary?" : "Leave this Save request?"
              )
              .font(.headline).fixedSize(horizontal: false, vertical: true)
              if editor.submission != nil {
                Text("If Save was already accepted, its submitted text will still be saved.")
              }
              Button("Keep Writing") {
                confirmsDiscard = false
                bodyFocused = true
              }.frame(minHeight: 44)
              Button("Discard Changes", role: .destructive, action: cancel).frame(minHeight: 44)
                .accessibilityIdentifier("manual-diary-discard")
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          TextEditor(text: $editor.body)
            .font(.body).focused($bodyFocused)
            .disabled(editor.submission != nil)
            .accessibilityLabel("Diary body")
            .accessibilityIdentifier("manual-diary-body")
            .padding(.horizontal, 12)
        }
      }
      .navigationTitle("Write Diary Snippet")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            if editor.dirty {
              confirmsDiscard = true
              bodyFocused = false
            } else {
              cancel()
            }
          } label: {
            InterfaceIcon(.cancel).frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .accessibilityLabel("Cancel").accessibilityIdentifier("manual-diary-cancel")
          .disabled(editor.isSaving)
          Button {
            bodyFocused = false
            Task {
              await Task.yield()
              await editor.save()
            }
          } label: {
            InterfaceIcon(.save).frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .tint(.accentColor)
          .accessibilityLabel("Save").accessibilityIdentifier("manual-diary-save")
          .accessibilityValue(editor.isSaving ? "Saving" : "")
          .disabled(!editor.canSave)
        }
      }
      .interactiveDismissDisabled(editor.dirty || editor.isSaving)
      .task { bodyFocused = editor.submission == nil }
      .onChange(of: scenePhase) { _, phase in if phase != .active { bodyFocused = false } }
      .privacySensitive()
      .disabled(scenePhase != .active)
      .accessibilityHidden(scenePhase != .active)
      .overlay { if scenePhase != .active { PrivacyCover() } }
    }
  }
}

struct ManualDiaryPendingView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    List {
      if let issue = model.manualDiaryIssue { Text(issue) }
      ForEach(model.manualDiaryPending) { record in
        VStack(alignment: .leading, spacing: 8) {
          Text("Written Diary Snippet").font(.headline)
          Text(SafeFolderDisplayName.project(record.folderName)).foregroundStyle(.secondary)
          Text(record.issue?.manualCreationMessage ?? "Saving diary text.")
          Button("Retry") { model.retryManualDiaries() }.frame(minHeight: 44)
            .disabled(record.issue?.canRetryAutomatically == false)
        }
      }
    }
    .navigationTitle("Pending Diary Snippets")
    .overlay {
      if model.manualDiaryPending.isEmpty && model.manualDiaryIssue == nil {
        ContentUnavailableView("No Pending Diary Snippets", systemImage: "text.book.closed")
      }
    }
  }
}
