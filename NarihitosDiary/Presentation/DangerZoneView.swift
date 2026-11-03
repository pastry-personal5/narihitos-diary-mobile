import SwiftUI

struct DangerZoneView: View {
  @ObservedObject var model: DangerZoneModel
  let folderName: String?
  var folderID: String?
  @Environment(\.scenePhase) private var scenePhase
  @AccessibilityFocusState private var focusedConfirmation: PurgeScope?

  var body: some View {
    Form {
      if model.blocksWork {
        Section("Processing Paused") {
          Text("An unfinished purge must be completed before recording or processing can resume.")
        }
      }
      ForEach(PurgeScope.allCases, id: \.self) { scope in
        Section(scope == .activeFolder ? "Active Folder" : "Internal Staging") {
          if scope == .activeFolder {
            LabeledContent("Active folder", value: folderName ?? "No folder selected")
              .privacySensitive()
          }
          Text(scope.warning).font(.callout)
          if let confirmation = model.confirmation, confirmation.transaction.scope == scope {
            Text("Confirm permanent removal")
              .font(.headline)
              .accessibilityFocused($focusedConfirmation, equals: scope)
            Button(role: .destructive) {
              Task { await model.confirm(confirmation.id) }
            } label: {
              Text(scope.title).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("purge-confirm-\(scope.rawValue)")
            .frame(minHeight: 44)
            Button(role: .cancel) {
              model.disarm()
            } label: {
              Text("Cancel").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("purge-cancel-\(scope.rawValue)")
          } else {
            Button(role: .destructive) {
              Task { await model.request(scope) }
            } label: {
              Text(scope.title).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("purge-request-\(scope.rawValue)")
            .disabled(
              model.confirmation != nil || (scope == .activeFolder && folderName == nil)
                || (model.recovery != nil && model.recovery?.scope != scope))
          }
        }
      }
      if model.isRunning {
        Section {
          ProgressView("Purging…")
          Text("Removed \(model.removedCount) items in this attempt.")
        }
      }
      if let message = model.message {
        Section("Result") {
          Text(message).accessibilityIdentifier("purge-result")
        }
      }
    }
    .disabled(model.isRunning)
    .navigationTitle("Danger Zone")
    .onDisappear { model.disarm() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { model.disarm() }
    }
    .onChange(of: folderName) { _, _ in model.disarm() }
    .onChange(of: folderID) { _, _ in model.disarm() }
    .onChange(of: model.confirmation) { _, confirmation in
      focusedConfirmation = confirmation?.transaction.scope
    }
    .task { model.reloadBarrier() }
  }
}
