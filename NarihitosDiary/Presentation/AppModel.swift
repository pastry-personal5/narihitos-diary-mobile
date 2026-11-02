import AVFAudio
import Combine
import Foundation
import OSLog
import SwiftUI
import UIKit

// Capture presentation adds the M9 lifecycle to the M8 root model.
// swiftlint:disable type_body_length file_length

enum RootTab: Hashable {
  case main
  case benefits
  case calendar
  case plugins
  case all
}

private enum FolderPickerRequestOrigin: String {
  case direct
  case recordingRecovery = "recording-recovery"
  case settingsAction = "settings-action"
}

@MainActor
final class AppModel: ObservableObject {
  let catalog: CatalogModel
  let catalogRenderers = CatalogDetailRendererRegistry.production(
    attributionSource: AppleWeatherAttributionSource())
  let notices = MainNoticeModel()
  @Published var recoveryRoute: CatalogRecoveryDestination?
  @Published private(set) var microphoneState: PermissionState
  @Published private(set) var locationState: PermissionState
  @Published private(set) var destination = ActiveDestination(
    summary: nil, accessState: .restoreAccessRequired)
  @Published private(set) var firstLaunchStep: FirstLaunchStep?
  @Published var isFolderPickerPresented = false
  @Published private(set) var folderPickerRequestID: UUID?
  @Published var preparedDestination: PreparedDestination?
  @Published var message: String?
  @Published private(set) var savedFolderBanner: String?
  @Published private(set) var offersSettingsRecovery = false
  @Published private(set) var offersPendingReview = false
  @Published var isCapturePresented = false
  @Published private(set) var captureElapsed = 0
  @Published private(set) var captureLevel: Float = 0
  @Published private(set) var pendingCaptures: [CaptureIdentity] = []
  @Published private(set) var failedCaptures: [CaptureIdentity] = []
  @Published private(set) var captureIssues: [CaptureRecoveryIssue] = []
  @Published private(set) var queuePending: [QueueProjection] = []
  @Published private(set) var queueFailed: [QueueProjection] = []
  @Published private(set) var queuePausedReason: String?
  @Published private(set) var appleReadinessStates:
    [CaptureLanguage: AppleTranscriptionAssetState] = [:]
  @Published private(set) var appleInstallProgress: [CaptureLanguage: Double] = [:]
  @Published private(set) var appleInstalling: Set<CaptureLanguage> = []
  @Published private(set) var selectedTranscriptionMethodID: String?
  @Published private(set) var selectedTranscriptionModel: TranscriptionModelSelection = .none
  @Published private(set) var transcriptionModelFocus: TranscriptionModelSelection = .none
  @Published private(set) var transcriptionSettingsUnavailable = false
  @Published private(set) var cohereReadiness: CohereModelReadiness = .checking
  @Published private(set) var cohereInstallProgress: CohereInstallProgress?
  @Published private(set) var isInstallingCohere = false
  @Published private(set) var cohereQ5Readiness: CohereModelReadiness = .checking
  @Published private(set) var cohereQ5InstallProgress: CohereInstallProgress?
  @Published private(set) var isInstallingCohereQ5 = false
  @Published var selectedRoot: RootTab = .main
  @Published var showPendingRecordings = false
  @Published var showSettings = false
  @Published var showTranscriptionSettings = false
  @Published private(set) var recoveryMethodLanguage: CaptureLanguage?

  private let microphone: any MicrophoneAuthorizationPort
  private let location: any LocationAuthorizationPort
  private let systemSettings: any SystemSettingsPort
  private let destinationService: any DestinationSelectionPort
  private let firstLaunch: FirstLaunchCoordinator
  private var captureEnvironment: AppleCaptureEnvironment?
  private var captureCoordinator: CaptureCoordinator?
  private var processingQueue: ProcessingQueueCoordinator?
  private var draftAdoption: DiaryDraftAdoptionCoordinator?
  private var commitCoordinator: DiaryCommitCoordinator?
  private var saveTasks: [String: Task<Void, Never>] = [:]
  private var saveAttempted: Set<String> = []
  private var savedFolderBannerTask: Task<Void, Never>?
  private var transcriptionSettings: PrivateSettingsRepository?
  private var appleReadiness: AppleTranscriptionReadiness?
  private var appleInstaller: AppleAssetInstaller?
  private var cohereModels: CohereModelManager?
  private var cohereQ5Models: CohereModelManager?
  private var cancellables: Set<AnyCancellable> = []
  private var captureEntryInProgress = false
  private var pendingFolderSelection: DestinationSelectionOutcome?
  private var folderPickerHasDismissed = false
  private var folderPickerRequestOrigin: FolderPickerRequestOrigin?
  private var isAppActive = false
  private var captureTimer: Task<Void, Never>?
  private var interruptionObserver: NSObjectProtocol?
  private let folderSelectionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "NarihitosDiary",
    category: "FolderSelection")

  var disclosurePresented: Binding<Bool> {
    Binding(
      get: { self.preparedDestination?.needsDisclosure == true },
      set: { isPresented in
        self.folderSelectionLogger.debug(
          "Disclosure presentation changed; isPresented=\(isPresented, privacy: .public); prepared selection retained"
        )
        // Alert buttons own acceptance and cancellation. SwiftUI writes false before invoking
        // their actions, so treating this write as cancellation would discard the selection.
      })
  }

  // swiftlint:disable:next function_body_length
  convenience init() {
    let repository = PrivateSettingsRepository()
    let destination = AppleDestinationService(repository: repository)
    var catalogRegistry = CatalogAssetRegistry()
    catalogRegistry.register(DiaryCatalogHandler())
    let catalog = AppleAssetCatalog(destination: destination, registry: catalogRegistry)
    let files = CapturePrivateFiles()
    let audioSource = VerifiedCaptureAudioSource(files: files)
    let candidateStore = FileTranscriptionCandidateStore(root: files.root, audio: audioSource)
    let draftStore = RetryingDiaryDraftStore(root: files.root, audio: audioSource)
    let readinessSource = AppleSpeechReadinessSource()
    let queueStore = FileQueueStore()
    let registry = TranscriptionMethodRegistry()
    let cohereModels = CohereModelManager(descriptor: .productionQ4)
    let cohereQ5Models = CohereModelManager(descriptor: .productionQ5)
    registry.register(
      AppleTranscriptionAdapter(
        store: queueStore, audio: audioSource, readinessSource: readinessSource))
    registry.register(
      CohereTranscriptionAdapter(
        store: queueStore, audio: audioSource, models: cohereModels, q5Models: cohereQ5Models,
        selectedModel: { [weak repository] in
          guard let repository,
            case .value(let selection) = repository.loadTranscriptionModelSelection()
          else { return .cohereQ4 }
          return selection
        }))
    let installationIdentity = KeychainInstallationIdentity()
    self.init(
      microphone: AppleMicrophoneAuthorization(),
      location: AppleLocationAuthorization(),
      systemSettings: AppleSystemSettings(),
      destinationService: destination,
      firstLaunchStore: repository, catalogPort: catalog)
    captureEnvironment = AppleCaptureEnvironment(
      microphone: microphone, destination: destination, files: files,
      installationIdentity: installationIdentity)
    transcriptionSettings = repository
    reloadTranscriptionSelection(from: repository)
    appleReadiness = AppleTranscriptionReadiness(source: readinessSource)
    let installer = AppleAssetInstaller(backend: SystemAppleAssetInstallationBackend())
    installer.onChange = { [weak self, weak installer] in
      self?.appleInstallProgress = installer?.progress ?? [:]
    }
    appleInstaller = installer
    self.cohereModels = cohereModels
    self.cohereQ5Models = cohereQ5Models
    observeCohereModel(cohereModels)
    observeCohereQ5Model(cohereQ5Models)
    let conflictSnapshots = try? FileDiaryConflictSnapshotStore()
    let receipts = CaptureQueueReceiptSource(files: files, snapshots: conflictSnapshots)
    processingQueue = ProcessingQueueCoordinator(
      store: queueStore, receipts: receipts,
      identity: installationIdentity,
      settings: ProductionTranscriptionSettings(repository: repository),
      registry: registry,
      candidates: candidateStore, drafts: draftStore)
    draftAdoption = DiaryDraftAdoptionCoordinator(
      queue: queueStore, receipts: receipts,
      candidates: candidateStore, drafts: draftStore,
      titles: DiaryTitlePolicy(
        model: AppleDiaryTitleModel(), languageDetector: NaturalLanguageTitleDetector()))
    let payload = RetryingDiaryCommitPayload(
      root: files.root, drafts: draftStore, audio: audioSource)
    let conflictInspector = conflictSnapshots.map {
      AppleDiaryConflictInspector(
        destination: destination, captures: files, snapshots: $0)
    }
    let conflictPairs = conflictSnapshots.map {
      AppleDiaryConflictPairStore(
        destination: destination, captures: files, snapshots: $0)
    }
    let commit = DiaryCommitCoordinator(
      queue: queueStore, drafts: draftStore,
      pairs: AppleDiaryPairStore(
        destination: destination, captures: files, payload: payload),
      cleanup: CaptureCommitCleanup(files: files, snapshots: conflictSnapshots),
      conflicts: conflictInspector,
      conflictPairs: conflictPairs)
    commitCoordinator = commit
    processingQueue?.saveWork = commit
    commit.onChange = { [weak self] in self?.refreshCaptureLists() }
    commit.onSettled = { [weak self] jobID in
      self?.processingQueue?.saveAttemptSettled(jobID: jobID)
      self?.refreshCaptureLists()
    }
    commit.onSaved = { [weak self] job in
      guard let self, let snapshot = try? files.readSnapshot(job.destinationReference) else {
        return
      }
      if self.destination.summary?.id.rawValue == snapshot.id {
        self.catalog.refresh()
      } else {
        showSavedFolderBanner(snapshot.displayName)
      }
    }
    draftAdoption?.onChange = { [weak self] in
      self?.refreshCaptureLists()
      self?.pumpSaves()
    }
    processingQueue?.onChange = { [weak self] in
      self?.refreshCaptureLists()
      self?.draftAdoption?.prerequisiteChanged()
      self?.pumpSaves()
    }
  }

  init(
    microphone: any MicrophoneAuthorizationPort,
    location: any LocationAuthorizationPort,
    systemSettings: any SystemSettingsPort,
    destinationService: any DestinationSelectionPort,
    firstLaunchStore: any FirstLaunchStorePort,
    catalogPort: (any AssetCatalogPort)? = nil
  ) {
    self.catalog = CatalogModel(catalog: catalogPort ?? InactiveAssetCatalog())
    self.microphone = microphone
    self.location = location
    self.systemSettings = systemSettings
    self.destinationService = destinationService
    firstLaunch = FirstLaunchCoordinator(
      microphone: microphone, location: location, store: firstLaunchStore)
    microphoneState = microphone.currentState()
    locationState = location.currentState()
    firstLaunchStep = firstLaunch.pendingExplanation
    catalog.onChange = { [weak self] in self?.updateMainNotices() }
    notices.announce = { message in
      if UIAccessibility.isVoiceOverRunning {
        let queued = NSAttributedString(
          string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: queued)
      }
    }
  }

  func becameActive() async {
    isAppActive = true
    saveAttempted.removeAll()
    firstLaunch.refresh()
    microphoneState = microphone.currentState()
    locationState = location.currentState()
    destination = await destinationService.activeDestination()
    if let repository = transcriptionSettings { reloadTranscriptionSelection(from: repository) }
    firstLaunchStep = firstLaunch.pendingExplanation
    _ = captureEnvironment?.recover()
    processingQueue?.activate()
    draftAdoption?.activate()
    commitCoordinator?.resumeCleanup()
    pumpSaves()
    refreshAppleReadiness()
    refreshCohereReadiness()
    refreshCaptureLists()
    catalog.activate(destinationID: destination.summary?.id)
  }

  func becameInactive() {
    isAppActive = false
    catalog.stop()
    notices.setEnvironment(visible: false, paused: true)
    processingQueue?.deactivate()
    draftAdoption?.deactivate()
    appleReadiness?.invalidate()
    appleReadinessStates = [:]
    destinationService.invalidateAccess()
    pendingFolderSelection = nil
    folderPickerHasDismissed = false
    folderPickerRequestOrigin = nil
    folderPickerRequestID = nil
    preparedDestination = nil
    isFolderPickerPresented = false
  }

  func identityChanged() async {
    catalog.stop()
    catalog.changeScope(nil)
    destinationService.invalidateAccess()
    pendingFolderSelection = nil
    folderPickerHasDismissed = false
    folderPickerRequestOrigin = nil
    folderPickerRequestID = nil
    preparedDestination = nil
    isFolderPickerPresented = false
    destination = await destinationService.activeDestination()
    catalog.activate(destinationID: destination.summary?.id)
    saveAttempted.removeAll()
    pumpSaves()
  }

  func continueFirstLaunch() async {
    await firstLaunch.continueCurrentStep()
    microphoneState = microphone.currentState()
    locationState = location.currentState()
    firstLaunchStep = firstLaunch.pendingExplanation
  }

  func requestLocation() async {
    guard location.currentState() == .notDetermined else { return }
    locationState = await location.requestWhenInUse()
  }

  func openSettings() {
    clearMessage()
    systemSettings.openApplicationSettings()
  }

  func openAppSettings() {
    clearMessage()
    showSettings = true
  }

  func clearMessage() {
    message = nil
    offersSettingsRecovery = false
    offersPendingReview = false
  }

  func reviewPendingRecordings() {
    clearMessage()
    selectedRoot = .all
    showPendingRecordings = true
  }

  func selectFolder() {
    beginFolderSelection(origin: .direct)
  }

  func selectFolderFromSettings() {
    beginFolderSelection(origin: .settingsAction)
  }

  private func beginFolderSelection(origin: FolderPickerRequestOrigin) {
    clearMessage()
    destinationService.invalidateAccess()
    pendingFolderSelection = nil
    folderPickerHasDismissed = false
    preparedDestination = nil
    folderPickerRequestOrigin = origin
    folderPickerRequestID = UUID()
    isFolderPickerPresented = true
    folderSelectionLogger.notice(
      "Folder picker requested; origin=\(origin.rawValue, privacy: .public)")
  }

  func pickedFolder(_ url: URL, requestID: UUID?) {
    guard let requestID, requestID == folderPickerRequestID else {
      folderSelectionLogger.notice("Folder picker result superseded")
      return
    }
    let origin = folderPickerRequestOrigin?.rawValue ?? "unknown"
    folderPickerRequestID = nil
    folderPickerRequestOrigin = nil
    folderSelectionLogger.notice(
      "Folder picker result received; origin=\(origin, privacy: .public)")
    // Prepare while the picker-granted URL is available, but wait for SwiftUI's
    // dismissal completion before presenting another modal or publishing a commit.
    // UIKit may deliver this result after SwiftUI has already reported dismissal.
    pendingFolderSelection = destinationService.prepareSelection(of: url)
    isFolderPickerPresented = false
    if folderPickerHasDismissed { presentPendingFolderSelection() }
  }

  func folderPickerDismissed() {
    guard !isFolderPickerPresented else { return }
    folderPickerHasDismissed = true
    folderSelectionLogger.notice("Folder picker dismissal completed")
    // Dismissal alone is not cancellation: the system picker can send its result next.
    presentPendingFolderSelection()
  }

  private func presentPendingFolderSelection() {
    guard let outcome = pendingFolderSelection else { return }
    pendingFolderSelection = nil
    switch outcome {
    case .prepared(let candidate):
      folderSelectionLogger.notice(
        "Folder selection prepared; disclosureRequired=\(candidate.needsDisclosure, privacy: .public)"
      )
      preparedDestination = candidate
      if !candidate.needsDisclosure {
        commitPreparedDestination()
      }
    case .rejected:
      folderSelectionLogger.notice("Folder selection rejected")
      presentMessage("Choose a folder in iCloud Drive.")
    case .temporarilyUnavailable:
      folderSelectionLogger.notice("Folder selection temporarily unavailable")
      presentMessage("The folder is temporarily unavailable. Try again later.")
    }
  }

  func cancelFolderPicker(requestID: UUID?) {
    guard let requestID, requestID == folderPickerRequestID else { return }
    let origin = folderPickerRequestOrigin?.rawValue ?? "unknown"
    folderPickerRequestID = nil
    folderPickerRequestOrigin = nil
    pendingFolderSelection = nil
    folderPickerHasDismissed = false
    isFolderPickerPresented = false
    folderSelectionLogger.notice(
      "Folder picker canceled; origin=\(origin, privacy: .public)")
  }

  func cancelDisclosure() {
    guard let preparedDestination else { return }
    folderSelectionLogger.notice("Folder disclosure canceled; prepared selection discarded")
    destinationService.cancelPreparedSelection(preparedDestination.id)
    self.preparedDestination = nil
  }

  func acceptDisclosure() {
    folderSelectionLogger.notice("Folder disclosure accepted; committing prepared selection")
    commitPreparedDestination()
  }

  func handleRecord(language: CaptureLanguage) async {
    guard !captureEntryInProgress, !isCapturePresented else { return }
    captureEntryInProgress = true
    defer { captureEntryInProgress = false }
    microphoneState = microphone.currentState()
    switch microphoneState {
    case .denied, .restricted:
      presentMicrophoneRecovery()
    case .notDetermined:
      microphoneState = await microphone.requestAccess()
      if microphoneState != .authorized {
        if microphoneState == .denied || microphoneState == .restricted {
          presentMicrophoneRecovery()
        } else {
          presentMessage("Microphone access is required to record.")
        }
        return
      }
      await routeRecordAfterAuthorization(language: language)
    case .authorized:
      await routeRecordAfterAuthorization(language: language)
    }
  }

  private func routeRecordAfterAuthorization(language: CaptureLanguage) async {
    microphoneState = microphone.currentState()
    guard microphoneState == .authorized else {
      if microphoneState == .denied || microphoneState == .restricted {
        presentMicrophoneRecovery()
      } else {
        presentMessage("Microphone access is required to record.")
      }
      return
    }

    destination = await destinationService.activeDestination()
    microphoneState = microphone.currentState()
    guard microphoneState == .authorized else {
      if microphoneState == .denied || microphoneState == .restricted {
        presentMicrophoneRecovery()
      } else {
        presentMessage("Microphone access is required to record.")
      }
      return
    }
    var verifiedOffline = false
    if destination.accessState == .temporarilyUnavailable {
      if let service = destinationService as? AppleDestinationService {
        verifiedOffline = (try? await service.captureSnapshotRecord()) != nil
      }
    }
    if destination.summary == nil || (destination.accessState != .accessible && !verifiedOffline) {
      beginFolderSelection(origin: .recordingRecovery)
    } else {
      await startCapture(language: language)
    }
  }

  private func startCapture(language: CaptureLanguage) async {
    guard let captureEnvironment else {
      presentMessage("Recording is temporarily unavailable.")
      return
    }
    let coordinator = CaptureCoordinator(environment: captureEnvironment)
    captureCoordinator = coordinator
    coordinator.onSettlement = { [weak self] phase in
      self?.finishCapture(phase)
    }
    do {
      try await coordinator.start(language: language)
      guard case .capturing = coordinator.phase else { return }
      captureElapsed = 0
      captureLevel = 0
      isCapturePresented = true
      interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: raw) == .began
        else { return }
        Task { @MainActor in self?.stopCapture(reason: .interruption) }
      }
      captureTimer?.cancel()
      captureTimer = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(250))
          guard let self, self.isCapturePresented else { return }
          self.captureElapsed = coordinator.elapsedSeconds
          self.captureLevel = captureEnvironment.currentLevel()
        }
      }
    } catch CaptureGateFailure.insufficientSpace {
      presentMessage("Not enough storage to start recording.", offersPendingReview: true)
    } catch {
      presentMessage("Recording could not start. Try again later.")
    }
  }

  func stopCapture(reason: CaptureEndReason = .user) {
    guard let captureCoordinator else { return }
    captureCoordinator.end(reason)
  }

  private func finishCapture(_ phase: CapturePhase) {
    captureTimer?.cancel()
    captureTimer = nil
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
      self.interruptionObserver = nil
    }
    isCapturePresented = false
    processingQueue?.captureSettled()
    refreshCaptureLists()
    switch phase {
    case .pending:
      break
    case .failed:
      presentMessage("This recording can’t be read.")
    case .paused:
      presentMessage("Recording saved locally. Recovery will resume when storage is available.")
    default:
      break
    }
  }

  func refreshCaptureLists() {
    let queue = processingQueue?.projections() ?? []
    let adoptedIDs = Set(queue.map(\.id))
    let nextPendingCaptures = (captureEnvironment?.pending() ?? []).filter {
      !adoptedIDs.contains($0.id.description)
    }
    let nextFailedCaptures = captureEnvironment?.failed() ?? []
    let nextCaptureIssues = captureEnvironment?.issues() ?? []
    let nextQueuePending = queue.filter { $0.state != .failed && $0.state != .saved }
    let nextQueueFailed = queue.filter { $0.state == .failed }
    let nextPausedReason = processingQueue?.pausedReason ?? draftAdoption?.pausedReason

    // Queue callbacks are emitted for every state transition. These sources are
    // main-actor/file-backed, so republishing identical snapshots makes a burst
    // of pending jobs needlessly redraw the recovery list.
    if pendingCaptures != nextPendingCaptures { pendingCaptures = nextPendingCaptures }
    if failedCaptures != nextFailedCaptures { failedCaptures = nextFailedCaptures }
    if captureIssues != nextCaptureIssues { captureIssues = nextCaptureIssues }
    if queuePending != nextQueuePending { queuePending = nextQueuePending }
    if queueFailed != nextQueueFailed { queueFailed = nextQueueFailed }
    if queuePausedReason != nextPausedReason { queuePausedReason = nextPausedReason }
    updateMainNotices()
  }

  func openRecovery(_ destination: CatalogRecoveryDestination) {
    selectedRoot = .all
    recoveryRoute = destination
  }

  func openAll() {
    selectedRoot = .all
  }

  private func updateMainNotices() {
    var values: [MainNotice] = []
    let processing = queuePending.filter { $0.state == .transcribing }.count
    let pending = pendingCaptures.count + queuePending.filter { $0.state != .transcribing }.count
    if processing > 0 {
      values.append(
        MainNotice(
          category: .processing, destination: .pending, message: "Transcribing a recording."))
    }
    if pending > 0 {
      values.append(
        MainNotice(
          category: .queued, destination: .pending, message: "\(pending) pending recordings."))
    }
    if !failedCaptures.isEmpty || !queueFailed.isEmpty || !captureIssues.isEmpty {
      values.append(
        MainNotice(category: .recovery, destination: .failed, message: "Recordings need attention.")
      )
    }
    if queuePausedReason != nil {
      values.append(
        MainNotice(
          category: .recovery, destination: .pending, message: "Pending work needs attention."))
    }
    for destination in [CatalogRecoveryDestination.incomplete, .conflicts]
    where catalog.knownRecoveryDestinations.contains(destination) {
      values.append(
        MainNotice(
          category: .recovery, destination: destination,
          message: "\(destination.rawValue) need attention."))
    }
    notices.update(values)
  }

  func refreshTranscriptionReadiness() {
    processingQueue?.settingsEntered()
    refreshAppleReadiness()
    refreshCohereReadiness()
    refreshCaptureLists()
  }

  func selectAppleTranscription() {
    guard let language = recoveryMethodLanguage else {
      persistAppleSelection()
      return
    }
    guard let appleReadiness else { return }
    Task { [weak self] in
      guard let state = await appleReadiness.refresh(language), let self else { return }
      self.appleReadinessStates[language] = state
      guard case .ready = state, self.recoveryMethodLanguage == language else { return }
      self.persistAppleSelection()
    }
  }

  func installAppleModel(_ language: CaptureLanguage) {
    guard let appleInstaller, !appleInstalling.contains(language) else { return }
    appleInstalling.insert(language)
    Task { [weak self] in
      let preparation = await appleInstaller.prepare(language)
      if case .downloadable(let plan) = preparation {
        let outcome = await appleInstaller.install(plan)
        switch outcome {
        case .reservationCapacity:
          self?.presentMessage("This device cannot reserve another Apple language model.")
        case .failed:
          self?.presentMessage("The Apple model could not be installed. Try again.")
        case .ready, .downloading, .unsupported, .cancelled:
          break
        }
      }
      self?.appleInstalling.remove(language)
      if self?.isAppActive == true {
        self?.refreshAppleReadiness()
        self?.processingQueue?.prerequisiteChanged()
      }
    }
  }

  func cancelAppleInstallation(_ language: CaptureLanguage) {
    appleInstaller?.cancel(language)
  }

  func chooseMethodForRecovery(_ language: CaptureLanguage) {
    recoveryMethodLanguage = language
    transcriptionModelFocus = selectedTranscriptionModel
    selectedRoot = .all
    showTranscriptionSettings = true
    refreshAppleReadiness()
    refreshCohereReadiness()
  }

  func leftSettings() {
    recoveryMethodLanguage = nil
    transcriptionModelFocus = selectedTranscriptionModel
  }

  var transcriptionSummary: String {
    if transcriptionSettingsUnavailable { return "Unavailable" }
    return "\(selectedTranscriptionModel.label) · \(transcriptionReadinessSummary)"
  }

  private func reloadTranscriptionSelection(from repository: PrivateSettingsRepository) {
    switch repository.loadTranscriptionModelSelection() {
    case .value(let selection):
      transcriptionSettingsUnavailable = false
      selectedTranscriptionModel = selection
      selectedTranscriptionMethodID = selection.methodID
      transcriptionModelFocus = selection
    case .unavailable:
      transcriptionSettingsUnavailable = true
      selectedTranscriptionModel = .none
      selectedTranscriptionMethodID = nil
      transcriptionModelFocus = .none
    }
  }

  var transcriptionReadinessSummary: String {
    switch selectedTranscriptionModel {
    case .none: "Waiting for choice"
    case .appleLocal: appleReadyForCurrentContext ? "Ready" : "Not ready"
    case .cohereQ4: cohereReadyForRecovery ? "Ready" : "Not installed"
    case .cohereQ5: cohereQ5ReadyForRecovery ? "Ready" : "Not installed"
    }
  }

  var appleReadyForCurrentContext: Bool {
    if let language = recoveryMethodLanguage { return isAppleReady(for: language) }
    return [CaptureLanguage.english, .korean].allSatisfy { isAppleReady(for: $0) }
  }

  func isTranscriptionSelectionReady(_ selection: TranscriptionModelSelection) -> Bool {
    switch selection {
    case .none: false
    case .appleLocal: appleReadyForCurrentContext
    case .cohereQ4: cohereReadyForRecovery
    case .cohereQ5: cohereQ5ReadyForRecovery
    }
  }

  func selectTranscriptionModel(_ selection: TranscriptionModelSelection) {
    if recoveryMethodLanguage != nil {
      transcriptionModelFocus = selection
      return
    }
    persistTranscriptionModel(selection)
  }

  func useFocusedTranscriptionModel() {
    guard recoveryMethodLanguage != nil,
      isTranscriptionSelectionReady(transcriptionModelFocus)
    else { return }
    persistTranscriptionModel(transcriptionModelFocus)
  }

  private func persistTranscriptionModel(_ selection: TranscriptionModelSelection) {
    guard let transcriptionSettings else { return }
    do {
      try transcriptionSettings.selectTranscriptionModel(selection)
      selectedTranscriptionModel = selection
      selectedTranscriptionMethodID = selection.methodID
      transcriptionModelFocus = selection
      processingQueue?.prerequisiteChanged()
      refreshCaptureLists()
    } catch {
      presentMessage("The transcription model choice could not be saved. Try again.")
    }
  }

  var appleReadyForRecovery: Bool {
    guard let language = recoveryMethodLanguage else { return true }
    guard case .ready = appleReadinessStates[language] else { return false }
    return true
  }

  var cohereReadyForRecovery: Bool {
    if case .ready = cohereReadiness { return true }
    return false
  }

  var cohereQ5ReadyForRecovery: Bool {
    if case .ready = cohereQ5Readiness { return true }
    return false
  }

  var cohereDownloadSize: String {
    guard let cohereModels else { return "Unavailable" }
    return ByteCountFormatter.string(
      fromByteCount: cohereModels.downloadByteCount, countStyle: .file)
  }

  var cohereQ5DownloadSize: String {
    ByteCountFormatter.string(
      fromByteCount: CohereTrustedModel.productionQ5.byteCount, countStyle: .file)
  }

  func installCohereModel() { cohereModels?.install() }

  func installCohereQ5Model() { cohereQ5Models?.install() }

  func cancelCohereInstallation() { cohereModels?.cancelInstallation() }

  func cancelCohereQ5Installation() { cohereQ5Models?.cancelInstallation() }

  func selectCohereTranscription() {
    selectTranscriptionModel(.cohereQ4)
  }

  private func persistAppleSelection() {
    selectTranscriptionModel(.appleLocal)
  }

  private func isAppleReady(for language: CaptureLanguage) -> Bool {
    if case .ready = appleReadinessStates[language] { return true }
    return false
  }

  private func refreshAppleReadiness() {
    guard isAppActive, let appleReadiness else { return }
    for language in [CaptureLanguage.english, .korean] {
      Task { [weak self] in
        guard let state = await appleReadiness.refresh(language) else { return }
        self?.appleReadinessStates[language] = state
      }
    }
  }

  private func refreshCohereReadiness() {
    guard let cohereModels else { return }
    Task { [weak self] in
      let state = await cohereModels.refresh()
      guard let self else { return }
      self.cohereReadiness = state
      self.processingQueue?.prerequisiteChanged()
      self.refreshCaptureLists()
    }
    if let cohereQ5Models {
      Task { [weak self] in
        self?.cohereQ5Readiness = await cohereQ5Models.refresh()
      }
    }
  }

  private func observeCohereModel(_ models: CohereModelManager) {
    models.$readiness
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        self?.cohereReadiness = state
        if case .ready = state { self?.processingQueue?.prerequisiteChanged() }
      }
      .store(in: &cancellables)
    models.$progress
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.cohereInstallProgress = $0 }
      .store(in: &cancellables)
    models.$isInstalling
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.isInstallingCohere = $0 }
      .store(in: &cancellables)
  }

  private func observeCohereQ5Model(_ models: CohereModelManager) {
    models.$readiness.receive(on: DispatchQueue.main).sink { [weak self] in
      self?.cohereQ5Readiness = $0
      if case .ready = $0 { self?.processingQueue?.prerequisiteChanged() }
    }.store(in: &cancellables)
    models.$progress.receive(on: DispatchQueue.main).sink { [weak self] in
      self?.cohereQ5InstallProgress = $0
    }.store(in: &cancellables)
    models.$isInstalling.receive(on: DispatchQueue.main).sink { [weak self] in
      self?.isInstallingCohereQ5 = $0
    }.store(in: &cancellables)
  }

  func retryQueueJob(_ id: String) {
    if processingQueue?.projections().first(where: { $0.id == id })?.state == .readyToSave {
      saveAttempted.remove(id)
      pumpSaves()
      return
    }
    processingQueue?.manualRetry(jobID: id)
    refreshCaptureLists()
  }

  private func pumpSaves() {
    guard isAppActive, let commitCoordinator else { return }
    let ready =
      processingQueue?.projections().filter {
        $0.state == .readyToSave && !saveAttempted.contains($0.id)
      } ?? []
    for job in ready {
      saveAttempted.insert(job.id)
      saveTasks[job.id] = Task { [weak self] in
        await commitCoordinator.attempt(jobID: job.id)
        self?.saveTasks.removeValue(forKey: job.id)
        self?.refreshCaptureLists()
        self?.pumpSaves()
      }
    }
  }

  func resumeQueueJob(_ id: String) {
    processingQueue?.resumeRestored(jobID: id)
    refreshCaptureLists()
  }

  func removeQueueJob(_ id: String) {
    processingQueue?.remove(jobID: id)
    saveTasks[id]?.cancel()
    refreshCaptureLists()
  }

  func dismissSavedFolderBanner() {
    savedFolderBannerTask?.cancel()
    savedFolderBannerTask = nil
    savedFolderBanner = nil
  }

  private func showSavedFolderBanner(_ folder: String) {
    dismissSavedFolderBanner()
    let message = "Diary saved to \(SafeFolderDisplayName.project(folder))."
    savedFolderBanner = message
    if UIAccessibility.isVoiceOverRunning {
      UIAccessibility.post(notification: .announcement, argument: message)
    }
    savedFolderBannerTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      self?.dismissSavedFolderBanner()
    }
  }

  private func presentMicrophoneRecovery() {
    presentMessage(
      "Microphone access is required to record. Open Settings to allow access.",
      offersSettingsRecovery: true)
  }

  private func commitPreparedDestination() {
    guard let candidate = preparedDestination else { return }
    switch destinationService.commitPreparedSelection(candidate.id) {
    case .committed(let summary):
      folderSelectionLogger.notice("Folder selection committed")
      destination = ActiveDestination(summary: summary, accessState: .accessible)
      catalog.changeScope(summary.id)
    case .superseded:
      folderSelectionLogger.notice("Folder selection commit superseded")
      presentMessage("The selection changed before it could be saved.")
    case .failed:
      folderSelectionLogger.notice("Folder selection commit failed")
      presentMessage("The folder could not be saved. Your previous selection was kept.")
    }
    preparedDestination = nil
  }

  private func presentMessage(
    _ message: String, offersSettingsRecovery: Bool = false,
    offersPendingReview: Bool = false
  ) {
    self.message = message
    self.offersSettingsRecovery = offersSettingsRecovery
    self.offersPendingReview = offersPendingReview
  }
}

// swiftlint:enable type_body_length
