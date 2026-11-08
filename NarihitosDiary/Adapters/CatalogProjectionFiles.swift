// swiftlint:disable trailing_comma
import Darwin
import Foundation

/// Only the projection's fixed file family is ever created or removed here.
struct CatalogProjectionFiles: Sendable {
  let root: URL
  let protection: any DraftFileProtectionPolicy

  func prepare() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try PurgeFileTree.identity(root)
    try protect(root)
    for name in ["catalog.sqlite", "catalog.sqlite-journal"] {
      let parent = try CatalogSafeFiles.descriptor(root: root, components: [], directory: true)
      defer { close(parent) }
      let descriptor = openat(parent, name, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw CatalogIndexFailure.unavailable }
      defer { close(descriptor) }
      var info = stat()
      guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1
      else {
        throw CatalogIndexFailure.unsafe
      }
      try protect(root.appending(path: name))
    }
    try verify()
  }

  func verify() throws {
    _ = try PurgeFileTree.identity(root)
    try protection.verify(root)
    var totalBytes: Int64 = 0
    for name in Self.names {
      let url = root.appending(path: name)
      var info = stat()
      guard lstat(url.path, &info) == 0 else {
        if errno == ENOENT { continue }
        throw CatalogIndexFailure.unavailable
      }
      guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
        throw CatalogIndexFailure.unsafe
      }
      guard info.st_size <= 64 * 1_024 * 1_024 else { throw CatalogIndexFailure.capacity }
      totalBytes += info.st_size
      guard totalBytes <= 128 * 1_024 * 1_024 else { throw CatalogIndexFailure.capacity }
      try protect(url)
    }
  }

  func discard() throws {
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    _ = try PurgeFileTree.identity(root)
    // Never follow a link or recursively remove an unexpected directory.
    for name in Self.names {
      let url = root.appending(path: name)
      var info = stat()
      guard lstat(url.path, &info) == 0 else {
        if errno == ENOENT { continue }
        throw CatalogIndexFailure.unavailable
      }
      guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
        throw CatalogIndexFailure.unsafe
      }
      try FileManager.default.removeItem(at: url)
    }
  }

  private func protect(_ url: URL) throws {
    try protection.applyAndVerify(to: url)
    var protectedURL = url
    var attributes = URLResourceValues()
    attributes.isExcludedFromBackup = true
    try protectedURL.setResourceValues(attributes)
    guard
      try protectedURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        == true
    else { throw CatalogIndexFailure.unavailable }
  }

  private static let names = [
    "catalog.sqlite", "catalog.sqlite-journal", "catalog.sqlite-wal", "catalog.sqlite-shm",
  ]
}

// swiftlint:enable trailing_comma
