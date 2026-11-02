import CryptoKit
import Darwin
import Foundation

// swift-format requires a trailing comma for multiline collections.
// swiftlint:disable trailing_comma

enum DiaryFileObservationFailure: Error {
  case unavailable
  case unsafeResource
  case changed
}

struct DiaryFileObservation: Equatable, Sendable {
  let identity: String
  let digest: String
  let byteCount: Int64
  let uploaded: Bool
  let modifiedAt: Date?
  let hasUnresolvedConflict: Bool
}

protocol DiaryFileObserverPort: Sendable {
  func observe(_ url: URL, maximumBytes: Int64) throws -> DiaryFileObservation
  func observeBounded(
    _ url: URL, maximumBytes: Int64, timeout: Duration
  ) async throws -> DiaryFileObservation
}

/// Reads a coordinated file without following a symlink and binds the provider
/// upload flag to the same local file version whose bytes were hashed.
struct AppleDiaryFileObserver: DiaryFileObserverPort {
  func observeBounded(
    _ url: URL, maximumBytes: Int64, timeout: Duration
  ) async throws -> DiaryFileObservation {
    try requireOriginalFile(url)
    let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
    let observation = try await BoundedFileCoordinator().perform(
      intents: [intent], timeout: timeout
    ) { urls in
      guard let coordinated = urls.first else {
        throw DiaryFileObservationFailure.unavailable
      }
      return try readCoordinated(coordinated, maximumBytes: maximumBytes)
    }
    try verifyOriginalFile(
      url, observation: observation.value, contentVersion: observation.contentVersion)
    return observation.value
  }

  func observe(_ url: URL, maximumBytes: Int64) throws -> DiaryFileObservation {
    try requireOriginalFile(url)
    var coordinationError: NSError?
    var result: Result<(value: DiaryFileObservation, contentVersion: String), Error>?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordinationError
    ) { coordinated in
      result = Result { try readCoordinated(coordinated, maximumBytes: maximumBytes) }
    }
    guard coordinationError == nil, let result else {
      throw DiaryFileObservationFailure.unavailable
    }
    let observation = try result.get()
    try verifyOriginalFile(
      url, observation: observation.value, contentVersion: observation.contentVersion)
    return observation.value
  }

  private func requireOriginalFile(_ url: URL) throws {
    var original = stat()
    guard lstat(url.path, &original) == 0 else {
      throw DiaryFileObservationFailure.unavailable
    }
    guard (original.st_mode & S_IFMT) == S_IFREG
    else { throw DiaryFileObservationFailure.unsafeResource }
  }

  private func verifyOriginalFile(
    _ url: URL, observation: DiaryFileObservation, contentVersion: String
  ) throws {
    var current = stat()
    guard lstat(url.path, &current) == 0,
      (current.st_mode & S_IFMT) == S_IFREG, current.st_nlink == 1,
      DiaryFileIdentity.contentVersionIdentity(current) == contentVersion
    else { throw DiaryFileObservationFailure.changed }
    guard DiaryFileIdentity.versionIdentity(current) == observation.identity else {
      throw DiaryFileObservationFailure.unavailable
    }
  }

  private func readCoordinated(
    _ url: URL, maximumBytes: Int64
  ) throws -> (value: DiaryFileObservation, contentVersion: String) {
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
      .ubiquitousItemIsUploadedKey, .contentModificationDateKey,
    ]
    // Request provider metadata independently of the caller's cached values.
    var freshURL = URL(fileURLWithPath: url.path)
    freshURL.removeAllCachedResourceValues()
    let before = try freshURL.resourceValues(forKeys: keys)
    guard before.isRegularFile == true, before.isSymbolicLink == false
    else { throw DiaryFileObservationFailure.unsafeResource }
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
    while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
      bytesRead += Int64(data.count)
      guard bytesRead <= maximumBytes else { throw DiaryFileObservationFailure.changed }
      hasher.update(data: data)
    }
    var final = stat()
    var path = stat()
    guard fstat(descriptor, &final) == 0, lstat(url.path, &path) == 0,
      (path.st_mode & S_IFMT) == S_IFREG, path.st_nlink == 1,
      bytesRead == initial.st_size
    else { throw DiaryFileObservationFailure.changed }
    try DiaryFileIdentity.requireStableRead(initial, final)
    try DiaryFileIdentity.requireStableRead(final, path)
    freshURL.removeAllCachedResourceValues()
    let after = try freshURL.resourceValues(forKeys: keys)
    try requireStableMetadata(before, after)
    let hasUnresolvedConflict =
      !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.isEmpty ?? true)
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    let observation = DiaryFileObservation(
      identity: DiaryFileIdentity.versionIdentity(final), digest: digest,
      byteCount: final.st_size,
      uploaded: after.isUbiquitousItem == true && after.ubiquitousItemIsUploaded == true,
      modifiedAt: after.contentModificationDate,
      hasUnresolvedConflict: hasUnresolvedConflict)
    return (observation, DiaryFileIdentity.contentVersionIdentity(final))
  }

  private func requireStableMetadata(
    _ before: URLResourceValues, _ after: URLResourceValues
  ) throws {
    guard after.isRegularFile == true, after.isSymbolicLink == false else {
      throw DiaryFileObservationFailure.unsafeResource
    }
    guard before.isUbiquitousItem == after.isUbiquitousItem,
      before.ubiquitousItemIsUploaded == after.ubiquitousItemIsUploaded,
      before.contentModificationDate == after.contentModificationDate
    else { throw DiaryFileObservationFailure.unavailable }
  }

}

// swiftlint:enable trailing_comma
