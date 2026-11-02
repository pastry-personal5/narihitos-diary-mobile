import AVFAudio
import CryptoKit
import Darwin
import Foundation

private struct ConflictSnapshotBinding: Codable {
  let schema: Int
  let id: String
  let assetID: String
  let version: DiaryPairVersion
  let modifiedAt: DiaryPairModificationTimes
  let markdownByteCount: Int64
  let audioByteCount: Int64
  let providerKeys: DiaryProviderVersionKeys?
}

protocol ConflictSnapshotAudioValidator {
  func isPlayable(_ bytes: Data) -> Bool
}

struct AppleConflictSnapshotAudioValidator: ConflictSnapshotAudioValidator {
  func isPlayable(_ bytes: Data) -> Bool {
    guard let player = try? AVAudioPlayer(data: bytes), player.duration > 0 else {
      return false
    }
    return player.prepareToPlay()
  }
}

/// Two immutable private files plus a binding record form one selectable pair.
/// Failed or interrupted snapshots remain isolated for recovery inspection.
@MainActor
final class FileDiaryConflictSnapshotStore {
  private let root: URL
  private let workspace: any PrivateWorkspacePort
  private let protection: any DraftFileProtectionPolicy
  private let audioValidator: any ConflictSnapshotAudioValidator
  private let codec = DiarySnippetMarkdownCodec()
  private let manager: FileManager

  init(
    root: URL? = nil,
    protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    audioValidator: any ConflictSnapshotAudioValidator = AppleConflictSnapshotAudioValidator(),
    manager: FileManager = .default,
    workspaceOverride: (any PrivateWorkspacePort)? = nil
  ) throws {
    self.manager = manager
    self.root =
      root
      ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "NarihitosDiary/ConflictSnapshots", directoryHint: .isDirectory)
    self.protection = protection
    self.audioValidator = audioValidator
    workspace =
      try workspaceOverride
      ?? LocalPrivateWorkspace(root: self.root, protectionPolicy: protection)
  }

  func capture(
    _ pair: DiaryVerifiedExternalPair, markdown: Data, audio: Data,
    providerKeys: DiaryProviderVersionKeys? = nil
  ) throws -> DiaryConflictSnapshot {
    guard markdown.count > 0, markdown.count <= 2 * 1_024 * 1_024,
      audio.count > 0, audio.count <= CapturePrivateFiles.maximumAudioBytes,
      Self.digest(markdown) == pair.version.markdownDigest,
      Self.digest(audio) == pair.version.audioDigest,
      audioValidator.isPlayable(audio),
      case .supported(let decoded) = codec.decode(markdown),
      decoded == pair.snippet,
      decoded.audioSHA256 == nil || decoded.audioSHA256 == pair.version.audioDigest,
      DiarySnippetLayout(id: decoded.id, createdAt: decoded.createdAt)
        .validates(audioReference: decoded.audioFilename)
    else { throw QueueStoreFailure.corrupt }
    let id = try WorkspaceID.random()
    let handle = try workspace.allocate(id: id)
    let binding = ConflictSnapshotBinding(
      schema: 1, id: id.description, assetID: decoded.id.description,
      version: pair.version, modifiedAt: pair.modifiedAt,
      markdownByteCount: Int64(markdown.count), audioByteCount: Int64(audio.count),
      providerKeys: providerKeys)
    let record = try JSONEncoder().encode(binding)
    guard record.count <= 64 * 1_024 else { throw QueueStoreFailure.corrupt }
    try workspace.replace(try workspace.artifact(.pendingAudio, in: handle), with: audio)
    try workspace.replace(try workspace.artifact(.markdownDraft, in: handle), with: markdown)
    try workspace.replace(try workspace.artifact(.draftBinding, in: handle), with: record)
    return try read(id: id)
  }

  func captureIfAbsent(
    _ pair: DiaryVerifiedExternalPair, markdown: Data, audio: Data,
    providerKeys: DiaryProviderVersionKeys? = nil
  ) throws -> DiaryConflictSnapshot {
    for id in try snapshotIDs() {
      guard let existing = try? read(id: id) else { continue }
      if existing.assetID == pair.snippet.id.description,
        existing.snippet == pair.snippet,
        existing.version == pair.version,
        existing.modifiedAt == pair.modifiedAt,
        existing.providerKeys == providerKeys
      {  // swiftlint:disable:this opening_brace
        return existing
      }
    }
    return try capture(
      pair, markdown: markdown, audio: audio, providerKeys: providerKeys)
  }

  func read(id: WorkspaceID) throws -> DiaryConflictSnapshot {
    let handle = try workspace.reopen(id: id)
    let audio = try workspace.read(try workspace.artifact(.pendingAudio, in: handle))
    let markdown = try workspace.read(try workspace.artifact(.markdownDraft, in: handle))
    let record = try workspace.read(try workspace.artifact(.draftBinding, in: handle))
    guard record.count <= 64 * 1_024,
      let binding = try? JSONDecoder().decode(ConflictSnapshotBinding.self, from: record),
      binding.schema == 1, binding.id == id.description,
      binding.markdownByteCount == markdown.count,
      binding.audioByteCount == audio.count,
      Self.digest(markdown) == binding.version.markdownDigest,
      Self.digest(audio) == binding.version.audioDigest,
      audioValidator.isPlayable(audio),
      case .supported(let snippet) = codec.decode(markdown),
      snippet.id.description == binding.assetID,
      snippet.audioSHA256 == nil || snippet.audioSHA256 == binding.version.audioDigest,
      DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
        .validates(audioReference: snippet.audioFilename)
    else { throw QueueStoreFailure.corrupt }
    try verifyAttributes(id: id, role: .pendingAudio)
    try verifyAttributes(id: id, role: .markdownDraft)
    try verifyAttributes(id: id, role: .draftBinding)
    return DiaryConflictSnapshot(
      id: id, assetID: binding.assetID, snippet: snippet,
      version: binding.version, modifiedAt: binding.modifiedAt,
      providerKeys: binding.providerKeys)
  }

  func audioBytes(id: WorkspaceID) throws -> Data {
    _ = try read(id: id)
    let handle = try workspace.reopen(id: id)
    return try workspace.read(try workspace.artifact(.pendingAudio, in: handle))
  }

  func markdownBytes(id: WorkspaceID) throws -> Data {
    _ = try read(id: id)
    let handle = try workspace.reopen(id: id)
    return try workspace.read(try workspace.artifact(.markdownDraft, in: handle))
  }

  func snapshotIDs() throws -> [WorkspaceID] {
    let children = try manager.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    return children.compactMap { url in
      guard let id = try? WorkspaceID(url.lastPathComponent),
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
        values.isDirectory == true, values.isSymbolicLink == false
      else { return nil }
      return id
    }
  }

  /// Call only after the selected complete pair has been verified and any new
  /// write has both upload reports. Re-read before deleting the exact snapshot.
  func removeVerified(id: WorkspaceID, expected: DiaryConflictSnapshot) throws {
    guard try read(id: id) == expected else { throw QueueStoreFailure.corrupt }
    let handle = try workspace.reopen(id: id)
    try workspace.remove(handle)
  }

  func removeVerifiedIfPresent(
    id: WorkspaceID, assetID: String, version: DiaryPairVersion
  ) throws {
    let url = root.appending(path: id.description, directoryHint: .isDirectory)
    var info = stat()
    if lstat(url.path, &info) != 0 {
      guard errno == ENOENT else { throw QueueStoreFailure.unavailable }
      return
    }
    let snapshot = try read(id: id)
    guard snapshot.assetID == assetID, snapshot.version == version else {
      throw QueueStoreFailure.corrupt
    }
    let handle = try workspace.reopen(id: id)
    try workspace.remove(handle)
  }

  private func verifyAttributes(id: WorkspaceID, role: PrivateArtifactRole) throws {
    let url = root.appending(path: id.description, directoryHint: .isDirectory)
      .appending(path: role.ownedFilename)
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard values.isExcludedFromBackup == true else {
      throw PrivateWorkspaceFailureCode.backupExclusionFailed
    }
    try protection.verify(url)
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
