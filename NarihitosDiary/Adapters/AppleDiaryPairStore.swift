import Darwin
import Foundation

private enum PairResourceState {
  case absent
  case regular
  case unsafe
}

private struct PairPaths: Sendable {
  let day: URL
  let assets: URL
  let markdown: URL
  let audio: URL
}

/// All provider access occurs under the original capture snapshot loan.
/// Existing names without a recorded version are collisions, even if their bytes match.
@MainActor
// swiftlint:disable:next type_body_length
final class AppleDiaryPairStore: DiaryPairStorePort {
  private let destination: AppleDestinationService
  private let captures: CapturePrivateFiles
  private let payload: any DiaryCommitPayloadPort
  private let observer: any DiaryFileObserverPort
  private let codec = DiarySnippetMarkdownCodec()

  init(
    destination: AppleDestinationService, captures: CapturePrivateFiles,
    payload: any DiaryCommitPayloadPort,
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver()
  ) {
    self.destination = destination
    self.captures = captures
    self.payload = payload
    self.observer = observer
  }

  func ensureAudio(_ intent: DiaryCommitRecord, job: QueueJob) async -> DiaryFileResult {
    do {
      let bytes = try payload.audio(job: job, intent: intent)
      return try await withPaths(intent, createDirectories: true) { paths in
        let repair = try await canRepairMissing(
          targetURL: paths.audio, missing: intent.audioVersion,
          surviving: intent.markdownVersion, survivorURL: paths.markdown)
        return try await ensureFile(
          at: paths.audio, bytes: bytes, expectedDigest: intent.audioDigest,
          prior: intent.audioVersion, allowRepair: repair,
          creationToken: intent.audioCreationToken)
      }
    } catch { return fileFailure(error) }
  }

  func ensureMarkdown(_ intent: DiaryCommitRecord, job: QueueJob) async -> DiaryFileResult {
    do {
      let bytes = try payload.markdown(job: job, intent: intent)
      return try await withPaths(intent, createDirectories: true) { paths in
        let repair = try await canRepairMissing(
          targetURL: paths.markdown, missing: intent.markdownVersion,
          surviving: intent.audioVersion, survivorURL: paths.audio)
        return try await ensureFile(
          at: paths.markdown, bytes: bytes, expectedDigest: intent.markdownDigest,
          prior: intent.markdownVersion, allowRepair: repair,
          creationToken: intent.markdownCreationToken)
      }
    } catch { return fileFailure(error) }
  }

  func verifyPair(_ intent: DiaryCommitRecord, job: QueueJob) async -> DiaryPairResult {
    do {
      let markdownBytes = try payload.markdown(job: job, intent: intent)
      _ = try payload.audio(job: job, intent: intent)
      guard case .supported(let snippet) = codec.decode(markdownBytes),
        snippet.id.description == intent.assetID,
        snippet.audioFilename == intent.audioFilename,
        snippet.audioSHA256 == nil || snippet.audioSHA256 == intent.audioDigest,
        DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt).directoryComponents
          == intent.directoryComponents
      else { return .recoveryRequired }
      return try await withPaths(intent, createDirectories: false) { paths in
        guard let markdown = intent.markdownVersion,
          let audio = intent.audioVersion,
          try await verified(paths.markdown, against: markdown),
          try await verified(paths.audio, against: audio)
        else { return .recoveryRequired }
        return .verified(
          DiaryPairVersion(
            markdownIdentity: markdown.identity, audioIdentity: audio.identity,
            markdownDigest: markdown.digest, audioDigest: audio.digest))
      }
    } catch { return pairFailure(error) }
  }

  func observeUploads(
    _ version: DiaryPairVersion, intent: DiaryCommitRecord
  ) async -> DiaryPairUploadObservation {
    do {
      return try await withPaths(intent, createDirectories: false) { paths in
        let markdown = try await uploadProof(
          paths.markdown, expected: intent.markdownVersion,
          versionIdentity: version.markdownIdentity)
        let audio = try await uploadProof(
          paths.audio, expected: intent.audioVersion,
          versionIdentity: version.audioIdentity)
        return DiaryPairUploadObservation(markdown: markdown, audio: audio)
      }
    } catch { return DiaryPairUploadObservation(markdown: nil, audio: nil) }
  }

  func verifyUnchanged(
    _ version: DiaryPairVersion, intent: DiaryCommitRecord
  ) async -> DiaryFinalPairCheck {
    do {
      return try await withPaths(intent, createDirectories: false) { paths in
        guard let markdown = intent.markdownVersion,
          let audio = intent.audioVersion,
          markdown.identity == version.markdownIdentity,
          audio.identity == version.audioIdentity,
          try await verified(paths.markdown, against: markdown),
          try await verified(paths.audio, against: audio)
        else { return .changed }
        return .unchanged
      }
    } catch DiaryFileObservationFailure.unavailable {
      return .waiting
    } catch DestinationValidationError.providerUnavailable {
      return .waiting
    } catch DestinationValidationError.identityUnavailable {
      return .waiting
    } catch { return .changed }
  }

  // swiftlint:disable:next function_parameter_count
  private func ensureFile(
    at url: URL, bytes: Data, expectedDigest: String,
    prior: DiaryFileVersion?, allowRepair: Bool, creationToken: UUID?
  ) async throws -> DiaryFileResult {
    switch try Self.state(of: url) {
    case .unsafe: return .recoveryRequired
    case .regular:
      if let prior {
        return try await verified(url, against: prior) ? .verified(prior) : .recoveryRequired
      }
      guard let creationToken,
        let adopted = try await adoptInterruptedCreation(
          url, token: creationToken, expectedDigest: expectedDigest,
          expectedCount: Int64(bytes.count))
      else { return .recoveryRequired }
      return .verified(adopted)
    case .absent:
      guard prior == nil || allowRepair else { return .recoveryRequired }
      try await writeExclusive(bytes, to: url, creationToken: creationToken)
      let observed = try await observer.observeBounded(
        url, maximumBytes: Int64(bytes.count), timeout: .seconds(15))
      guard !observed.hasUnresolvedConflict,
        observed.byteCount == Int64(bytes.count),
        observed.digest == expectedDigest
      else { return .recoveryRequired }
      let version = DiaryFileVersion(
        identity: observed.identity, digest: observed.digest,
        byteCount: observed.byteCount)
      return prior == nil ? .verified(version) : .repaired(version)
    }
  }

  private func adoptInterruptedCreation(
    _ url: URL, token: UUID, expectedDigest: String, expectedCount: Int64
  ) async throws -> DiaryFileVersion? {
    let first = try await observer.observeBounded(
      url, maximumBytes: expectedCount, timeout: .seconds(15))
    guard !first.hasUnresolvedConflict, first.byteCount == expectedCount,
      first.digest == expectedDigest,
      DiaryFileCreationMarker.matches(token, at: url)
    else { return nil }
    let second = try await observer.observeBounded(
      url, maximumBytes: expectedCount, timeout: .seconds(15))
    guard !second.hasUnresolvedConflict,
      first.identity == second.identity, first.digest == second.digest,
      first.byteCount == second.byteCount
    else { return nil }
    return DiaryFileVersion(
      identity: second.identity, digest: second.digest, byteCount: second.byteCount)
  }

  private func canRepairMissing(
    targetURL: URL, missing: DiaryFileVersion?, surviving: DiaryFileVersion?,
    survivorURL: URL
  ) async throws -> Bool {
    guard missing != nil, let surviving, try Self.state(of: targetURL) == .absent else {
      return false
    }
    return try await verified(survivorURL, against: surviving)
  }

  private func verified(_ url: URL, against version: DiaryFileVersion) async throws -> Bool {
    let observed = try await observer.observeBounded(
      url, maximumBytes: version.byteCount, timeout: .seconds(15))
    return !observed.hasUnresolvedConflict
      && observed.identity == version.identity && observed.digest == version.digest
      && observed.byteCount == version.byteCount
  }

  private func uploadProof(
    _ url: URL, expected: DiaryFileVersion?, versionIdentity: String
  ) async throws -> DiaryFileUploadProof? {
    guard let expected, expected.identity == versionIdentity else { return nil }
    let observed = try await observer.observeBounded(
      url, maximumBytes: expected.byteCount, timeout: .seconds(15))
    guard observed.uploaded, !observed.hasUnresolvedConflict,
      observed.identity == expected.identity,
      observed.digest == expected.digest, observed.byteCount == expected.byteCount
    else { return nil }
    return DiaryFileUploadProof(identity: observed.identity, digest: observed.digest)
  }

  private func withPaths<Value: Sendable>(
    _ intent: DiaryCommitRecord, createDirectories: Bool,
    operation: (PairPaths) async throws -> Value
  ) async throws -> Value {
    let snapshot = try captures.readSnapshot(intent.destinationReference)
    return try await destination.withCaptureSnapshotAsync(snapshot) { root in
      let paths = try await paths(root: root, intent: intent, create: createDirectories)
      return try await operation(paths)
    }
  }

  private func paths(
    root: URL, intent: DiaryCommitRecord, create: Bool
  ) async throws -> PairPaths {
    guard intent.directoryComponents.count == 3,
      intent.directoryComponents.allSatisfy({ value in
        value.utf8.allSatisfy { (48...57).contains($0) }
      })
    else { throw DiaryFileObservationFailure.unsafeResource }
    try requireDirectory(root)
    var day = root
    for component in intent.directoryComponents {
      day = try await childDirectory(named: component, under: day, create: create)
    }
    let assets = try await childDirectory(
      named: intent.assetsDirectoryName, under: day, create: create)
    return PairPaths(
      day: day, assets: assets,
      markdown: day.appending(path: intent.markdownFilename),
      audio: assets.appending(path: intent.audioFilename))
  }

  private func childDirectory(
    named name: String, under parent: URL, create: Bool
  ) async throws -> URL {
    guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
      name != ".", name != ".."
    else { throw DiaryFileObservationFailure.unsafeResource }
    try requireDirectory(parent)
    let url = parent.appending(path: name, directoryHint: .isDirectory)
    if try Self.state(of: url) == .absent {
      guard create else { throw DiaryFileObservationFailure.unavailable }
      let access = NSFileAccessIntent.writingIntent(with: parent, options: [])
      _ = try await BoundedFileCoordinator().perform(
        intents: [access], timeout: .seconds(15)
      ) { urls in
        guard urls.first?.standardizedFileURL == parent.standardizedFileURL else {
          throw DiaryFileObservationFailure.changed
        }
        try FileManager().createDirectory(at: url, withIntermediateDirectories: false)
        return true
      }
    }
    try requireDirectory(url)
    return url
  }

  private func requireDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw DiaryFileObservationFailure.unsafeResource
    }
  }

  nonisolated private static func state(of url: URL) throws -> PairResourceState {
    var value = stat()
    if lstat(url.path, &value) == 0 {
      return (value.st_mode & S_IFMT) == S_IFREG && value.st_nlink == 1
        ? .regular : .unsafe
    }
    if errno == ENOENT { return .absent }
    throw DiaryFileObservationFailure.unavailable
  }

  private func writeExclusive(
    _ bytes: Data, to url: URL, creationToken: UUID?
  ) async throws {
    let parent = url.deletingLastPathComponent()
    try requireDirectory(parent)
    let access = NSFileAccessIntent.writingIntent(with: parent, options: [])
    _ = try await BoundedFileCoordinator().perform(
      intents: [access], timeout: .seconds(15)
    ) { urls in
      guard urls.first?.standardizedFileURL == parent.standardizedFileURL,
        try Self.state(of: url) == .absent
      else { throw DiaryFileObservationFailure.changed }
      try Self.writeNew(bytes, to: url, creationToken: creationToken)
      return true
    }
  }

  nonisolated private static func writeNew(
    _ bytes: Data, to url: URL, creationToken: UUID?
  ) throws {
    let descriptor = Darwin.open(
      url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw DiaryFileObservationFailure.changed }
    defer { Darwin.close(descriptor) }
    try bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { throw DiaryFileObservationFailure.unsafeResource }
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor, base.advanced(by: offset), bytes.count - offset)
        guard written > 0 else { throw DiaryFileObservationFailure.unavailable }
        offset += written
      }
    }
    if let creationToken {
      DiaryFileCreationMarker.set(descriptor: descriptor, token: creationToken)
    }
    guard fsync(descriptor) == 0 else { throw DiaryFileObservationFailure.unavailable }
  }

  private func fileFailure(_ error: Error) -> DiaryFileResult {
    switch error {
    case DiaryFileObservationFailure.unsafeResource,
      DiaryFileObservationFailure.changed,
      QueueStoreFailure.corrupt,
      AudioFingerprintFailure.invalidAudio,
      DestinationValidationError.invalidReference,
      DestinationValidationError.notICloud:
      .recoveryRequired
    case AudioFingerprintFailure.protectedDataUnavailable:
      .waiting(.localData)
    default: .waiting(.destination)
    }
  }

  private func pairFailure(_ error: Error) -> DiaryPairResult {
    switch error {
    case DiaryFileObservationFailure.unsafeResource,
      DiaryFileObservationFailure.changed,
      QueueStoreFailure.corrupt,
      AudioFingerprintFailure.invalidAudio,
      DestinationValidationError.invalidReference,
      DestinationValidationError.notICloud:
      .recoveryRequired
    case AudioFingerprintFailure.protectedDataUnavailable:
      .waiting(.localData)
    default: .waiting(.destination)
    }
  }
}
