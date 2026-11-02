import CryptoKit
import Darwin
import Foundation

/// Descriptor-relative traversal never resolves an external document's link components.
enum CatalogSafeFiles {
  static func descriptor(root: URL, components: [String], directory: Bool) throws -> Int32 {
    var descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw CatalogIssue.unavailable }
    do {
      for (index, component) in components.enumerated() {
        guard !component.isEmpty, component != ".", component != "..",
          !component.contains("/"), !component.contains("\\"), !component.contains("\0")
        else { throw CatalogIssue.unsafe }
        let isDirectory = index < components.count - 1 || directory
        let flags = O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (isDirectory ? O_DIRECTORY : 0)
        let next = openat(descriptor, component, flags)
        guard next >= 0 else {
          throw errno == ELOOP || errno == ENOTDIR ? CatalogIssue.unsafe : .unavailable
        }
        close(descriptor)
        descriptor = next
      }
      var info = stat()
      guard fstat(descriptor, &info) == 0 else { throw CatalogIssue.unavailable }
      let expected = directory ? S_IFDIR : S_IFREG
      guard (info.st_mode & S_IFMT) == expected, directory || info.st_nlink == 1 else {
        throw CatalogIssue.unsafe
      }
      return descriptor
    } catch {
      close(descriptor)
      throw error
    }
  }

  static func read(root: URL, components: [String], maximum: Int) throws -> (Data, String) {
    let descriptor = try descriptor(root: root, components: components, directory: false)
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var before = stat()
    guard fstat(descriptor, &before) == 0 else { throw CatalogIssue.unavailable }
    guard before.st_size >= 0, before.st_size <= maximum else { throw CatalogIssue.malformed }
    var data = Data()
    while let part = try handle.read(upToCount: 65_536), !part.isEmpty {
      guard data.count + part.count <= maximum else { throw CatalogIssue.malformed }
      data.append(part)
    }
    var after = stat()
    guard fstat(descriptor, &after) == 0, DiaryFileIdentity.sameVersion(before, after),
      data.count == before.st_size
    else { throw CatalogIssue.changed }
    let current = try self.descriptor(root: root, components: components, directory: false)
    defer { close(current) }
    var path = stat()
    guard fstat(current, &path) == 0, DiaryFileIdentity.sameVersion(after, path) else {
      throw CatalogIssue.changed
    }
    return (data, version(data: data, info: after))
  }

  static func version(data: Data, info: stat) -> String {
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return DiaryFileIdentity.versionIdentity(info) + ":" + digest
  }

  static func resourceExists(root: URL, components: [String]) throws -> Bool {
    guard let name = components.last else { return true }
    let parent = try descriptor(
      root: root, components: Array(components.dropLast()), directory: true)
    defer { close(parent) }
    var info = stat()
    if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
        throw CatalogIssue.unsafe
      }
      return true
    }
    if errno == ENOENT { return false }
    throw CatalogIssue.unavailable
  }
}

struct CatalogDirectorySlice: Sendable {
  struct Entry: Sendable {
    let name: String
    let isDirectory: Bool
    let safe: Bool
  }
  let entries: [Entry]
  let version: String
  let ended: Bool
  let visited: Int

}

/// POSIX directory cookies belong to their open stream. Retain the stream only
/// in the adapter session, use it only inside a fresh active-folder loan, and
/// revalidate its directory identity/version on every slice. No cookie escapes.
final class CatalogDirectoryCursor: @unchecked Sendable {
  private let lock = NSLock()
  private let stream: UnsafeMutablePointer<DIR>
  private let descriptor: Int32
  private let initial: stat

  init(root: URL, components: [String]) throws {
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: components, directory: true)
    guard let stream = fdopendir(descriptor) else {
      close(descriptor)
      throw CatalogIssue.unavailable
    }
    var initial = stat()
    guard fstat(descriptor, &initial) == 0 else {
      closedir(stream)
      throw CatalogIssue.unavailable
    }
    self.stream = stream
    self.descriptor = descriptor
    self.initial = initial
  }

  deinit { closedir(stream) }

  func next(root: URL, components: [String], maximum: Int) throws -> CatalogDirectorySlice {
    try lock.withLock {
      let current = try CatalogSafeFiles.descriptor(
        root: root, components: components, directory: true)
      defer { close(current) }
      var currentInfo = stat()
      guard fstat(current, &currentInfo) == 0, DiaryFileIdentity.sameVersion(initial, currentInfo)
      else {
        throw CatalogIssue.changed
      }
      return try read(root: root, components: components, maximum: maximum)
    }
  }

  private func read(root: URL, components: [String], maximum: Int) throws -> CatalogDirectorySlice {
    var entries: [CatalogDirectorySlice.Entry] = []
    var ended = false
    var visited = 0
    while visited < maximum {
      errno = 0
      guard let pointer = readdir(stream) else {
        guard errno == 0 else { throw CatalogIssue.unavailable }
        ended = true
        break
      }
      visited += 1
      var record = pointer.pointee
      let nameLength = Int(record.d_namlen) + 1
      let name = withUnsafePointer(to: &record.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: nameLength) { String(cString: $0) }
      }
      guard name != ".", name != ".." else { continue }
      var info = stat()
      guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw CatalogIssue.changed
      }
      let type = info.st_mode & S_IFMT
      let directory = type == S_IFDIR
      let url = (components + [name]).reduce(root) { $0.appendingPathComponent($1) }
      let package =
        directory && ((try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true)
      entries.append(
        CatalogDirectorySlice.Entry(
          name: name, isDirectory: directory,
          safe: (directory && !package) || (type == S_IFREG && info.st_nlink == 1)))
    }
    var after = stat()
    guard fstat(descriptor, &after) == 0, DiaryFileIdentity.sameVersion(initial, after) else {
      throw CatalogIssue.changed
    }
    return CatalogDirectorySlice(
      entries: entries,
      version: DiaryFileIdentity.versionIdentity(initial), ended: ended, visited: visited)
  }
}
