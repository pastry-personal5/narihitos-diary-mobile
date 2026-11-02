import AVFAudio
import Foundation
import UIKit

// swift-format's multiline collections conflict with SwiftLint's trailing-comma rule.
// Capture persistence intentionally keeps its journal and verification logic together.
// swiftlint:disable trailing_comma file_length

private struct CaptureJournal: Codable, Equatable {
  let id: String
  let startedAt: Date
  let language: CaptureLanguage
  let destinationReference: UUID
  let installationBinding: String?
  let outcome: String?
  let failureReason: String?
  let inspection: CaptureInspection?

  func identity() throws -> CaptureIdentity {
    CaptureIdentity(
      id: try WorkspaceID(id), startedAt: startedAt, language: language,
      destinationReference: destinationReference, installationBinding: installationBinding)
  }
}

struct CaptureRecoveryIssue: Identifiable, Equatable {
  let id: String
  let reason: String
}

enum CaptureWriteFailurePoint {
  case beforeCommit
  case afterCommit
}

@MainActor
final class CapturePrivateFiles {
  static let maximumAudioBytes: Int64 = 64 * 1_024 * 1_024
  private let manager: FileManager
  private let protection: any CaptureProtectionPolicy
  private let failureInjector: ((CaptureWriteFailurePoint, URL) throws -> Void)?
  let root: URL

  init(
    manager: FileManager = .default, root: URL? = nil,
    protection: any CaptureProtectionPolicy = AppleCaptureProtectionPolicy(),
    failureInjector: ((CaptureWriteFailurePoint, URL) throws -> Void)? = nil
  ) {
    self.manager = manager
    self.protection = protection
    self.failureInjector = failureInjector
    self.root =
      root
      ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "NarihitosDiary/Captures", directoryHint: .isDirectory)
    try? manager.createDirectory(at: self.root, withIntermediateDirectories: true)
    try? setPrivateAttributes(self.root, open: false)
  }

  func saveSnapshot(_ record: StoredDestinationRecord) throws -> UUID {
    let id = UUID()
    let data = try JSONEncoder().encode(record)
    guard data.count <= 96 * 1_024 else { throw CaptureGateFailure.destination }
    try writeNew(data, to: snapshotURL(id))
    return id
  }

  func createWorkspace(_ identity: CaptureIdentity) throws {
    guard hasSnapshot(identity.destinationReference) else {
      throw CaptureGateFailure.destination
    }
    let directory = workspaceURL(identity.id)
    try requirePlainDirectory(root)
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    try setPrivateAttributes(directory, open: false)
    let marker = CaptureJournal(
      id: identity.id.description, startedAt: identity.startedAt,
      language: identity.language, destinationReference: identity.destinationReference,
      installationBinding: identity.installationBinding,
      outcome: nil, failureReason: nil, inspection: nil)
    try writeNew(JSONEncoder().encode(marker), to: directory.appending(path: "capture.json"))
  }

  func prepareAudio(id: WorkspaceID) throws -> URL {
    let directory = workspaceURL(id)
    try requirePlainDirectory(directory)
    let url = audioURL(id)
    guard !manager.fileExists(atPath: url.path) else { throw CaptureGateFailure.storage }
    return url
  }

  func protectOpenAudio(id: WorkspaceID) throws {
    let url = audioURL(id)
    try requirePlainFile(url)
    try setPrivateAttributes(url, open: true)
  }

  func inspectAudio(id: WorkspaceID) throws -> CaptureInspection {
    let url = audioURL(id)
    try requirePlainFile(url)
    let attributes = try manager.attributesOfItem(atPath: url.path)
    let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    // The recorder has closed by this point. Apply closed-file protection even
    // when the bytes are empty or exceed the accepted capture limit.
    try setPrivateAttributes(url, open: false)
    guard bytes > 0, bytes <= Self.maximumAudioBytes else {
      return CaptureInspection(byteCount: bytes, duration: 0, isMonoAAC: false, isPlayable: false)
    }
    do {
      let file = try AVAudioFile(forReading: url)
      let settings = file.fileFormat.settings
      let format = (settings[AVFormatIDKey] as? NSNumber)?.uint32Value
      let channels = (settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue
      let sampleRate = file.fileFormat.sampleRate
      let player = try AVAudioPlayer(contentsOf: url)
      guard (8_000...96_000).contains(sampleRate), file.length > 0,
        Double(file.length) <= 301 * sampleRate
      else {
        return CaptureInspection(
          byteCount: bytes, duration: 0, isMonoAAC: false, isPlayable: false)
      }
      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096)
      guard let buffer else {
        return CaptureInspection(
          byteCount: bytes, duration: 0, isMonoAAC: false, isPlayable: false)
      }
      var decodedFrames: AVAudioFramePosition = 0
      while decodedFrames < file.length {
        let remaining = file.length - decodedFrames
        let count = AVAudioFrameCount(min(remaining, 4_096))
        try file.read(into: buffer, frameCount: count)
        guard buffer.frameLength > 0 else {
          return CaptureInspection(
            byteCount: bytes, duration: 0, isMonoAAC: false, isPlayable: false)
        }
        decodedFrames += AVAudioFramePosition(buffer.frameLength)
      }
      return CaptureInspection(
        byteCount: bytes, duration: player.duration,
        isMonoAAC: format == kAudioFormatMPEG4AAC && channels == 1,
        isPlayable: player.prepareToPlay(), sampleRate: sampleRate,
        channelCount: channels, codecIdentifier: format,
        approximateBitRate: player.duration > 0
          ? Int(Double(bytes) * 8 / player.duration) : nil)
    } catch {
      return CaptureInspection(
        byteCount: bytes, duration: 0, isMonoAAC: false, isPlayable: false)
    }
  }

  func audioBytes(id: WorkspaceID) -> Int64? {
    guard let attributes = try? manager.attributesOfItem(atPath: audioURL(id).path)
    else { return nil }
    return (attributes[.size] as? NSNumber)?.int64Value
  }

  func saveOutcome(_ identity: CaptureIdentity, inspection: CaptureInspection) throws -> Bool {
    let verifiedPending = inspection.isAccepted && hasSnapshot(identity.destinationReference)
    let journal = CaptureJournal(
      id: identity.id.description, startedAt: identity.startedAt,
      language: identity.language, destinationReference: identity.destinationReference,
      installationBinding: identity.installationBinding,
      outcome: verifiedPending ? "pending" : "failed",
      failureReason: verifiedPending ? nil : "This recording can’t be read.",
      inspection: inspection)
    do {
      try writeNew(
        JSONEncoder().encode(journal),
        to: workspaceURL(identity.id).appending(path: "receipt.json"))
    } catch {
      guard validatedReceipt(id: identity.id) == journal else { throw error }
    }
    guard validatedReceipt(id: identity.id) == journal else {
      throw CaptureGateFailure.storage
    }
    return verifiedPending
  }

  func reconcile() -> [CaptureIdentity] {
    var recovered: [CaptureIdentity] = []
    for id in workspaceIDs() {
      guard UIApplication.shared.isProtectedDataAvailable else { continue }
      let storedMarker = readJournal(id: id, name: "capture.json")
      let marker = storedMarker ?? repairMarkerAttributes(id: id)
      guard let marker, let identity = try? marker.identity()
      else { continue }
      if readJournal(id: id, name: "receipt.json") != nil { continue }
      if repairReceiptAttributes(id: id, marker: marker) {
        recovered.append(identity)
        continue
      }
      guard !manager.fileExists(atPath: workspaceURL(id).appending(path: "receipt.json").path)
      else { continue }
      // A missing, inaccessible, or substituted file is unresolved state. Only an
      // inspected file can be classified as an unreadable recording.
      guard let inspection = try? inspectAudio(id: id) else { continue }
      guard (try? saveOutcome(identity, inspection: inspection)) != nil else { continue }
      recovered.append(identity)
    }
    return recovered
  }

  func list(outcome: String) -> [CaptureIdentity] {
    workspaceIDs().compactMap { id in
      guard let journal = validatedReceipt(id: id),
        journal.outcome == outcome
      else { return nil }
      return try? journal.identity()
    }
    .sorted { $0.startedAt < $1.startedAt }
  }

  func issues() -> [CaptureRecoveryIssue] {
    guard UIApplication.shared.isProtectedDataAvailable else { return [] }
    return workspaceIDs().compactMap { id in
      let marker = readJournal(id: id, name: "capture.json")
      guard validatedReceipt(id: id) == nil else { return nil }
      return CaptureRecoveryIssue(
        id: id.description,
        reason: marker == nil ? "This recording needs review." : "Local recovery is pending.")
    }
  }

  func pendingQueueReceipts() -> [QueueReceipt] {
    workspaceIDs().compactMap { id in
      queueReceipt(jobID: id.description)
    }.sorted {
      $0.startedAt == $1.startedAt
        ? $0.id.description < $1.id.description : $0.startedAt < $1.startedAt
    }
  }

  func queueReceipt(jobID: String) -> QueueReceipt? {
    guard let id = try? WorkspaceID(jobID),
      (try? requirePlainDirectory(root)) != nil,
      (try? requirePlainDirectory(workspaceURL(id))) != nil,
      let journal = validatedReceipt(id: id), journal.outcome == "pending",
      let inspection = journal.inspection, inspection.isAccepted,
      let identity = try? journal.identity()
    else { return nil }
    return QueueReceipt(
      id: identity.id, startedAt: identity.startedAt, language: identity.language,
      destinationReference: identity.destinationReference,
      installationBinding: identity.installationBinding, inspection: inspection)
  }

  func removeWorkspace(jobID: String) throws {
    let id = try WorkspaceID(jobID)
    let directory = workspaceURL(id)
    try requirePlainDirectory(root)
    guard manager.fileExists(atPath: directory.path) else { return }
    try requirePlainDirectory(directory)
    let children = try manager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey])
    for child in children {
      let values = try child.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
      ])
      guard isOwnedCaptureFile(child.lastPathComponent), values.isRegularFile == true,
        values.isSymbolicLink == false, values.isAliasFile != true
      else {
        throw CaptureGateFailure.storage
      }
    }
    try manager.removeItem(at: directory)
  }

  private func isOwnedCaptureFile(_ name: String) -> Bool {
    let fixed = [
      "capture.json", "receipt.json", "pending-audio.m4a", "transcription-result-v1.json",
      PrivateArtifactRole.markdownDraft.ownedFilename,
      PrivateArtifactRole.draftBinding.ownedFilename,
      ".recovery-\(PrivateArtifactRole.markdownDraft.rawValue)",
      ".recovery-\(PrivateArtifactRole.draftBinding.rawValue)",
    ]
    if fixed.contains(name) { return true }
    for prefix in [".write-", ".result-"] where name.hasPrefix(prefix) {
      let suffix = String(name.dropFirst(prefix.count))
      guard let id = UUID(uuidString: suffix) else { return false }
      return id.uuidString.lowercased() == suffix
    }
    return false
  }

}

extension CapturePrivateFiles {
  private func validatedReceipt(id: WorkspaceID) -> CaptureJournal? {
    guard let marker = readJournal(id: id, name: "capture.json"),
      let receipt = readJournal(id: id, name: "receipt.json"),
      marker.startedAt == receipt.startedAt,
      marker.language == receipt.language,
      marker.destinationReference == receipt.destinationReference,
      marker.installationBinding == receipt.installationBinding,
      let measured = receipt.inspection,
      receipt.outcome == "pending" || receipt.outcome == "failed",
      (try? requirePlainFile(audioURL(id))) != nil
    else { return nil }
    if receipt.outcome == "pending" {
      guard UIApplication.shared.isProtectedDataAvailable,
        hasSnapshot(receipt.destinationReference),
        (try? verifyPrivateAttributes(audioURL(id), open: false)) != nil,
        let observed = try? inspectAudio(id: id),
        observed.isAccepted,
        observed.byteCount == measured.byteCount,
        abs(observed.duration - measured.duration) < 0.25
      else { return nil }
    }
    return receipt
  }

  private func workspaceIDs() -> [WorkspaceID] {
    guard
      let children = try? manager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    else { return [] }
    return children.compactMap { url in
      guard (try? requirePlainDirectory(url)) != nil else { return nil }
      return try? WorkspaceID(url.lastPathComponent)
    }
  }

  private func readJournal(id: WorkspaceID, name: String) -> CaptureJournal? {
    let url = workspaceURL(id).appending(path: name)
    guard (try? requirePlainFile(url)) != nil,
      (try? verifyPrivateAttributes(url, open: false)) != nil
    else { return nil }
    return rawJournal(id: id, name: name)
  }

  private func rawJournal(id: WorkspaceID, name: String) -> CaptureJournal? {
    let url = workspaceURL(id).appending(path: name)
    guard (try? requirePlainFile(url)) != nil,
      let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
      size <= 4096, let data = try? Data(contentsOf: url)
    else { return nil }
    guard let journal = try? JSONDecoder().decode(CaptureJournal.self, from: data),
      journal.id == id.description
    else { return nil }
    return journal
  }

  private func repairReceiptAttributes(id: WorkspaceID, marker: CaptureJournal) -> Bool {
    guard let receipt = rawJournal(id: id, name: "receipt.json"),
      receipt.startedAt == marker.startedAt,
      receipt.language == marker.language,
      receipt.destinationReference == marker.destinationReference
        && receipt.installationBinding == marker.installationBinding
    else { return false }
    let url = workspaceURL(id).appending(path: "receipt.json")
    guard (try? setPrivateAttributes(url, open: false)) != nil else { return false }
    return validatedReceipt(id: id) != nil
  }

  private func repairMarkerAttributes(id: WorkspaceID) -> CaptureJournal? {
    guard let marker = rawJournal(id: id, name: "capture.json"),
      hasSnapshot(marker.destinationReference)
    else { return nil }
    let url = workspaceURL(id).appending(path: "capture.json")
    guard (try? setPrivateAttributes(url, open: false)) != nil else { return nil }
    return readJournal(id: id, name: "capture.json")
  }

  private func hasSnapshot(_ id: UUID) -> Bool {
    let url = snapshotURL(id)
    guard (try? requirePlainFile(url)) != nil,
      (try? verifyPrivateAttributes(url, open: false)) != nil,
      let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
      size > 0, size <= 96 * 1_024,
      let data = try? Data(contentsOf: url),
      let record = try? JSONDecoder().decode(StoredDestinationRecord.self, from: data)
    else { return false }
    return DestinationID(rawValue: record.id) != nil && record.disclosureAcknowledged
      && !record.bookmark.isEmpty
      && record.bookmark.count <= AppleDestinationService.maximumBookmarkSize
      && !record.identityArchive.isEmpty
      && record.identityArchive.count <= AppleDestinationService.maximumIdentityArchiveSize
  }

  private func workspaceURL(_ id: WorkspaceID) -> URL {
    root.appending(path: id.description, directoryHint: .isDirectory)
  }

  private func audioURL(_ id: WorkspaceID) -> URL {
    workspaceURL(id).appending(path: "pending-audio.m4a")
  }

  private func snapshotURL(_ id: UUID) -> URL {
    root.appending(path: "snapshot-\(id.uuidString.lowercased()).json")
  }

  private func writeNew(_ data: Data, to url: URL) throws {
    try requirePlainDirectory(url.deletingLastPathComponent())
    guard !manager.fileExists(atPath: url.path) else { throw CaptureGateFailure.storage }
    let temporary = url.deletingLastPathComponent().appending(
      path: ".write-\(UUID().uuidString.lowercased())")
    try data.write(
      to: temporary,
      options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
    try setPrivateAttributes(temporary, open: false)
    guard try Data(contentsOf: temporary) == data else { throw CaptureGateFailure.storage }
    try failureInjector?(.beforeCommit, url)
    try manager.moveItem(at: temporary, to: url)
    try failureInjector?(.afterCommit, url)
    try setPrivateAttributes(url, open: false)
    guard try Data(contentsOf: url) == data else { throw CaptureGateFailure.storage }
  }

  private func setPrivateAttributes(_ url: URL, open: Bool) throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutable = url
    try mutable.setResourceValues(values)
    let verify = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard verify.isExcludedFromBackup == true else { throw CaptureGateFailure.storage }
    try protection.applyAndVerify(to: url, open: open, manager: manager)
  }

  private func verifyPrivateAttributes(_ url: URL, open: Bool) throws {
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard values.isExcludedFromBackup == true else { throw CaptureGateFailure.storage }
    try protection.verify(to: url, open: open, manager: manager)
  }

  private func requirePlainDirectory(_ url: URL) throws {
    let value = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard value.isDirectory == true, value.isSymbolicLink == false else {
      throw CaptureGateFailure.storage
    }
  }

  private func requirePlainFile(_ url: URL) throws {
    let value = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
    ])
    guard value.isRegularFile == true, value.isSymbolicLink == false,
      value.isAliasFile != true
    else { throw CaptureGateFailure.storage }
  }
}

// swiftlint:enable trailing_comma file_length
