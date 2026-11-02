import Darwin
import Foundation

/// A best-effort local creation receipt. It proves a retry sees the same inode
/// created under a durable intent; unsupported provider metadata stays unsafe.
enum DiaryFileCreationMarker {
  private static let name = "com.narihitosdiary.commit-creation"

  static func set(descriptor: Int32, token: UUID) {
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { return }
    let bytes = Array(value(token, file: info).utf8)
    bytes.withUnsafeBytes { raw in
      _ = fsetxattr(descriptor, name, raw.baseAddress, bytes.count, 0, 0)
    }
  }

  static func matches(_ token: UUID, at url: URL) -> Bool {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return false }
    defer { Darwin.close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0,
      (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1
    else { return false }
    let length = fgetxattr(descriptor, name, nil, 0, 0, 0)
    guard length > 0, length <= 128 else { return false }
    var bytes = [UInt8](repeating: 0, count: length)
    let expectedCount = bytes.count
    let count = bytes.withUnsafeMutableBytes { raw in
      fgetxattr(descriptor, name, raw.baseAddress, expectedCount, 0, 0)
    }
    return count == expectedCount
      && String(bytes: bytes, encoding: .utf8) == value(token, file: info)
  }

  private static func value(_ token: UUID, file: stat) -> String {
    "\(token.uuidString.lowercased()):\(file.st_dev):\(file.st_ino)"
  }
}
