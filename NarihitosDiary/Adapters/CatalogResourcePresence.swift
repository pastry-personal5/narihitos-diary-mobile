import Darwin
import Foundation

enum CatalogResourcePresence: Equatable, Sendable {
  case present
  case missing
  case unsafe

  static func inspect(root: URL, components: [String]) throws -> Self {
    guard !components.isEmpty else { return .present }
    var descriptor = try CatalogSafeFiles.descriptor(root: root, components: [], directory: true)
    defer { close(descriptor) }
    for (index, name) in components.enumerated() {
      guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
        !name.contains("\\"), !name.contains("\0")
      else { return .unsafe }
      var info = stat()
      guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
        if errno == ENOENT { return .missing }
        throw CatalogIssue.unavailable
      }
      let kind = info.st_mode & S_IFMT
      guard kind == S_IFDIR || (kind == S_IFREG && info.st_nlink == 1) else { return .unsafe }
      if index == components.count - 1 { return .present }
      guard kind == S_IFDIR else { return .unsafe }
      let next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard next >= 0 else { throw CatalogIssue.unavailable }
      close(descriptor)
      descriptor = next
    }
    return .present
  }
}

extension DiaryCatalogHandler {
  func presence(of candidate: CatalogCandidate, root: URL) throws -> CatalogResourcePresence {
    guard let stem = candidate.components.last else { return .unsafe }
    let parent = Array(candidate.components.dropLast())
    let text = try CatalogResourcePresence.inspect(root: root, components: parent + [stem + ".md"])
    let audio = try CatalogResourcePresence.inspect(
      root: root, components: parent + [stem + ".assets"])
    if text == .unsafe || audio == .unsafe { return .unsafe }
    return text == .present || audio == .present ? .present : .missing
  }
}
