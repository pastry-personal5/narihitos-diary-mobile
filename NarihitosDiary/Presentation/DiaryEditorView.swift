import SwiftUI

struct DiaryEditorView: View {
  @ObservedObject var editor: DiaryEditorModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var bodyFocused: Bool
  @State private var confirmsDiscard = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        if let issue = editor.issue {
          Text(issue.message).foregroundStyle(.secondary).padding(.horizontal)
        }
        if confirmsDiscard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Discard unsaved changes?")
            Button("Keep Editing") {
              confirmsDiscard = false
              bodyFocused = true
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("diary-keep-editing")
            Button("Discard Changes", role: .destructive) { dismiss() }.frame(minHeight: 44)
              .accessibilityIdentifier("diary-discard-edit")
          }
          .padding()
        }
        TextEditor(text: $editor.body)
          .font(.body)
          .focused($bodyFocused)
          .disabled(editor.locksBody)
          .accessibilityLabel("Diary body")
          .accessibilityIdentifier("diary-body-editor")
          .padding(.horizontal, 12)
      }
      .navigationTitle("Edit Diary")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            if editor.dirty {
              confirmsDiscard = true
              bodyFocused = false
            } else {
              dismiss()
            }
          }
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityIdentifier("diary-cancel-edit")
          .disabled(editor.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(editor.isSaving ? "Saving…" : "Save") {
            bodyFocused = false
            Task {
              await Task.yield()
              await editor.save()
            }
          }
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityIdentifier("diary-save-body")
          .disabled(editor.isSaving)
        }
      }
      .interactiveDismissDisabled(editor.dirty || editor.isSaving)
      .task { bodyFocused = true }
      .onChange(of: scenePhase) { _, phase in if phase != .active { bodyFocused = false } }
      .privacySensitive()
      .disabled(scenePhase != .active)
      .accessibilityHidden(scenePhase != .active)
      .overlay { if scenePhase != .active { PrivacyCover() } }
    }
  }
}

struct DiaryEditorPresentation: ViewModifier {
  @ObservedObject var actions: DiaryActionsModel

  func body(content: Content) -> some View {
    content.sheet(item: $actions.editor) { editor in DiaryEditorView(editor: editor) }
  }
}
