import CryptoKit
import Darwin
import Foundation

// swiftlint:disable file_length

private struct ConflictPairPaths: Sendable {
  let markdown: URL
  let audio: URL
}

/// Publishes a selected protected pair under the capture-time destination loan.
/// Each replacement is checked against the exact current or already-published
/// version; a durable per-file marker covers an interrupted queue checkpoint.
@MainActor
final class AppleDiaryConflictPairStore: DiaryConflictPairStorePort {
  private let destination: AppleDestinationService
  private let captures: CapturePrivateFiles
  private let snapshots: FileDiaryConflictSnapshotStore
  private let observer: any DiaryFileObserverPort
  private let versions: any DiaryExternalVersionSourcePort
  private let cleaner: any DiaryConflictVersionCleanerPort
  private let codec = DiarySnippetMarkdownCodec()

  init(
    destination: AppleDestinationService, captures: CapturePrivateFiles,
    snapshots: FileDiaryConflictSnapshotStore,
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver(),
    versions: any DiaryExternalVersionSourcePort = AppleDiaryExternalVersionSource(),
    cleaner: any DiaryConflictVersionCleanerPort = AppleDiaryConflictVersionCleaner()
  ) {
    self.destination = destination
    self.captures = captures
    self.snapshots = snapshots
    self.observer = observer
    self.versions = versions
    self.cleaner = cleaner
  }

  func ensureAudio(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryFileResult {
    do {
      let selected = try selectedPair(claim, job: job)
      let bytes = try snapshots.audioBytes(id: selected.id)
      return try await withPaths(claim, job: job) { paths in
        try await ensure(
          paths.audio, bytes: bytes, digest: selected.version.audioDigest,
          expected: claim.expectedAudio, published: claim.publishedAudio,
          expectedProviderKey: claim.expectedProviderKeys?.audio,
          token: claim.audioCreationToken)
      }
    } catch { return fileFailure(error) }
  }

  func ensureMarkdown(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryFileResult {
    do {
      let selected = try selectedPair(claim, job: job)
      let bytes = try snapshots.markdownBytes(id: selected.id)
      return try await withPaths(claim, job: job) { paths in
        try await ensure(
          paths.markdown, bytes: bytes, digest: selected.version.markdownDigest,
          expected: claim.expectedMarkdown, published: claim.publishedMarkdown,
          expectedProviderKey: claim.expectedProviderKeys?.markdown,
          token: claim.markdownCreationToken)
      }
    } catch { return fileFailure(error) }
  }

  func verifyPair(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryPairResult {
    do {
      let selected = try selectedPair(claim, job: job)
      guard let markdown = claim.publishedMarkdown, let audio = claim.publishedAudio,
        markdown.digest == selected.version.markdownDigest,
        audio.digest == selected.version.audioDigest
      else { return .recoveryRequired }
      let markdownBytes = try snapshots.markdownBytes(id: selected.id)
      guard case .supported(let snippet) = codec.decode(markdownBytes),
        snippet == selected.snippet,
        snippet.audioSHA256 == audio.digest
      else { return .recoveryRequired }
      return try await withPaths(claim, job: job) { paths in
        guard try await verified(paths.markdown, against: markdown),
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
    _ version: DiaryPairVersion, claim: DiaryConflictResolutionClaim,
    job: QueueJob
  ) async -> DiaryPairUploadObservation {
    do {
      return try await withPaths(claim, job: job) { paths in
        let markdown = try await uploadProof(
          paths.markdown, expected: claim.publishedMarkdown,
          identity: version.markdownIdentity)
        let audio = try await uploadProof(
          paths.audio, expected: claim.publishedAudio,
          identity: version.audioIdentity)
        return DiaryPairUploadObservation(markdown: markdown, audio: audio)
      }
    } catch { return DiaryPairUploadObservation(markdown: nil, audio: nil) }
  }

  func verifyUnchanged(
    _ version: DiaryPairVersion, claim: DiaryConflictResolutionClaim,
    job: QueueJob
  ) async -> DiaryFinalPairCheck {
    do {
      return try await withPaths(claim, job: job) { paths in
        guard let markdown = claim.publishedMarkdown, let audio = claim.publishedAudio,
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
    } catch { return .changed }
  }

  private func selectedPair(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) throws -> DiaryConflictSnapshot {
    guard claim.matches(job: job), let selected = claim.selectedSnapshotID,
      selected == claim.firstSnapshotID || selected == claim.secondSnapshotID,
      let id = try? WorkspaceID(selected)
    else { throw QueueStoreFailure.corrupt }
    let snapshot = try snapshots.read(id: id)
    guard snapshot.assetID == claim.assetID,
      snapshot.version == claim.selectedVersion,
      snapshot.providerKeys != nil
    else {
      throw QueueStoreFailure.corrupt
    }
    return snapshot
  }

  private func withPaths<Value: Sendable>(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob,
    operation: (ConflictPairPaths) async throws -> Value
  ) async throws -> Value {
    guard claim.matches(job: job),
      let id = try? AssetID(claim.assetID),
      let created = try? SchemaInstant.from(date: job.startedAt)
    else { throw QueueStoreFailure.corrupt }
    let stored = try captures.readSnapshot(job.destinationReference)
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    return try await destination.withCaptureSnapshotAsync(stored) { root in
      var day = root
      for component in layout.directoryComponents {
        day = day.appending(path: component, directoryHint: .isDirectory)
        try Self.requireDirectory(day)
      }
      let assets = day.appending(path: layout.assetsDirectoryName, directoryHint: .isDirectory)
      try Self.requireDirectory(assets)
      let paths = ConflictPairPaths(
        markdown: day.appending(path: layout.markdownFilename),
        audio: assets.appending(path: layout.audioFilename))
      return try await operation(paths)
    }
  }

  // swiftlint:disable:next function_parameter_count
  private func ensure(
    _ url: URL, bytes: Data, digest: String, expected: DiaryFileVersion,
    published: DiaryFileVersion?, expectedProviderKey: String?, token: UUID
  ) async throws -> DiaryFileResult {
    guard Self.digest(bytes) == digest else { return .recoveryRequired }
    if let published {
      return try await verified(url, against: published)
        ? .verified(published) : .recoveryRequired
    }
    if let adopted = try await adopted(url, bytes: bytes, digest: digest, token: token) {
      return .verified(adopted)
    }
    guard let expectedProviderKey,
      versions.versions(at: url).first?.providerKey == expectedProviderKey,
      try await verified(url, against: expected)
    else { return .recoveryRequired }
    if expected.digest == digest && expected.byteCount == bytes.count {
      return .verified(expected)
    }
    try await replaceExpected(
      url, bytes: bytes, expected: expected, token: token)
    let observed = try await observer.observeBounded(
      url, maximumBytes: Int64(bytes.count), timeout: .seconds(15))
    guard observed.digest == digest, observed.byteCount == bytes.count else {
      return .recoveryRequired
    }
    return .verified(Self.version(observed))
  }

  private func adopted(
    _ url: URL, bytes: Data, digest: String, token: UUID
  ) async throws -> DiaryFileVersion? {
    guard DiaryFileCreationMarker.matches(token, at: url) else { return nil }
    let first = try await observer.observeBounded(
      url, maximumBytes: Int64(bytes.count), timeout: .seconds(15))
    guard first.digest == digest, first.byteCount == bytes.count else { return nil }
    let second = try await observer.observeBounded(
      url, maximumBytes: Int64(bytes.count), timeout: .seconds(15))
    guard
      first.identity == second.identity && first.digest == second.digest
        && first.byteCount == second.byteCount
    else { return nil }
    return Self.version(second)
  }

  private func verified(_ url: URL, against expected: DiaryFileVersion) async throws -> Bool {
    let observed = try await observer.observeBounded(
      url, maximumBytes: expected.byteCount, timeout: .seconds(15))
    return observed.identity == expected.identity && observed.digest == expected.digest
      && observed.byteCount == expected.byteCount
  }

  private func uploadProof(
    _ url: URL, expected: DiaryFileVersion?, identity: String
  ) async throws -> DiaryFileUploadProof? {
    guard let expected, expected.identity == identity else { return nil }
    let observed = try await observer.observeBounded(
      url, maximumBytes: expected.byteCount, timeout: .seconds(15))
    guard observed.uploaded, observed.identity == identity,
      observed.digest == expected.digest, observed.byteCount == expected.byteCount
    else { return nil }
    return DiaryFileUploadProof(identity: identity, digest: expected.digest)
  }

  nonisolated private static func requireDirectory(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
      throw DiaryFileObservationFailure.unsafeResource
    }
  }

  nonisolated private static func version(_ observed: DiaryFileObservation) -> DiaryFileVersion {
    DiaryFileVersion(
      identity: observed.identity, digest: observed.digest,
      byteCount: observed.byteCount)
  }

  nonisolated private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  private func fileFailure(_ error: Error) -> DiaryFileResult {
    switch error {
    case QueueStoreFailure.corrupt, DiaryFileObservationFailure.unsafeResource,
      DiaryFileObservationFailure.changed:
      .recoveryRequired
    case AudioFingerprintFailure.protectedDataUnavailable:
      .waiting(.localData)
    default: .waiting(.destination)
    }
  }

  private func pairFailure(_ error: Error) -> DiaryPairResult {
    switch fileFailure(error) {
    case .waiting(let wait): .waiting(wait)
    default: .recoveryRequired
    }
  }
}

extension AppleDiaryConflictPairStore {
  // swiftlint:disable:next function_body_length
  func removeObsolete(
    _ claim: DiaryConflictResolutionClaim, job: QueueJob
  ) async -> DiaryConflictCleanupResult {
    do {
      guard claim.matches(job: job), claim.pairVerified == true,
        claim.removalConfirmed == true,
        let markdown = claim.publishedMarkdown,
        let audio = claim.publishedAudio,
        let firstID = try? WorkspaceID(claim.firstSnapshotID),
        let secondID = try? WorkspaceID(claim.secondSnapshotID)
      else { return .recoveryRequired }
      _ = try selectedPair(claim, job: job)
      let first = try snapshots.read(id: firstID)
      let second = try snapshots.read(id: secondID)
      guard first.assetID == claim.assetID, second.assetID == claim.assetID,
        first.version == claim.firstVersion,
        second.version == claim.secondVersion,
        let firstKeys = first.providerKeys,
        let secondKeys = second.providerKeys,
        let knownMarkdown = Self.knownVersions(
          first: DiaryObsoleteFileVersion(
            providerKey: firstKeys.markdown, digest: first.version.markdownDigest,
            byteCount: Int64(try snapshots.markdownBytes(id: firstID).count)),
          second: DiaryObsoleteFileVersion(
            providerKey: secondKeys.markdown, digest: second.version.markdownDigest,
            byteCount: Int64(try snapshots.markdownBytes(id: secondID).count))),
        let knownAudio = Self.knownVersions(
          first: DiaryObsoleteFileVersion(
            providerKey: firstKeys.audio, digest: first.version.audioDigest,
            byteCount: Int64(try snapshots.audioBytes(id: firstID).count)),
          second: DiaryObsoleteFileVersion(
            providerKey: secondKeys.audio, digest: second.version.audioDigest,
            byteCount: Int64(try snapshots.audioBytes(id: secondID).count)))
      else { return .recoveryRequired }
      let version = DiaryPairVersion(
        markdownIdentity: markdown.identity, audioIdentity: audio.identity,
        markdownDigest: markdown.digest, audioDigest: audio.digest)
      guard await verifyUnchanged(version, claim: claim, job: job) == .unchanged else {
        return .waiting
      }
      guard await observeUploads(version, claim: claim, job: job).proves(version) else {
        return .waiting
      }
      return try await withPaths(claim, job: job) { paths in
        let audioResult = await cleaner.removeObsolete(
          at: paths.audio, current: audio, knownVersions: knownAudio)
        guard audioResult == .done else { return audioResult }
        return await cleaner.removeObsolete(
          at: paths.markdown, current: markdown, knownVersions: knownMarkdown)
      }
    } catch QueueStoreFailure.corrupt {
      return .recoveryRequired
    } catch DiaryFileObservationFailure.changed {
      return .recoveryRequired
    } catch { return .waiting }
  }

  nonisolated fileprivate static func knownVersions(
    first: DiaryObsoleteFileVersion, second: DiaryObsoleteFileVersion
  ) -> [DiaryObsoleteFileVersion]? {
    guard !first.providerKey.isEmpty, !second.providerKey.isEmpty else { return nil }
    if first.providerKey == second.providerKey {
      return first == second ? [first] : nil
    }
    return [first, second]
  }

  fileprivate func replaceExpected(
    _ url: URL, bytes: Data, expected: DiaryFileVersion, token: UUID
  ) async throws {
    let parent = url.deletingLastPathComponent()
    try Self.requireDirectory(parent)
    let temporary = parent.appending(path: ".ndm-\(token.uuidString.lowercased()).tmp")
    let intent = NSFileAccessIntent.writingIntent(with: parent, options: [])
    _ = try await BoundedFileCoordinator().perform(
      intents: [intent], timeout: .seconds(15)
    ) { urls in
      guard urls.first?.standardizedFileURL == parent.standardizedFileURL,
        try Self.fingerprint(url, maximumBytes: expected.byteCount) == expected
      else { throw DiaryFileObservationFailure.changed }
      if Self.isAbsent(temporary) {
        try Self.writeTemporary(bytes, to: temporary, token: token)
      }
      let temporaryVersion = try Self.fingerprint(
        temporary, maximumBytes: Int64(bytes.count))
      guard temporaryVersion.digest == Self.digest(bytes),
        temporaryVersion.byteCount == bytes.count,
        DiaryFileCreationMarker.matches(token, at: temporary)
      else { throw DiaryFileObservationFailure.changed }
      guard Darwin.rename(temporary.path, url.path) == 0 else {
        throw DiaryFileObservationFailure.unavailable
      }
      return true
    }
  }

  nonisolated static func fingerprint(
    _ url: URL, maximumBytes: Int64
  ) throws -> DiaryFileVersion {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw DiaryFileObservationFailure.unavailable }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var initial = stat()
    guard fstat(descriptor, &initial) == 0,
      (initial.st_mode & S_IFMT) == S_IFREG, initial.st_nlink == 1,
      initial.st_size > 0, initial.st_size <= maximumBytes
    else { throw DiaryFileObservationFailure.unsafeResource }
    var hasher = SHA256()
    var bytesRead: Int64 = 0
    while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
      bytesRead += Int64(chunk.count)
      guard bytesRead <= maximumBytes else { throw DiaryFileObservationFailure.changed }
      hasher.update(data: chunk)
    }
    var final = stat()
    var path = stat()
    guard fstat(descriptor, &final) == 0, lstat(url.path, &path) == 0,
      DiaryFileIdentity.sameVersion(initial, final),
      DiaryFileIdentity.sameVersion(final, path),
      bytesRead == initial.st_size
    else { throw DiaryFileObservationFailure.changed }
    return DiaryFileVersion(
      identity: DiaryFileIdentity.versionIdentity(final),
      digest: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      byteCount: final.st_size)
  }

  nonisolated fileprivate static func isAbsent(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) != 0 && errno == ENOENT
  }

  nonisolated fileprivate static func writeTemporary(
    _ bytes: Data, to url: URL, token: UUID
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
    DiaryFileCreationMarker.set(descriptor: descriptor, token: token)
    guard fsync(descriptor) == 0 else { throw DiaryFileObservationFailure.unavailable }
  }
}
