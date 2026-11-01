import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = AppModel()

  var body: some View {
    ZStack {
      TabView {
        MainView(model: model)
          .tabItem { Label("Main", systemImage: "house") }
        EmptyRootView(message: "Benefits are coming later.")
          .tabItem { Label("Benefits", systemImage: "sparkles") }
        EmptyRootView(message: "Calendar is coming later.")
          .tabItem { Label("Calendar", systemImage: "calendar") }
        EmptyRootView(message: "Plugins are coming later.")
          .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        AllView(model: model)
          .tabItem { Label("All", systemImage: "square.grid.2x2") }
      }
      .disabled(scenePhase != .active)
      .accessibilityHidden(scenePhase != .active)

      if scenePhase != .active {
        PrivacyCover()
          .transition(.identity)
          .zIndex(100)
      }
    }
    .animation(nil, value: scenePhase)
    .task { await model.becameActive() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.becameActive() }
      } else {
        model.becameInactive()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
      Task { await model.identityChanged() }
    }
    .sheet(isPresented: $model.isFolderPickerPresented) {
      FolderPicker(onPick: model.pickedFolder, onCancel: model.cancelFolderPicker)
    }
    .alert(
      firstLaunchTitle,
      isPresented: firstLaunchPresented,
      presenting: model.firstLaunchStep
    ) { _ in
      Button("Continue") { Task { await model.continueFirstLaunch() } }
    } message: { step in
      Text(firstLaunchMessage(for: step))
    }
    .alert(
      "Readable Files",
      isPresented: model.disclosurePresented,
      presenting: model.preparedDestination
    ) { _ in
      Button("Cancel", role: .cancel, action: model.cancelDisclosure)
      Button("Use Folder", action: model.acceptDisclosure)
    } message: { _ in
      Text(
        "Diary text, audio, and optional exact location are readable files. "
          + "Anyone with access to this folder may read them."
      )
    }
    .alert("Narihito's Diary", isPresented: messagePresented) {
      if model.offersSettingsRecovery {
        Button("Open Settings", action: model.openSettings)
      }
      Button("OK", role: .cancel, action: model.clearMessage)
    } message: {
      Text(model.message ?? "")
    }
  }

  private var firstLaunchPresented: Binding<Bool> {
    Binding(get: { model.firstLaunchStep != nil }, set: { _ in })
  }

  private var messagePresented: Binding<Bool> {
    Binding(
      get: { model.message != nil },
      set: { if !$0 { model.clearMessage() } })
  }

  private var firstLaunchTitle: String {
    model.firstLaunchStep == .location ? "Optional Location" : "Microphone Access"
  }

  private func firstLaunchMessage(for step: FirstLaunchStep) -> String {
    switch step {
    case .microphone:
      "Allow microphone access to record diary audio. If you decline, the rest of the app remains available."
    case .location:
      "Optionally allow location while using the app to add recording-time place and weather "
        + "context. Recording works without it."
    case .complete:
      ""
    }
  }
}

private struct MainView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "No Diary Snippets",
        systemImage: "book.closed",
        description: Text("Diary Snippets in your active folder will appear here.")
      )
      .navigationTitle("Main")
      .safeAreaInset(edge: .bottom) {
        HStack {
          Spacer()
          Button {
            Task { await model.handleRecord() }
          } label: {
            Label("Record", systemImage: "mic.fill")
              .font(.headline)
              .padding()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .accessibilityLabel("Record")
          Spacer()
        }
        .padding(.bottom, 8)
      }
    }
  }
}

private struct EmptyRootView: View {
  let message: String

  var body: some View {
    ContentUnavailableView(message, systemImage: "hourglass")
  }
}

private struct AllView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    NavigationStack {
      List {
        placeholder("Pending Recordings")
        placeholder("Failed Recordings")
        placeholder("Incomplete Diary Snippets")
        placeholder("Conflicting Versions")
        NavigationLink("Settings") { SettingsView(model: model) }
          .accessibilityLabel("Settings")
      }
      .navigationTitle("All")
    }
  }

  private func placeholder(_ title: String) -> some View {
    NavigationLink(title) {
      ContentUnavailableView("Coming Later", systemImage: "hourglass")
        .navigationTitle(title)
    }
  }
}

private struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section("Active Folder") {
        Text(model.destination.summary?.displayName ?? "No folder selected")
          .lineLimit(1)
          .privacySensitive()
          .accessibilityLabel("Active folder")
          .accessibilityValue(model.destination.summary?.displayName ?? "No folder selected")
        Button(model.destination.summary == nil ? "Select Folder" : "Change Folder") {
          model.selectFolder()
        }
        .frame(minHeight: 44)
      }
      Section("Location") {
        LabeledContent("Access", value: locationLabel)
        if model.locationState == .notDetermined {
          Button("Allow Location Access") { Task { await model.requestLocation() } }
            .frame(minHeight: 44)
        } else if model.locationState == .denied || model.locationState == .restricted {
          Button("Open Settings", action: model.openSettings)
            .frame(minHeight: 44)
        }
      }
    }
    .navigationTitle("Settings")
    .task { await model.becameActive() }
  }

  private var locationLabel: String {
    switch model.locationState {
    case .notDetermined: "Not Requested"
    case .authorized: "Allowed"
    case .denied: "Denied"
    case .restricted: "Restricted"
    }
  }
}

private struct PrivacyCover: View {
  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      Image(systemName: "book.closed")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .accessibilityLabel("Narihito's Diary hidden while inactive")
  }
}
