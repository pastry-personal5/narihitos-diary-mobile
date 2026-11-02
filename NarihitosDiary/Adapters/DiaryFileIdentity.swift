import CryptoKit
import Darwin
import Foundation

enum DiaryFileIdentity {
  static func sameVersion(_ lhs: stat, _ rhs: stat) -> Bool {
    sameContentVersion(lhs, rhs)
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
  }

  /// Metadata-only races are transient; content or resource changes remain
  /// conflicts. Persistent version identity still includes ctime.
  static func requireStableRead(_ before: stat, _ after: stat) throws {
    guard sameContentVersion(before, after) else { throw DiaryFileObservationFailure.changed }
    guard sameVersion(before, after) else { throw DiaryFileObservationFailure.unavailable }
  }

  private static func sameContentVersion(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
  }

  /// Used only to classify a post-read metadata race, never as upload proof.
  static func contentVersionIdentity(_ value: stat) -> String {
    let raw =
      "\(value.st_dev):\(value.st_ino):\(value.st_size):"
      + "\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec)"
    return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func versionIdentity(_ value: stat) -> String {
    let raw =
      "\(value.st_dev):\(value.st_ino):\(value.st_size):"
      + "\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):"
      + "\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
