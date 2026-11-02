import AVFAudio
import CryptoKit
import Darwin
import Foundation

private enum RecoveryResourceState {
  case absent
  case file
}

/// Classifies a canonical layout in the current selected folder, including
/// pairs that originated on another device and have no local M13 candidate.
@MainActor
final class AppleDiaryRecoveryInspector: DiaryRecoveryInspectionPort {
  private let destination: AppleDestinationService
  private let repository: any DestinationSettingsStore
  private let captures: CapturePrivateFiles
  private let observer: any DiaryFileObserverPort
  private let classifier = DiaryExternalPairClassifier()

  init(
    destination: AppleDestinationService, repository: any DestinationSettingsStore,
    captures: CapturePrivateFiles,
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver()
  ) {
    self.destination = destination
    self.repository = repository
    self.captures = captures
    self.observer = observer
  }

  /// Inspect a pending job at its capture-time destination, independent of
  /// later Settings changes. This is read-only and never grants repair rights.
  func inspectCapture(
    reference: UUID, id: AssetID, createdAt: SchemaInstant
  ) async -> DiaryExternalPairStatus {
    do {
      let stored = try captures.readSnapshot(reference)
      let layout = DiarySnippetLayout(id: id, createdAt: createdAt)
      return try await destination.withCaptureSnapshotAsync(stored) { root in
        try await inspect(layout: layout, id: id, root: root)
      }
    } catch {
      return .blocked("The iCloud pair needs review.")
    }
  }

  func inspectActive(id: AssetID, createdAt: SchemaInstant) async -> DiaryExternalPairStatus {
    guard let stored = repository.loadDestination() else {
      return .blocked("The iCloud folder needs access.")
    }
    let layout = DiarySnippetLayout(id: id, createdAt: createdAt)
    do {
      return try await destination.withCaptureSnapshotAsync(stored) { root in
        try await inspect(layout: layout, id: id, root: root)
      }
    } catch {
      return .blocked("The iCloud pair needs review.")
    }
  }

  private func inspect(
    layout: DiarySnippetLayout, id: AssetID, root: URL
  ) async throws -> DiaryExternalPairStatus {
    var day = root
    for component in layout.directoryComponents {
      let next = day.appending(path: component, directoryHint: .isDirectory)
      if try directoryIsAbsent(next) { return .absent }
      day = next
    }
    let markdownURL = day.appending(path: layout.markdownFilename)
    let assets = day.appending(path: layout.assetsDirectoryName, directoryHint: .isDirectory)
    let assetsAbsent = try directoryIsAbsent(assets)
    let audioURL = assets.appending(path: layout.audioFilename)
    let markdown: DiaryObservedMarkdown?
    switch try state(of: markdownURL) {
    case .absent: markdown = nil
    case .file: markdown = try await readMarkdown(markdownURL)
    }
    let audio: DiaryObservedAudio?
    if assetsAbsent {
      audio = nil
    } else {
      switch try state(of: audioURL) {
      case .absent: audio = nil
      case .file: audio = try await readAudio(audioURL)
      }
    }
    return classifier.classify(layout: layout, assetID: id, markdown: markdown, audio: audio)
  }

  private func directoryIsAbsent(_ url: URL) throws -> Bool {
    var value = stat()
    if lstat(url.path, &value) != 0 {
      if errno == ENOENT { return true }
      throw DiaryFileObservationFailure.unavailable
    }
    guard (value.st_mode & S_IFMT) == S_IFDIR else {
      throw DiaryFileObservationFailure.unsafeResource
    }
    return false
  }

  private func state(of url: URL) throws -> RecoveryResourceState {
    var value = stat()
    if lstat(url.path, &value) != 0 {
      if errno == ENOENT { return .absent }
      throw DiaryFileObservationFailure.unavailable
    }
    guard (value.st_mode & S_IFMT) == S_IFREG, value.st_nlink == 1 else {
      throw DiaryFileObservationFailure.unsafeResource
    }
    return .file
  }

  private func readMarkdown(_ url: URL) async throws -> DiaryObservedMarkdown {
    let maximum: Int64 = 2 * 1_024 * 1_024
    let before = try await observer.observeBounded(
      url, maximumBytes: maximum, timeout: .seconds(15))
    let bytes = try await coordinatedBytes(url, maximumBytes: maximum)
    let after = try await observer.observeBounded(
      url, maximumBytes: maximum, timeout: .seconds(15))
    guard before == after, !after.hasUnresolvedConflict,
      Int64(bytes.count) == after.byteCount,
      Self.digest(bytes) == after.digest
    else { throw DiaryFileObservationFailure.changed }
    return DiaryObservedMarkdown(
      bytes: bytes, version: version(after), modifiedAt: after.modifiedAt)
  }

  private func readAudio(_ url: URL) async throws -> DiaryObservedAudio {
    let maximum = CapturePrivateFiles.maximumAudioBytes
    let before = try await observer.observeBounded(
      url, maximumBytes: maximum, timeout: .seconds(15))
    let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
    let playable = try await BoundedFileCoordinator().perform(
      intents: [intent], timeout: .seconds(15)
    ) { urls in
      guard let coordinated = urls.first,
        let player = try? AVAudioPlayer(contentsOf: coordinated), player.duration > 0
      else { return false }
      return player.prepareToPlay()
    }
    let after = try await observer.observeBounded(
      url, maximumBytes: maximum, timeout: .seconds(15))
    guard before == after, !after.hasUnresolvedConflict else {
      throw DiaryFileObservationFailure.changed
    }
    return DiaryObservedAudio(
      version: version(after), playable: playable, modifiedAt: after.modifiedAt)
  }

  private func coordinatedBytes(_ url: URL, maximumBytes: Int64) async throws -> Data {
    let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
    return try await BoundedFileCoordinator().perform(
      intents: [intent], timeout: .seconds(15)
    ) { urls in
      guard let coordinated = urls.first else {
        throw DiaryFileObservationFailure.unavailable
      }
      let descriptor = Darwin.open(coordinated.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw DiaryFileObservationFailure.unavailable }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      var info = stat()
      guard fstat(descriptor, &info) == 0,
        (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1,
        info.st_size > 0, info.st_size <= maximumBytes
      else { throw DiaryFileObservationFailure.unsafeResource }
      var bytes = Data()
      while bytes.count < Int(info.st_size) {
        let remaining = Int(info.st_size) - bytes.count
        guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)),
          !chunk.isEmpty
        else { throw DiaryFileObservationFailure.changed }
        bytes.append(chunk)
      }
      return bytes
    }
  }

  private func version(_ observation: DiaryFileObservation) -> DiaryFileVersion {
    DiaryFileVersion(
      identity: observation.identity, digest: observation.digest,
      byteCount: observation.byteCount)
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
