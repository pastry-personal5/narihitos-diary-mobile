import SwiftUI
import UIKit

struct MainNoticeView: View {
  @ObservedObject var notices: MainNoticeModel
  let open: (CatalogRecoveryDestination) -> Void
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var voiceOver = UIAccessibility.isVoiceOverRunning
  @State private var visible = false

  var body: some View {
    Group {
      if let current = notices.current {
        Button {
          open(current.destination)
        } label: {
          HStack(spacing: 10) {
            InterfaceIcon(current.category == .recovery ? .warning : .pending)
            Text(verbatim: current.message).font(.subheadline).lineLimit(1)
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .padding(.horizontal, 16)
          .background(.bar)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(current.message)
        .accessibilityHint("Opens \(current.destination.rawValue)")
      }
    }
    .onAppear {
      visible = true
      updateEnvironment()
    }
    .onDisappear {
      visible = false
      updateEnvironment()
    }
    .onChange(of: scenePhase) { _, _ in updateEnvironment() }
    .onChange(of: reduceMotion) { _, _ in updateEnvironment() }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIAccessibility.voiceOverStatusDidChangeNotification)
    ) { _ in
      voiceOver = UIAccessibility.isVoiceOverRunning
      updateEnvironment()
    }
  }

  private func updateEnvironment() {
    notices.setEnvironment(
      visible: visible && scenePhase == .active, paused: voiceOver || reduceMotion)
  }
}

struct CatalogRecoveryAttentionView: View {
  @ObservedObject var catalog: CatalogModel
  let destination: CatalogRecoveryDestination

  var body: some View {
    List {
      if catalog.recovery.contains(where: { $0.destination == destination }) {
        Section {
          ForEach(catalog.recovery.filter { $0.destination == destination }) { item in
            Text(item.issue.message).frame(minHeight: 44, alignment: .leading)
          }
        } footer: {
          Text("These files have been preserved.")
        }
      } else {
        Text("No observed items need attention here.").foregroundStyle(.secondary)
      }
    }
    .navigationTitle(destination.rawValue)
  }
}
