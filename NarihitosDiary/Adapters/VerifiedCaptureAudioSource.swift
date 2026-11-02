import AVFAudio
import CryptoKit
import Darwin
import Foundation
import UIKit

// swiftlint:disable opening_brace

/// Adapter-private lease for the positively identified M9 audio file.
@MainActor
final class VerifiedCaptureAudio: AppleSpeechAudioLease, CohereAudioLease {
  let url: URL
  let digest: String
  private let handle: FileHandle
  private let initial: stat

  init(url: URL, digest: String, handle: FileHandle, initial: stat) {
    self.url = url
    self.digest = digest
    self.handle = handle
    self.initial = initial
  }

  func verifyUnchanged() throws {
    var current = stat()
    var path = stat()
    guard fstat(handle.fileDescriptor, &current) == 0,
      lstat(url.path, &path) == 0,
      Self.sameFile(initial, current), Self.sameFile(current, path)
    else { throw AudioFingerprintFailure.invalidAudio }
  }

  func close() throws { try handle.close() }

  func openAudioFile() throws -> AVAudioFile {
    do { return try AVAudioFile(forReading: url) } catch {
      throw AudioFingerprintFailure.invalidAudio
    }
  }

  private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
  }
}

@MainActor
final class VerifiedCaptureAudioSource:
  CaptureAudioFingerprintSource, AppleSpeechAudioSource, CohereAudioSource
{
  private let files: CapturePrivateFiles
  private let protectedDataAvailable: () -> Bool

  init(
    files: CapturePrivateFiles,
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
  ) {
    self.files = files
    self.protectedDataAvailable = protectedDataAvailable
  }

  func fingerprint(for job: QueueJob) throws -> String {
    let lease = try open(job: job)
    defer { try? lease.close() }
    return lease.digest
  }

  func openForSpeech(job: QueueJob) throws -> any AppleSpeechAudioLease {
    try open(job: job)
  }

  func openForCohere(job: QueueJob) throws -> any CohereAudioLease {
    try open(job: job)
  }

  func open(job: QueueJob) throws -> VerifiedCaptureAudio {
    guard protectedDataAvailable() else {
      throw AudioFingerprintFailure.protectedDataUnavailable
    }
    do {
      return try openAccessible(job: job)
    } catch let failure as AudioFingerprintFailure {
      throw failure
    } catch {
      guard protectedDataAvailable() else {
        throw AudioFingerprintFailure.protectedDataUnavailable
      }
      throw AudioFingerprintFailure.invalidAudio
    }
  }

  private func openAccessible(job: QueueJob) throws -> VerifiedCaptureAudio {
    guard let id = try? WorkspaceID(job.id), let receipt = files.queueReceipt(jobID: job.id),
      job.matches(receipt), receipt.inspection.isAccepted,
      receipt.inspection.channelCount == job.audioChannelCount,
      receipt.inspection.sampleRate == job.audioSampleRate
    else { throw AudioFingerprintFailure.invalidAudio }
    let directory = files.root.appending(path: id.description, directoryHint: .isDirectory)
    try requireDirectory(files.root)
    try requireDirectory(directory)
    let url = directory.appending(path: "pending-audio.m4a", directoryHint: .notDirectory)
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw AudioFingerprintFailure.invalidAudio }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var initial = stat()
    var path = stat()
    guard fstat(descriptor, &initial) == 0, lstat(url.path, &path) == 0,
      (initial.st_mode & S_IFMT) == S_IFREG, initial.st_nlink == 1,
      initial.st_dev == path.st_dev, initial.st_ino == path.st_ino,
      initial.st_size == job.audioByteCount, initial.st_size > 0,
      initial.st_size <= CapturePrivateFiles.maximumAudioBytes
    else { throw AudioFingerprintFailure.invalidAudio }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
      hash.update(data: data)
    }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    let lease = VerifiedCaptureAudio(url: url, digest: digest, handle: handle, initial: initial)
    try lease.verifyUnchanged()
    return lease
  }

  private func requireDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw AudioFingerprintFailure.invalidAudio
    }
  }
}

// swiftlint:enable opening_brace
