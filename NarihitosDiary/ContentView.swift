import SwiftUI

// swiftlint:disable file_length

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = AppModel()

  var body: some View {
    ZStack {
      TabView(selection: $model.selectedRoot) {
        MainView(model: model)
          .tabItem {
            Label {
              Text("Main")
            } icon: {
              InterfaceIcon(.main, selected: model.selectedRoot == .main)
            }
          }
          .tag(RootTab.main)
        EmptyRootView(message: "Benefits are coming later.")
          .tabItem {
            Label {
              Text("Benefits")
            } icon: {
              InterfaceIcon(.benefits, selected: model.selectedRoot == .benefits)
            }
          }
          .tag(RootTab.benefits)
        EmptyRootView(message: "Calendar is coming later.")
          .tabItem {
            Label {
              Text("Calendar")
            } icon: {
              InterfaceIcon(.calendar, selected: model.selectedRoot == .calendar)
            }
          }
          .tag(RootTab.calendar)
        EmptyRootView(message: "Plugins are coming later.")
          .tabItem {
            Label {
              Text("Plugins")
            } icon: {
              InterfaceIcon(.plugins, selected: model.selectedRoot == .plugins)
            }
          }
          .tag(RootTab.plugins)
        AllView(model: model)
          .tabItem {
            Label {
              Text("All")
            } icon: {
              InterfaceIcon(.all, selected: model.selectedRoot == .all)
            }
          }
          .tag(RootTab.all)
      }
      .disabled(scenePhase != .active)
      .accessibilityHidden(scenePhase != .active)

      if scenePhase != .active {
        PrivacyCover()
          .transition(.identity)
          .zIndex(100)
      }
    }
    .safeAreaInset(edge: .top) {
      if scenePhase == .active, let banner = model.savedFolderBanner {
        HStack(spacing: 12) {
          Text(verbatim: banner).font(.subheadline)
          Spacer()
          Button("Dismiss", action: model.dismissSavedFolderBanner).frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial)
      }
    }
    .animation(nil, value: scenePhase)
    .onChange(of: model.selectedRoot) { _, root in model.catalog.setVisible(root == .main) }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    ) { _ in
      model.catalog.discard()
    }
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
    .fullScreenCover(isPresented: $model.isCapturePresented) {
      RecordingView(model: model)
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
      if model.offersPendingReview {
        Button("Review Pending Recordings", action: model.reviewPendingRecordings)
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
      CatalogCollectionView(
        catalog: model.catalog, openAll: model.openAll, renderers: model.catalogRenderers
      )
      .safeAreaInset(edge: .top) {
        MainNoticeView(notices: model.notices, open: model.openRecovery)
      }
      .onAppear { model.catalog.setVisible(model.selectedRoot == .main) }
      .navigationTitle("Main")
      .safeAreaInset(edge: .bottom) {
        HStack {
          Spacer()
          recordButton(
            language: .english, shortLabel: "en", accessibilityLabel: "Record in English",
            backgroundColor: Color(red: 0.08, green: 0.35, blue: 0.70))
          recordButton(
            language: .korean, shortLabel: "ko", accessibilityLabel: "Record in Korean",
            backgroundColor: Color(red: 0.39, green: 0.21, blue: 0.62))
        }
        .padding(.trailing, 20)
        .padding(.bottom, 8)
      }
    }
  }

  private func recordButton(
    language: CaptureLanguage, shortLabel: String, accessibilityLabel: String,
    backgroundColor: Color
  ) -> some View {
    Button {
      Task { await model.handleRecord(language: language) }
    } label: {
      VStack(spacing: 0) {
        InterfaceIcon(.record)
        Text(shortLabel)
          .font(.system(size: 11, weight: .bold))
      }
      .foregroundStyle(.white)
      .frame(width: 56, height: 56)
      .background(backgroundColor, in: Circle())
      .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
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
        NavigationLink("Pending Recordings") {
          CaptureListView(
            title: "Pending Recordings", captures: model.pendingCaptures,
            queueEntries: model.queuePending, pausedReason: model.queuePausedReason,
            onRetry: model.retryQueueJob, onResume: model.resumeQueueJob,
            onRemove: model.removeQueueJob, onChooseMethod: model.chooseMethodForRecovery)
        }
        NavigationLink("Failed Recordings") {
          CaptureListView(
            title: "Failed Recordings", captures: model.failedCaptures,
            issues: model.captureIssues, queueEntries: model.queueFailed,
            pausedReason: model.queuePausedReason, showFailureReason: true,
            onRetry: model.retryQueueJob, onResume: model.resumeQueueJob,
            onRemove: model.removeQueueJob, onChooseMethod: model.chooseMethodForRecovery)
        }
        NavigationLink {
          CatalogRecoveryAttentionView(catalog: model.catalog, destination: .incomplete)
        } label: {
          Label {
            Text("Incomplete Diary Snippets")
          } icon: {
            InterfaceIcon(.incomplete)
          }
        }
        NavigationLink {
          CatalogRecoveryAttentionView(catalog: model.catalog, destination: .conflicts)
        } label: {
          Label {
            Text("Conflicting Versions")
          } icon: {
            InterfaceIcon(.conflicts)
          }
        }
        NavigationLink {
          SettingsView(model: model)
        } label: {
          Label {
            Text("Settings")
          } icon: {
            InterfaceIcon(.settings)
          }
        }
        .accessibilityLabel("Settings")
      }
      .navigationTitle("All")
      .navigationDestination(item: $model.recoveryRoute) { destination in
        recoveryDestination(destination)
      }
      .navigationDestination(isPresented: $model.showSettings) { SettingsView(model: model) }
      .navigationDestination(isPresented: $model.showPendingRecordings) {
        CaptureListView(
          title: "Pending Recordings", captures: model.pendingCaptures,
          queueEntries: model.queuePending, pausedReason: model.queuePausedReason,
          onRetry: model.retryQueueJob, onResume: model.resumeQueueJob,
          onRemove: model.removeQueueJob, onChooseMethod: model.chooseMethodForRecovery)
      }
    }
  }

  @ViewBuilder
  private func recoveryDestination(_ destination: CatalogRecoveryDestination) -> some View {
    switch destination {
    case .pending:
      CaptureListView(
        title: destination.rawValue, captures: model.pendingCaptures,
        queueEntries: model.queuePending, pausedReason: model.queuePausedReason,
        onRetry: model.retryQueueJob, onResume: model.resumeQueueJob,
        onRemove: model.removeQueueJob, onChooseMethod: model.chooseMethodForRecovery)
    case .failed:
      CaptureListView(
        title: destination.rawValue, captures: model.failedCaptures, issues: model.captureIssues,
        queueEntries: model.queueFailed, pausedReason: model.queuePausedReason,
        showFailureReason: true, onRetry: model.retryQueueJob, onResume: model.resumeQueueJob,
        onRemove: model.removeQueueJob, onChooseMethod: model.chooseMethodForRecovery)
    case .incomplete, .conflicts:
      CatalogRecoveryAttentionView(catalog: model.catalog, destination: destination)
    }
  }

}

private struct RecordingView: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var model: AppModel

  var body: some View {
    ZStack {
      VStack(spacing: 24) {
        Spacer()
        Text("Recording")
          .font(.largeTitle.bold())
        Text(Duration.seconds(model.captureElapsed).formatted(.time(pattern: .minuteSecond)))
          .font(.system(.largeTitle, design: .monospaced))
          .accessibilityLabel("Elapsed recording time")
        ProgressView(value: model.captureLevel)
          .accessibilityLabel("Recording level")
          .padding(.horizontal, 40)
        Spacer()
        Button {
          model.stopCapture()
        } label: {
          Label {
            Text("Stop & Transcribe")
          } icon: {
            InterfaceIcon(.stop)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.bottom, 40)
      }
      .accessibilityHidden(scenePhase != .active)
      if scenePhase != .active {
        PrivacyCover()
          .zIndex(100)
      }
    }
    .interactiveDismissDisabled()
    .animation(nil, value: scenePhase)
  }
}

private struct CaptureListView: View {
  @State private var removalCandidate: String?
  let title: String
  let captures: [CaptureIdentity]
  var issues: [CaptureRecoveryIssue] = []
  var queueEntries: [QueueProjection] = []
  var pausedReason: String?
  var showFailureReason = false
  var onRetry: (String) -> Void = { _ in }
  var onResume: (String) -> Void = { _ in }
  var onRemove: (String) -> Void = { _ in }
  var onChooseMethod: (CaptureLanguage) -> Void = { _ in }

  var body: some View {
    List {
      ForEach(captures, id: \.id) { capture in
        VStack(alignment: .leading) {
          Text(capture.startedAt.formatted(date: .abbreviated, time: .shortened))
          Text(capture.language == .english ? "English" : "Korean")
            .foregroundStyle(.secondary)
          if showFailureReason {
            Text("This recording can’t be read.")
              .foregroundStyle(.secondary)
          }
        }
      }
      ForEach(queueEntries) { entry in
        VStack(alignment: .leading, spacing: 6) {
          Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
          Text(entry.language == .english ? "English" : "Korean")
            .foregroundStyle(.secondary)
          if let reason = entry.reason {
            Text(reason).foregroundStyle(.secondary)
          }
          if entry.state == .reviewRequired {
            Button("Resume") { onResume(entry.id) }
          } else if entry.state == .failed {
            Button("Retry") { onRetry(entry.id) }
          } else if entry.state == .waiting {
            Button("Choose Method") { onChooseMethod(entry.language) }
          } else if entry.state == .readyToSave, entry.reason != nil {
            Button("Retry Verification") { onRetry(entry.id) }
          }
          if entry.state != .cancelling {
            Button("Remove", role: .destructive) { removalCandidate = entry.id }
          } else {
            Text("Cancelling").foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .contain)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !issues.isEmpty || pausedReason != nil {
        VStack {
          if let pausedReason { Text(pausedReason) }
          ForEach(issues) { issue in
            Text(issue.reason)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding()
      }
    }
    .overlay {
      if captures.isEmpty && queueEntries.isEmpty && issues.isEmpty {
        ContentUnavailableView("No Recordings", systemImage: "waveform")
      }
    }
    .navigationTitle(title)
    .confirmationDialog(
      "Remove this recording and its private audio?",
      isPresented: Binding(
        get: { removalCandidate != nil },
        set: { if !$0 { removalCandidate = nil } })
    ) {
      Button("Remove Recording", role: .destructive) {
        guard let removalCandidate else { return }
        onRemove(removalCandidate)
        self.removalCandidate = nil
      }
      Button("Cancel", role: .cancel) { removalCandidate = nil }
    }
  }
}

private struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section("Apple Transcription") {
        appleStatus(.english, label: "English")
        appleStatus(.korean, label: "Korean")
        Button(action: model.selectAppleTranscription) {
          HStack {
            Text("Use Apple Transcription")
            Spacer()
            if model.selectedTranscriptionMethodID == TranscriptionMethodIdentifiers.apple {
              Image(systemName: "checkmark")
                .accessibilityHidden(true)
            }
          }
        }
        .frame(minHeight: 44)
        .disabled(!model.appleReadyForRecovery)
        .accessibilityValue(
          model.selectedTranscriptionMethodID == TranscriptionMethodIdentifiers.apple
            ? "Selected" : "Not selected")
      }
      Section("Cohere Transcription") {
        LabeledContent("Model", value: cohereStatus)
          .accessibilityLabel("Cohere transcription model")
          .accessibilityValue(cohereStatus)
        LabeledContent("Download size", value: model.cohereDownloadSize)
        if model.isInstallingCohere {
          if let fraction = model.cohereInstallProgress?.fraction {
            ProgressView(value: fraction) {
              Text("Installing Cohere model")
            }
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
          } else {
            ProgressView("Installing Cohere model")
          }
          Button("Cancel Installation", role: .cancel, action: model.cancelCohereInstallation)
            .frame(minHeight: 44)
        } else if !model.cohereReadyForRecovery {
          Button("Install Model", action: model.installCohereModel)
            .frame(minHeight: 44)
        }
        Button(action: model.selectCohereTranscription) {
          HStack {
            Text("Use Cohere Transcription")
            Spacer()
            if model.selectedTranscriptionMethodID == TranscriptionMethodIdentifiers.cohere {
              Image(systemName: "checkmark")
                .accessibilityHidden(true)
            }
          }
        }
        .frame(minHeight: 44)
        .disabled(!model.cohereReadyForRecovery)
        .accessibilityValue(
          model.selectedTranscriptionMethodID == TranscriptionMethodIdentifiers.cohere
            ? "Selected" : "Not selected")
        if noReadyRecoveryMethod {
          Text("No transcription method is ready for this recording.")
            .foregroundStyle(.secondary)
        }
      }
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
    .onDisappear { model.leftSettings() }
    .task {
      await model.becameActive()
      model.refreshTranscriptionReadiness()
    }
  }

  private func appleStatus(_ language: CaptureLanguage, label: String) -> some View {
    VStack(alignment: .leading) {
      LabeledContent(
        label, value: AppleReadinessPresentation.label(model.appleReadinessStates[language])
      )
      .accessibilityLabel("\(label) Apple transcription")
      .accessibilityValue(AppleReadinessPresentation.label(model.appleReadinessStates[language]))
      if model.appleInstalling.contains(language) {
        if let fraction = model.appleInstallProgress[language] {
          ProgressView(value: fraction) { Text("Installing \(label) model") }
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        } else {
          ProgressView("Installing \(label) model")
        }
        Button("Cancel Installation", role: .cancel) {
          model.cancelAppleInstallation(language)
        }
        .frame(minHeight: 44)
      } else if model.appleReadinessStates[language] == .downloadable {
        Button("Download \(label) Model") { model.installAppleModel(language) }
          .frame(minHeight: 44)
      }
    }
  }

  private var locationLabel: String {
    switch model.locationState {
    case .notDetermined: "Not Requested"
    case .authorized: "Allowed"
    case .denied: "Denied"
    case .restricted: "Restricted"
    }
  }

  private var cohereStatus: String {
    switch model.cohereReadiness {
    case .checking: "Checking"
    case .notInstalled: "Not installed"
    case .ready: "Ready"
    case .failed(let failure): failure.userMessage
    }
  }

  private var noReadyRecoveryMethod: Bool {
    model.recoveryMethodLanguage != nil && !model.appleReadyForRecovery
      && !model.cohereReadyForRecovery
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
