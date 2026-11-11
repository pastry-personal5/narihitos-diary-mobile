import SwiftUI

// swiftlint:disable file_length

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model: AppModel

  init() {
    _model = StateObject(wrappedValue: AppModel())
  }

  init(model: AppModel) {
    _model = StateObject(wrappedValue: model)
  }

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
    .modifier(DiaryEditorPresentation(actions: model.diaryActions))
    .sheet(item: $model.manualEditor, onDismiss: model.manualEditorDismissed) { editor in
      ManualDiaryEditorView(
        editor: editor, cancel: model.cancelManualDiary,
        chooseFolder: model.chooseManualDiaryFolder)
    }
    .onChange(of: model.selectedRoot) { _, root in model.catalog.setVisible(root == .main) }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    ) { _ in
      model.catalog.discard()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.protectedDataWillBecomeUnavailableNotification)
    ) { _ in
      model.catalog.stop()
      model.diaryActions.invalidateVisibleActions()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.protectedDataDidBecomeAvailableNotification)
    ) { _ in
      if scenePhase == .active {
        model.catalog.activate(destinationID: model.destination.summary?.id)
      }
    }
    .task { await model.becameActive() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.becameActive() }
      } else {
        model.becameInactive()
        if phase == .background { model.departed() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
      Task { await model.identityChanged() }
    }
    .sheet(
      isPresented: $model.isFolderPickerPresented, onDismiss: model.folderPickerDismissed
    ) {
      let requestID = model.folderPickerRequestID
      FolderPicker(
        onPick: { model.pickedFolder($0, requestID: requestID) },
        onCancel: { model.cancelFolderPicker(requestID: requestID) })
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
          Button(action: model.handleWrite) {
            InterfaceIcon(.write)
              .foregroundStyle(.white).frame(width: 56, height: 56)
              .background(Color.accentColor, in: Circle())
              .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Write Diary Snippet")
          .accessibilityIdentifier("manual-diary-write")
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
        NavigationLink("Pending Diary Snippets") { ManualDiaryPendingView(model: model) }
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
      }
      .navigationTitle("All")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          // Keep Task 14's action boundary before constructing the Settings destination.
          Button {
            model.openAppSettings()
          } label: {
            InterfaceIcon(.settings)
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
          .accessibilityIdentifier("all-settings-button")
        }
      }
      .navigationDestination(item: $model.recoveryRoute) { destination in
        recoveryDestination(destination)
      }
      .navigationDestination(isPresented: $model.showSettings) { SettingsView(model: model) }
      .navigationDestination(isPresented: $model.showTranscriptionSettings) {
        TranscriptionSettingsView(model: model)
      }
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
    case .manualPending:
      ManualDiaryPendingView(model: model)
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

  private var locationLabel: String {
    switch model.locationState {
    case .notDetermined: "Not Requested"
    case .authorized: "Allowed"
    case .denied: "Denied"
    case .restricted: "Restricted"
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

struct CaptureListView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var removalCandidate: String?
  @AccessibilityFocusState private var removalFocus: RemovalFocus?

  private enum RemovalFocus: Hashable {
    case button(String)
    case confirmation(String)
  }

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
          recordingActions(for: entry)
        }
        .buttonStyle(.borderless)
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
    .onChange(of: removalCandidate) { previous, current in
      if scenePhase != .active {
        removalFocus = nil
      } else if let current {
        removalFocus = .confirmation(current)
      } else if let previous {
        let isRemovable = queueEntries.contains {
          $0.id == previous && $0.state != .cancelling
        }
        removalFocus = isRemovable ? .button(previous) : nil
      }
    }
    .onChange(of: queueEntries) { _, entries in
      guard let removalCandidate else { return }
      let isRemovable = entries.contains {
        $0.id == removalCandidate && $0.state != .cancelling
      }
      if !isRemovable {
        self.removalCandidate = nil
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { removalCandidate = nil }
    }
    .onDisappear {
      removalCandidate = nil
      removalFocus = nil
    }
  }

  @ViewBuilder
  private func recordingActions(for entry: QueueProjection) -> some View {
    if entry.state == .cancelling {
      Text("Cancelling").foregroundStyle(.secondary)
    } else if removalCandidate == entry.id {
      VStack(alignment: .leading, spacing: 12) {
        Text("Remove this recording and its private audio?")
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("recording-remove-confirmation-\(entry.id)")
          .accessibilityFocused($removalFocus, equals: .confirmation(entry.id))
        Button(role: .destructive) {
          confirmRemoval(of: entry.id)
        } label: {
          Text("Remove Recording").frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityIdentifier("recording-remove-confirm-\(entry.id)")
        Button(role: .cancel) {
          removalCandidate = nil
        } label: {
          Text("Cancel").frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("recording-remove-cancel-\(entry.id)")
      }
      .padding(.vertical, 8)
    } else {
      VStack(spacing: 12) {
        if entry.state == .reviewRequired {
          recoveryButton("Resume") { onResume(entry.id) }
        } else if entry.state == .failed {
          recoveryButton("Retry") { onRetry(entry.id) }
        } else if entry.state == .waiting {
          recoveryButton("Choose Method") { onChooseMethod(entry.language) }
        } else if entry.state == .readyToSave, entry.reason != nil {
          recoveryButton("Retry Verification") { onRetry(entry.id) }
        }
        Button(role: .destructive) {
          removalCandidate = entry.id
        } label: {
          recordingActionLabel("Remove")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("recording-remove-\(entry.id)")
        .accessibilityFocused($removalFocus, equals: .button(entry.id))
      }
      .padding(.top, 6)
    }
  }

  private func recoveryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      recordingActionLabel(title)
    }
    .buttonStyle(.borderedProminent)
  }

  private func recordingActionLabel(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 52)
  }

  private func confirmRemoval(of id: String) {
    guard removalCandidate == id,
      queueEntries.contains(where: { $0.id == id && $0.state != .cancelling })
    else { return }
    removalCandidate = nil
    onRemove(id)
  }
}

private struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section("Transcription") {
        NavigationLink {
          TranscriptionSettingsView(model: model)
        } label: {
          LabeledContent("Transcription", value: model.transcriptionSummary)
        }
        .accessibilityHint("Opens transcription model settings")
      }
      Section("Active Folder") {
        Text(model.destination.summary?.displayName ?? "No folder selected")
          .lineLimit(1)
          .privacySensitive()
          .accessibilityLabel("Active folder")
          .accessibilityValue(model.destination.summary?.displayName ?? "No folder selected")
        Button(model.destination.summary == nil ? "Select Folder" : "Change Folder") {
          model.selectFolderFromSettings()
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
      if model.remindersDenied {
        Section("Reminders") {
          Text("Notifications are off, so pending diary work can’t remind you.")
          Button("Open Settings", action: model.openSettings)
            .frame(minHeight: 44)
        }
      }
      Section {
        NavigationLink("Danger Zone") {
          DangerZoneView(
            model: model.dangerZone, folderName: model.destination.summary?.displayName,
            folderID: model.destination.summary?.id.rawValue)
        }
        .accessibilityIdentifier("settings-danger-zone")
      }
    }
    .navigationTitle("Settings")
    .task {
      await model.becameActive()
      model.refreshTranscriptionReadiness()
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
}

private struct TranscriptionSettingsView: View {
  @ObservedObject var model: AppModel

  private var selection: Binding<TranscriptionModelSelection> {
    Binding(
      get: { model.transcriptionModelFocus },
      set: { model.selectTranscriptionModel($0) })
  }

  var body: some View {
    Form {
      Section("AI Models") {
        Picker("AI Models", selection: selection) {
          ForEach(TranscriptionModelSelection.allCases) { model in
            Text(model.label).tag(model)
          }
        }
        .pickerStyle(.inline)
        .accessibilityLabel("AI Models")

        if let language = model.recoveryMethodLanguage {
          let languageName = language == .english ? "English" : "Korean"
          Text("Choose a model ready for \(languageName) recordings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          LabeledContent("Saved choice", value: model.selectedTranscriptionModel.label)
          if model.transcriptionModelFocus != model.selectedTranscriptionModel {
            Button("Use \(model.transcriptionModelFocus.label) for Retry") {
              model.useFocusedTranscriptionModel()
            }
            .disabled(!model.isTranscriptionSelectionReady(model.transcriptionModelFocus))
            .frame(minHeight: 44)
          }
        }
      }

      modelDetails
    }
    .navigationTitle("Transcription")
    .onDisappear { model.leftSettings() }
    .task {
      await model.becameActive()
      model.refreshTranscriptionReadiness()
    }
  }

  @ViewBuilder
  private var modelDetails: some View {
    switch model.transcriptionModelFocus {
    case .none:
      Section("Model details") {
        Text("Recordings remain queued until you choose an available transcription model.")
          .foregroundStyle(.secondary)
      }
    case .appleLocal:
      Section("Apple Local") {
        appleStatus(.english, label: "English")
        appleStatus(.korean, label: "Korean")
        Text(
          "Apple provides the system transcription assets. "
            + "Download size is not reported by the system."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    case .cohereQ4:
      cohereSection(title: "Cohere Q4", quantization: "Q4_K_M")
    case .cohereQ5:
      Section("Cohere Q5") {
        LabeledContent("Quantization", value: "Q5_K_M")
        LabeledContent("Model", value: cohereQ5Status)
        LabeledContent("Download size", value: model.cohereQ5DownloadSize)
        if model.isInstallingCohereQ5 {
          if let fraction = model.cohereQ5InstallProgress?.fraction {
            ProgressView(value: fraction) { Text("Installing Cohere Q5") }
              .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
          } else {
            ProgressView("Installing Cohere Q5")
          }
          Button("Cancel Installation", role: .cancel, action: model.cancelCohereQ5Installation)
            .frame(minHeight: 44)
        } else if !model.cohereQ5ReadyForRecovery {
          Button("Install Model", action: model.installCohereQ5Model)
            .frame(minHeight: 44)
        }
      }
    }
  }

  @ViewBuilder
  private func cohereSection(title: String, quantization: String) -> some View {
    Section(title) {
      LabeledContent("Quantization", value: quantization)
      LabeledContent("Model", value: cohereStatus)
        .accessibilityLabel("Cohere model readiness")
      LabeledContent("Download size", value: model.cohereDownloadSize)
      if model.isInstallingCohere {
        if let fraction = model.cohereInstallProgress?.fraction {
          ProgressView(value: fraction) { Text("Installing Cohere Q4") }
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        } else {
          ProgressView("Installing Cohere Q4")
        }
        Button("Cancel Installation", role: .cancel, action: model.cancelCohereInstallation)
          .frame(minHeight: 44)
      } else if !model.cohereReadyForRecovery {
        Button("Install Model", action: model.installCohereModel)
          .frame(minHeight: 44)
      }
      if noReadyRecoveryMethod {
        Text("No transcription model is ready for this recording.")
          .foregroundStyle(.secondary)
      }
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
      } else if shouldOfferAppleSetup(language) {
        Button(
          model.appleReadinessStates[language] == .reservationRequired
            ? "Set Up \(label) Model" : "Download \(label) Model"
        ) {
          model.installAppleModel(language)
        }
        .frame(minHeight: 44)
      }
    }
  }

  private func shouldOfferAppleSetup(_ language: CaptureLanguage) -> Bool {
    model.appleReadinessStates[language] == .downloadable
      || model.appleReadinessStates[language] == .reservationRequired
  }

  private var cohereStatus: String {
    switch model.cohereReadiness {
    case .checking: "Checking"
    case .notInstalled: "Not installed"
    case .ready: "Ready"
    case .failed(let failure): failure.userMessage
    }
  }

  private var cohereQ5Status: String {
    switch model.cohereQ5Readiness {
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

struct PrivacyCover: View {
  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      Image(systemName: "book.closed")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .accessibilityLabel("Narihito's Diary hidden while inactive")
    .accessibilityIdentifier("privacy-cover")
  }
}
