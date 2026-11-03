import Darwin
import Foundation

/// Descriptor-relative traversal never follows a descendant link. A moved or
/// substituted directory is rejected before its name is unlinked from its parent.
struct PurgeFileTree: Sendable {
  var beforeRemoval: (@Sendable () throws -> Void)?

  static func identity(_ root: URL) throws -> String {
    let descriptor = try openRoot(root)
    defer { close(descriptor) }
    return try identity(descriptor)
  }

  static func isEmpty(_ root: URL) throws -> Bool {
    let descriptor = try openRoot(root)
    defer { close(descriptor) }
    return try entries(descriptor) { _ in false }
  }

  @discardableResult
  func purge(
    _ root: URL, expectedIdentity: String? = nil,
    progress: @Sendable (Int) -> Void = { _ in }
  ) throws -> Int {
    let descriptor = try Self.openRoot(root)
    defer { close(descriptor) }
    let original = try Self.identity(descriptor)
    guard expectedIdentity == nil || expectedIdentity == original else {
      throw PurgeFailure.changedDestination
    }
    var count = 0
    try removeContents(descriptor, depth: 0, count: &count, progress: progress) {
      guard try Self.identity(root) == original else { throw PurgeFailure.unsafeResource }
    }
    guard try Self.identity(root) == original, try Self.isEmpty(root) else {
      throw PurgeFailure.unsafeResource
    }
    progress(count)
    return count
  }

  struct Entry: Sendable {
    let name: String
    fileprivate let identity: String
  }

  static func firstEntry(_ root: URL, expectedIdentity: String?) throws -> Entry? {
    let descriptor = try openRoot(root)
    defer { close(descriptor) }
    guard try identity(descriptor) == expectedIdentity else {
      throw PurgeFailure.changedDestination
    }
    var result: Entry?
    _ = try entries(descriptor) { name in
      var value = stat()
      guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw PurgeFailure.unavailable
      }
      result = Entry(name: name, identity: resourceIdentity(value))
      return false
    }
    return result
  }

  func purgeEntry(
    _ entry: Entry, in root: URL, expectedIdentity: String?,
    progress: @Sendable (Int) -> Void
  ) throws -> Int {
    let descriptor = try Self.openRoot(root)
    defer { close(descriptor) }
    guard try Self.identity(descriptor) == expectedIdentity else {
      throw PurgeFailure.changedDestination
    }
    var current = stat()
    guard fstatat(descriptor, entry.name, &current, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return 0 }
      throw PurgeFailure.unavailable
    }
    guard Self.resourceIdentity(current) == entry.identity else {
      throw PurgeFailure.unsafeResource
    }
    var count = 0
    try removeEntry(entry.name, parent: descriptor, depth: 0, count: &count, progress: progress) {
      guard try Self.identity(root) == expectedIdentity else { throw PurgeFailure.unsafeResource }
    }
    progress(count)
    return count
  }

  private func removeContents(
    _ parent: Int32, depth: Int, count: inout Int, progress: @Sendable (Int) -> Void,
    validate: () throws -> Void
  ) throws {
    guard depth < 128 else { throw PurgeFailure.unsafeResource }
    _ = try Self.entries(parent) { name in
      try removeEntry(
        name, parent: parent, depth: depth, count: &count, progress: progress, validate: validate)
      return true
    }
  }

  // swiftlint:disable:next cyclomatic_complexity function_parameter_count
  private func removeEntry(
    _ name: String, parent: Int32, depth: Int, count: inout Int,
    progress: @Sendable (Int) -> Void, validate: () throws -> Void
  ) throws {
    try Task.checkCancellation()
    var original = stat()
    guard fstatat(parent, name, &original, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return }
      throw PurgeFailure.unavailable
    }
    let directory = (original.st_mode & S_IFMT) == S_IFDIR
    if directory {
      let child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard child >= 0 else { throw PurgeFailure.unsafeResource }
      defer { close(child) }
      var opened = stat()
      guard fstat(child, &opened) == 0, Self.sameResource(original, opened) else {
        throw PurgeFailure.unsafeResource
      }
      try removeContents(child, depth: depth + 1, count: &count, progress: progress) {
        try validate()
        var attached = stat()
        guard fstatat(parent, name, &attached, AT_SYMLINK_NOFOLLOW) == 0,
          Self.sameResource(opened, attached)
        else { throw PurgeFailure.unsafeResource }
      }
    }
    try beforeRemoval?()
    try validate()
    var current = stat()
    guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return }
      throw PurgeFailure.unavailable
    }
    guard Self.sameResource(original, current) else { throw PurgeFailure.unsafeResource }
    guard unlinkat(parent, name, directory ? AT_REMOVEDIR : 0) == 0 else {
      if errno == ENOENT { return }
      throw PurgeFailure.unavailable
    }
    count += 1
    if count.isMultiple(of: 32) { progress(count) }
  }

  private static func resourceIdentity(_ value: stat) -> String {
    "\(value.st_dev):\(value.st_ino):\(value.st_mode & S_IFMT)"
  }

  private static func sameResource(_ left: stat, _ right: stat) -> Bool {
    left.st_dev == right.st_dev && left.st_ino == right.st_ino
      && (left.st_mode & S_IFMT) == (right.st_mode & S_IFMT)
  }

  private static func identity(_ descriptor: Int32) throws -> String {
    var value = stat()
    guard fstat(descriptor, &value) == 0 else { throw PurgeFailure.unavailable }
    return "\(value.st_dev):\(value.st_ino)"
  }

  private static func openRoot(_ root: URL) throws -> Int32 {
    guard root.isFileURL, root.standardizedFileURL.pathComponents.count > 2 else {
      throw PurgeFailure.unsafeResource
    }
    let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw PurgeFailure.unavailable }
    return descriptor
  }

  /// Returns true for an empty directory or when every visit returns true.
  private static func entries(_ descriptor: Int32, visit: (String) throws -> Bool) throws -> Bool {
    // A fresh open description avoids sharing readdir's offset with the owner.
    let copy = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard copy >= 0 else { throw PurgeFailure.unavailable }
    guard let stream = fdopendir(copy) else {
      close(copy)
      throw PurgeFailure.unavailable
    }
    defer { closedir(stream) }
    while true {
      errno = 0
      guard let entry = readdir(stream) else {
        guard errno == 0 else { throw PurgeFailure.unavailable }
        return true
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(validatingCString: $0)
        }
      }
      guard let name else { throw PurgeFailure.unsafeResource }
      if name == "." || name == ".." { continue }
      guard try visit(name) else { return false }
    }
  }
}
