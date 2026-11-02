import CryptoKit
import Darwin
import Foundation

enum DiaryFileIdentity {
  static func sameVersion(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
  }

  static func versionIdentity(_ value: stat) -> String {
    let raw =
      "\(value.st_dev):\(value.st_ino):\(value.st_size):"
      + "\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):"
      + "\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
