import Darwin
import Foundation
import UIKit

enum AudioFingerprintFailure: Error, Equatable {
  case protectedDataUnavailable
  case invalidAudio
}

private enum CandidateFileFailure: Error {
  case invalidSize
  case invalidBackupAttribute
  case invalidProtectionAttribute
  case sizeChanged
  case temporaryMismatch
  case publishedMismatch
  case invalidWorkspace
}

enum CandidateWritePoint: CaseIterable, Equatable {
  case temporaryWritten
  case temporaryVerified
  case published
  case publishedVerified
}

protocol CandidateProtectionPolicy {
  func apply(to url: URL, manager: FileManager) throws
  func verify(to url: URL, manager: FileManager) throws
}

struct AppleCandidateProtectionPolicy: CandidateProtectionPolicy {
  func apply(to url: URL, manager: FileManager) throws {
    try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    try verify(to: url, manager: manager)
  }

  func verify(to url: URL, manager: FileManager) throws {
    let attributes = try manager.attributesOfItem(atPath: url.path)
    guard attributes[.protectionKey] as? FileProtectionType == .complete else {
      throw CandidateFileFailure.invalidProtectionAttribute
    }
  }
}

@MainActor
protocol CaptureAudioFingerprintSource {
  func fingerprint(for job: QueueJob) throws -> String
}

private struct StoredTranscriptionCandidate: Codable, Equatable {
  let schema: Int
  let jobID: String
  let attemptID: UUID
  let generation: Int
  let language: CaptureLanguage
  let method: String
  let settings: [String: String]
  let modelIdentity: String?
  let conversionIdentity: String?
  let destinationRevision: Int
  let bodyRevision: Int
  let audioByteCount: Int64
  let audioDuration: TimeInterval
  let payload: TranscriptionPayload

  init(payload: TranscriptionPayload, request: TranscriptionRequest, job: QueueJob) throws {
    guard let method = job.selectedMethodID, let settings = job.effectiveSettings,
      job.state == .transcribing, job.id == request.jobID,
      job.attemptID == request.attemptID, job.attemptGeneration == request.generation,
      job.language == request.language, settings == request.settings.values,
      job.modelIdentity == request.settings.modelIdentity,
      job.conversionIdentity == request.settings.conversionIdentity,
      job.destinationRevision == request.destinationRevision,
      job.bodyRevision == request.bodyRevision
    else { throw QueueStoreFailure.corrupt }
    schema = 1
    jobID = job.id
    attemptID = request.attemptID
    generation = request.generation
    language = job.language
    self.method = method
    self.settings = settings
    modelIdentity = job.modelIdentity
    conversionIdentity = job.conversionIdentity
    destinationRevision = job.destinationRevision
    bodyRevision = job.bodyRevision
    audioByteCount = job.audioByteCount
    audioDuration = job.audioDuration
    self.payload = payload
  }

  func matches(_ job: QueueJob) -> Bool {
    schema == 1 && jobID == job.id && attemptID == job.attemptID
      && generation == job.attemptGeneration && language == job.language
      && method == job.selectedMethodID && settings == job.effectiveSettings
      && modelIdentity == job.modelIdentity && conversionIdentity == job.conversionIdentity
      && destinationRevision == job.destinationRevision && bodyRevision == job.bodyRevision
      && audioByteCount == job.audioByteCount && audioDuration == job.audioDuration
  }
}

/// Stores a single intermediate inside the validated M9 workspace; no path comes from a record.
@MainActor
// swiftlint:disable:next type_body_length
final class FileTranscriptionCandidateStore: TranscriptionCandidateStore {
  private static let filename = "transcription-result-v1.json"
  private static let maximumFileBytes = 8 * 1_024 * 1_024
  private let root: URL
  private let audio: any CaptureAudioFingerprintSource
  private let manager: FileManager
  private let protection: any CandidateProtectionPolicy
  private let failureInjector: ((CandidateWritePoint) throws -> Void)?
  private let protectedDataAvailable: () -> Bool

  init(
    root: URL, audio: any CaptureAudioFingerprintSource, manager: FileManager = .default,
    protection: any CandidateProtectionPolicy = AppleCandidateProtectionPolicy(),
    failureInjector: ((CandidateWritePoint) throws -> Void)? = nil,
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
  ) {
    self.root = root
    self.audio = audio
    self.manager = manager
    self.protection = protection
    self.failureInjector = failureInjector
    self.protectedDataAvailable = protectedDataAvailable
  }

  func publish(
    _ payload: TranscriptionPayload, request: TranscriptionRequest, job: QueueJob
  ) throws {
    guard protectedDataAvailable(), valid(payload) else { throw QueueStoreFailure.unavailable }
    let record = try StoredTranscriptionCandidate(payload: payload, request: request, job: job)
    guard validProvenance(record) else { throw QueueStoreFailure.corrupt }
    let fingerprint: String
    do {
      fingerprint = try audio.fingerprint(for: job)
    } catch AudioFingerprintFailure.invalidAudio {
      throw TranscriptionCandidateFailure.invalidSource
    }
    guard fingerprint == payload.sourceDigest else {
      throw TranscriptionCandidateFailure.invalidSource
    }
    let destination = try candidateURL(job.id)
    let data = try JSONEncoder().encode(record)
    guard data.count <= Self.maximumFileBytes else { throw QueueStoreFailure.corrupt }
    if manager.fileExists(atPath: destination.path) {
      guard try read(destination) == record else {
        throw QueueStoreFailure.corrupt
      }
      try requireVerifiedCandidate(job: job, payload: payload)
      return
    }
    let temporary = destination.deletingLastPathComponent().appending(
      path: ".result-\(UUID().uuidString.lowercased())")
    defer { try? manager.removeItem(at: temporary) }
    try data.write(to: temporary, options: [.withoutOverwriting, .completeFileProtection])
    try applyAttributes(temporary)
    try failureInjector?(.temporaryWritten)
    guard try read(temporary) == record else { throw CandidateFileFailure.temporaryMismatch }
    try failureInjector?(.temporaryVerified)
    try manager.moveItem(at: temporary, to: destination)
    try applyAttributes(destination)
    try failureInjector?(.published)
    try requireVerifiedCandidate(job: job, payload: payload)
    try failureInjector?(.publishedVerified)
  }

  private func requireVerifiedCandidate(job: QueueJob, payload: TranscriptionPayload) throws {
    switch try inspect(job: job) {
    case .verified: return
    case .protectedDataUnavailable: throw TranscriptionCandidateFailure.protectedDataUnavailable
    case .missing: throw CandidateFileFailure.publishedMismatch
    case .invalid:
      do {
        guard try audio.fingerprint(for: job) == payload.sourceDigest else {
          throw TranscriptionCandidateFailure.invalidSource
        }
      } catch AudioFingerprintFailure.invalidAudio {
        throw TranscriptionCandidateFailure.invalidSource
      }
      throw CandidateFileFailure.publishedMismatch
    }
  }

  func inspect(job: QueueJob) throws -> CandidateInspection {
    guard protectedDataAvailable() else { return .protectedDataUnavailable }
    let destination: URL
    do {
      destination = try candidateURL(job.id)
    } catch CandidateFileFailure.invalidWorkspace {
      return protectedDataAvailable() ? .invalid : .protectedDataUnavailable
    }
    guard manager.fileExists(atPath: destination.path) else {
      return protectedDataAvailable() ? .missing : .protectedDataUnavailable
    }
    let record: StoredTranscriptionCandidate
    do {
      record = try read(destination)
    } catch {
      if isProtectionError(error) {
        return .protectedDataUnavailable
      }
      return .invalid
    }
    guard record.matches(job), valid(record.payload), validProvenance(record) else {
      return .invalid
    }
    do {
      return try audio.fingerprint(for: job) == record.payload.sourceDigest ? .verified : .invalid
    } catch AudioFingerprintFailure.protectedDataUnavailable {
      return .protectedDataUnavailable
    } catch AudioFingerprintFailure.invalidAudio {
      return .invalid
    }
  }

  func discard(job: QueueJob) throws {
    let destination: URL
    do {
      destination = try candidateURL(job.id)
    } catch CandidateFileFailure.invalidWorkspace {
      guard protectedDataAvailable() else {
        throw TranscriptionCandidateFailure.protectedDataUnavailable
      }
      return
    }
    guard manager.fileExists(atPath: destination.path) else { return }
    try requirePlainFile(destination)
    if job.state == .resultReady {
      guard let record = try? read(destination), record.matches(job) else {
        throw QueueStoreFailure.corrupt
      }
    }
    try manager.removeItem(at: destination)
  }

  func readVerified(job: QueueJob) throws -> TranscriptionPayload {
    guard job.state == .resultReady else { throw QueueStoreFailure.corrupt }
    let inspection = try inspect(job: job)
    if inspection == .protectedDataUnavailable {
      throw TranscriptionCandidateFailure.protectedDataUnavailable
    }
    guard inspection == .verified else {
      throw QueueStoreFailure.corrupt
    }
    do {
      let record = try read(candidateURL(job.id))
      guard record.matches(job), valid(record.payload), validProvenance(record),
        try audio.fingerprint(for: job) == record.payload.sourceDigest
      else { throw QueueStoreFailure.corrupt }
      return record.payload
    } catch AudioFingerprintFailure.protectedDataUnavailable {
      throw TranscriptionCandidateFailure.protectedDataUnavailable
    } catch AudioFingerprintFailure.invalidAudio {
      throw QueueStoreFailure.corrupt
    } catch {
      if isProtectionError(error) { throw TranscriptionCandidateFailure.protectedDataUnavailable }
      throw error
    }
  }

  private func isProtectionError(_ error: any Error) -> Bool {
    let cocoaError = error as NSError
    let denied =
      cocoaError.domain == NSCocoaErrorDomain
      && cocoaError.code == NSFileReadNoPermissionError
    return !protectedDataAvailable() || denied
  }

  private func candidateURL(_ id: String) throws -> URL {
    guard let workspace = try? WorkspaceID(id) else { throw QueueStoreFailure.corrupt }
    try requirePlainDirectory(root)
    let directory = root.appending(path: workspace.description, directoryHint: .isDirectory)
    do { try requirePlainDirectory(directory) } catch {
      throw CandidateFileFailure.invalidWorkspace
    }
    return directory.appending(path: Self.filename, directoryHint: .notDirectory)
  }

  private func read(_ url: URL) throws -> StoredTranscriptionCandidate {
    try requirePlainFile(url)
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      if errno == EACCES || errno == EPERM { throw CocoaError(.fileReadNoPermission) }
      throw QueueStoreFailure.unsafeResource
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var before = stat()
    var path = stat()
    guard fstat(descriptor, &before) == 0, lstat(url.path, &path) == 0,
      sameFile(before, path), (before.st_mode & S_IFMT) == S_IFREG, before.st_nlink == 1,
      before.st_size > 0, before.st_size <= Int64(Self.maximumFileBytes)
    else { throw CandidateFileFailure.invalidSize }
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard values.isExcludedFromBackup == true else {
      throw CandidateFileFailure.invalidBackupAttribute
    }
    try protection.verify(to: url, manager: manager)
    var data = Data()
    while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
      guard chunk.count <= Self.maximumFileBytes - data.count else {
        throw CandidateFileFailure.invalidSize
      }
      data.append(chunk)
    }
    var after = stat()
    guard fstat(descriptor, &after) == 0, lstat(url.path, &path) == 0,
      sameFile(before, after), sameFile(after, path), data.count == Int(before.st_size)
    else { throw CandidateFileFailure.sizeChanged }
    return try JSONDecoder().decode(StoredTranscriptionCandidate.self, from: data)
  }

  private func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
  }

  private func applyAttributes(_ url: URL) throws {
    var mutable = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try mutable.setResourceValues(values)
    try protection.apply(to: url, manager: manager)
  }

  private func requirePlainDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw QueueStoreFailure.unsafeResource
    }
  }

  private func requirePlainFile(_ url: URL) throws {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey]
    let values = try url.resourceValues(forKeys: keys)
    var metadata = stat()
    guard values.isRegularFile == true, values.isSymbolicLink == false,
      values.isAliasFile != true, lstat(url.path, &metadata) == 0,
      metadata.st_nlink == 1
    else { throw QueueStoreFailure.unsafeResource }
  }

  private func valid(_ payload: TranscriptionPayload) -> Bool {
    let digest = payload.sourceDigest
    let text = payload.text
    guard digest.utf8.count == 64,
      digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      !text.isEmpty, text.utf8.count <= DiaryBody.maximumBytes,
      text == text.trimmingCharacters(in: .whitespacesAndNewlines),
      text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
    else { return false }
    return [
      // swiftlint:disable:next trailing_comma
      payload.resolvedLocale, payload.runtime, payload.conversion, payload.operatingSystemVersion,
    ]
    .allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }
  }

  private func validProvenance(_ record: StoredTranscriptionCandidate) -> Bool {
    guard record.conversionIdentity == record.payload.conversion else { return false }
    let settings = record.settings
    switch record.method {
    case TranscriptionMethodIdentifiers.apple:
      return record.modelIdentity == nil
        && settings["settingsRevision"] == "1"
        && settings["requestedLocale"] == record.language.rawValue
        && settings["resolvedLocale"] == record.payload.resolvedLocale
        && settings["preset"] == "transcription"
        && settings["resultPolicy"] == "final-only"
        && settings["runtime"] == record.payload.runtime
        && settings["operatingSystemVersion"] == record.payload.operatingSystemVersion
    case TranscriptionMethodIdentifiers.cohere:
      let descriptor = CohereTrustedModel.production
      let expectedHint = record.language == .english ? "en" : "ko"
      return record.modelIdentity == descriptor.installationIdentity
        && settings["settingsRevision"] == "1"
        && settings["requestedLocale"] == record.language.rawValue
        && settings["resolvedLocale"] == record.payload.resolvedLocale
        && settings["languageHint"] == expectedHint
        && settings["backend"] == "metal"
        && settings["runtime"] == record.payload.runtime
        && settings["runtimeCommit"] == CohereRuntimeProvenance.commit
        && settings["modelID"] == descriptor.modelID
        && settings["modelRevision"] == descriptor.repositoryRevision
        && settings["quantization"] == descriptor.quantization
        && settings["chunkingRevision"] == CohereChunkPlanner.identity
        && settings["installedIdentity"] == descriptor.installationIdentity
        && settings["operatingSystemVersion"] == record.payload.operatingSystemVersion
    default:
      return false
    }
  }
}
