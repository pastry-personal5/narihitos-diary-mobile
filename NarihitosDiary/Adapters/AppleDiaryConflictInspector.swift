import CryptoKit
import Darwin
import Foundation

struct DiaryExternalVersion: Sendable {
  let contentsURL: URL
  let modifiedAt: Date?
  let providerKey: String?

  init(contentsURL: URL, modifiedAt: Date?, providerKey: String? = nil) {
    self.contentsURL = contentsURL
    self.modifiedAt = modifiedAt
    self.providerKey = providerKey
  }
}

protocol DiaryExternalVersionSourcePort {
  /// The current version is first, followed by unresolved conflict versions.
  func versions(at url: URL) -> [DiaryExternalVersion]
}

struct AppleDiaryExternalVersionSource: DiaryExternalVersionSourcePort {
  func versions(at url: URL) -> [DiaryExternalVersion] {
    guard let current = NSFileVersion.currentVersionOfItem(at: url) else { return [] }
    let versions = [current] + (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [])
    return versions.map {
      return DiaryExternalVersion(
        contentsURL: $0.url, modifiedAt: $0.modificationDate,
        providerKey: Self.key(for: $0))
    }
  }

  static func key(for version: NSFileVersion) -> String? {
    guard
      let archived = try? NSKeyedArchiver.archivedData(
        withRootObject: version.persistentIdentifier, requiringSecureCoding: false)
    else { return nil }
    return SHA256.hash(data: archived).map { String(format: "%02x", $0) }.joined()
  }
}

private struct ConflictObservedFile {
  let bytes: Data
  let version: DiaryFileVersion
  let modifiedAt: Date?
  let providerKey: String?
}

private struct ConflictObservedMarkdown {
  let file: ConflictObservedFile
  let snippet: DiarySnippetV1
}

private struct ConflictPairCandidate {
  let pair: DiaryVerifiedExternalPair
  let markdown: Data
  let audio: Data
  let providerKeys: DiaryProviderVersionKeys?
}

/// Reads each provider version as a complete file, pairs it only through the
/// Markdown's explicit audio digest, and retains two validated private pairs.
/// It never resolves or deletes provider versions.
@MainActor
final class AppleDiaryConflictInspector: DiaryConflictInspectionPort {
  private let destination: AppleDestinationService
  private let captures: CapturePrivateFiles
  private let versions: any DiaryExternalVersionSourcePort
  private let observer: any DiaryFileObserverPort
  private let snapshots: FileDiaryConflictSnapshotStore
  private let codec = DiarySnippetMarkdownCodec()

  init(
    destination: AppleDestinationService, captures: CapturePrivateFiles,
    snapshots: FileDiaryConflictSnapshotStore,
    versions: any DiaryExternalVersionSourcePort = AppleDiaryExternalVersionSource(),
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver()
  ) {
    self.destination = destination
    self.captures = captures
    self.snapshots = snapshots
    self.versions = versions
    self.observer = observer
  }

  func inspectCaptureConflicts(
    reference: UUID, id: AssetID, createdAt: SchemaInstant
  ) async -> DiaryConflictCandidateStatus {
    do {
      let stored = try captures.readSnapshot(reference)
      let layout = DiarySnippetLayout(id: id, createdAt: createdAt)
      return try await destination.withCaptureSnapshotAsync(stored) { root in
        try await inspect(root: root, layout: layout, id: id)
      }
    } catch {
      return .blocked("The conflicting diary pair needs review.")
    }
  }

  func validateChoice(
    _ claim: DiaryConflictResolutionClaim, snapshotID: String, job: QueueJob
  ) async -> Bool {
    guard claim.matches(job: job),
      snapshotID == claim.firstSnapshotID || snapshotID == claim.secondSnapshotID,
      let firstID = try? WorkspaceID(claim.firstSnapshotID),
      let secondID = try? WorkspaceID(claim.secondSnapshotID),
      let first = try? snapshots.read(id: firstID),
      let second = try? snapshots.read(id: secondID),
      first.assetID == claim.assetID, second.assetID == claim.assetID,
      first.providerKeys != nil, second.providerKeys != nil,
      let expectedKeys = claim.expectedProviderKeys,
      let id = try? AssetID(claim.assetID),
      let created = try? SchemaInstant.from(date: job.startedAt),
      let stored = try? captures.readSnapshot(job.destinationReference)
    else { return false }
    let layout = DiarySnippetLayout(id: id, createdAt: created)
    do {
      return try await destination.withCaptureSnapshotAsync(stored) { root in
        var day = root
        for component in layout.directoryComponents {
          day = day.appending(path: component, directoryHint: .isDirectory)
          guard Self.isPlainDirectory(day) else { return false }
        }
        let assets = day.appending(path: layout.assetsDirectoryName, directoryHint: .isDirectory)
        guard Self.isPlainDirectory(assets) else { return false }
        let markdown = day.appending(path: layout.markdownFilename)
        let audio = assets.appending(path: layout.audioFilename)
        return await unchanged(
          markdown: markdown, audio: audio, claim: claim, keys: expectedKeys)
      }
    } catch { return false }
  }

  private func unchanged(
    markdown: URL, audio: URL, claim: DiaryConflictResolutionClaim,
    keys: DiaryProviderVersionKeys
  ) async -> Bool {
    guard Self.isPlainFile(markdown), Self.isPlainFile(audio),
      versions.versions(at: markdown).first?.providerKey == keys.markdown,
      versions.versions(at: audio).first?.providerKey == keys.audio
    else { return false }
    do {
      let markdownObserved = try await observer.observeBounded(
        markdown, maximumBytes: claim.expectedMarkdown.byteCount,
        timeout: .seconds(15))
      let audioObserved = try await observer.observeBounded(
        audio, maximumBytes: claim.expectedAudio.byteCount,
        timeout: .seconds(15))
      return markdownObserved.identity == claim.expectedMarkdown.identity
        && markdownObserved.digest == claim.expectedMarkdown.digest
        && markdownObserved.byteCount == claim.expectedMarkdown.byteCount
        && audioObserved.identity == claim.expectedAudio.identity
        && audioObserved.digest == claim.expectedAudio.digest
        && audioObserved.byteCount == claim.expectedAudio.byteCount
        && versions.versions(at: markdown).first?.providerKey == keys.markdown
        && versions.versions(at: audio).first?.providerKey == keys.audio
    } catch { return false }
  }

  private func inspect(
    root: URL, layout: DiarySnippetLayout, id: AssetID
  ) async throws -> DiaryConflictCandidateStatus {
    var day = root
    for component in layout.directoryComponents {
      day = day.appending(path: component, directoryHint: .isDirectory)
      guard Self.isPlainDirectory(day) else { return .none }
    }
    let assets = day.appending(path: layout.assetsDirectoryName, directoryHint: .isDirectory)
    guard Self.isPlainDirectory(assets) else { return .none }
    let markdownURL = day.appending(path: layout.markdownFilename)
    let audioURL = assets.appending(path: layout.audioFilename)
    guard Self.isPlainFile(markdownURL), Self.isPlainFile(audioURL) else {
      return .blocked("The conflicting diary pair needs review.")
    }
    let markdownVersions = versions.versions(at: markdownURL)
    let audioVersions = versions.versions(at: audioURL)
    guard markdownVersions.count > 1 || audioVersions.count > 1 else { return .none }
    guard (1...2).contains(markdownVersions.count), (1...2).contains(audioVersions.count)
    else { return .blocked("The conflicting diary pair needs review.") }

    var markdownFiles: [ConflictObservedMarkdown] = []
    for version in markdownVersions {
      let file = try await read(version, maximumBytes: 2 * 1_024 * 1_024)
      guard case .supported(let snippet) = codec.decode(file.bytes),
        snippet.id == id, snippet.audioFilename == layout.audioFilename,
        snippet.audioSHA256 != nil,
        DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt) == layout
      else { return .blocked("The conflicting diary text needs review.") }
      markdownFiles.append(ConflictObservedMarkdown(file: file, snippet: snippet))
    }
    var audioFiles: [ConflictObservedFile] = []
    for version in audioVersions {
      audioFiles.append(
        try await read(version, maximumBytes: CapturePrivateFiles.maximumAudioBytes))
    }
    guard let pairs = pairCandidates(markdownFiles, audioFiles) else {
      return .blocked("The conflicting audio versions need review.")
    }
    let first = try snapshots.captureIfAbsent(
      pairs[0].pair, markdown: pairs[0].markdown, audio: pairs[0].audio,
      providerKeys: pairs[0].providerKeys)
    let second = try snapshots.captureIfAbsent(
      pairs[1].pair, markdown: pairs[1].markdown, audio: pairs[1].audio,
      providerKeys: pairs[1].providerKeys)
    return .candidates(
      DiaryConflictCandidates(
        first: first, second: second,
        currentMarkdown: markdownFiles[0].file.version,
        currentAudio: audioFiles[0].version,
        currentProviderKeys: Self.keys(
          markdown: markdownFiles[0].file, audio: audioFiles[0]),
        selection: DiaryPairConflictPolicy.select(
          first: first.modifiedAt, second: second.modifiedAt)))
  }

  private func pairCandidates(
    _ markdownFiles: [ConflictObservedMarkdown], _ audioFiles: [ConflictObservedFile]
  ) -> [ConflictPairCandidate]? {
    var pairs: [ConflictPairCandidate] = []
    var usedAudio: Set<Int> = []
    for markdown in markdownFiles {
      let matches = audioFiles.indices.filter {
        audioFiles[$0].version.digest == markdown.snippet.audioSHA256
      }
      guard matches.count == 1, let audioIndex = matches.first else { return nil }
      // Text-only edits legitimately reference the same immutable recording.
      // The digest must still select exactly one provider audio version.
      usedAudio.insert(audioIndex)
      let audio = audioFiles[audioIndex]
      let pair = DiaryVerifiedExternalPair(
        snippet: markdown.snippet,
        version: DiaryPairVersion(
          markdownIdentity: markdown.file.version.identity,
          audioIdentity: audio.version.identity,
          markdownDigest: markdown.file.version.digest,
          audioDigest: audio.version.digest),
        modifiedAt: DiaryPairModificationTimes(
          markdown: markdown.file.modifiedAt, audio: audio.modifiedAt))
      pairs.append(
        ConflictPairCandidate(
          pair: pair, markdown: markdown.file.bytes, audio: audio.bytes,
          providerKeys: Self.keys(markdown: markdown.file, audio: audio)))
    }
    guard pairs.count == 2, usedAudio.count == audioFiles.count,
      pairs[0].pair.version != pairs[1].pair.version
    else { return nil }
    return pairs
  }

  private func read(
    _ external: DiaryExternalVersion, maximumBytes: Int64
  ) async throws -> ConflictObservedFile {
    let first = try await observer.observeBounded(
      external.contentsURL, maximumBytes: maximumBytes, timeout: .seconds(15))
    let bytes = try await Self.coordinatedBytes(
      external.contentsURL, maximumBytes: maximumBytes)
    let second = try await observer.observeBounded(
      external.contentsURL, maximumBytes: maximumBytes, timeout: .seconds(15))
    guard first.identity == second.identity, first.digest == second.digest,
      first.byteCount == second.byteCount,
      Int64(bytes.count) == second.byteCount,
      Self.digest(bytes) == second.digest
    else { throw DiaryFileObservationFailure.changed }
    return ConflictObservedFile(
      bytes: bytes,
      version: DiaryFileVersion(
        identity: second.identity, digest: second.digest,
        byteCount: second.byteCount),
      modifiedAt: external.modifiedAt, providerKey: external.providerKey)
  }

  nonisolated private static func keys(
    markdown: ConflictObservedFile, audio: ConflictObservedFile
  ) -> DiaryProviderVersionKeys? {
    guard let markdownKey = markdown.providerKey, let audioKey = audio.providerKey else {
      return nil
    }
    return DiaryProviderVersionKeys(markdown: markdownKey, audio: audioKey)
  }

  nonisolated private static func coordinatedBytes(
    _ url: URL, maximumBytes: Int64
  ) async throws -> Data {
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

  nonisolated private static func isPlainDirectory(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
  }

  nonisolated private static func isPlainFile(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
      && info.st_nlink == 1
  }

  nonisolated private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
