import Darwin
import Foundation

private struct EditCleanupReceipt: Codable {
  let schema: Int
  let record: DiaryEditRecord
  let directoryIdentity: String
}

extension DiaryEditPrivateFiles {
  /// The receipt lives outside the retiring directory so it survives deletion
  /// of either original journal file, the last payload, and the directory itself.
  func remove(_ record: DiaryEditRecord, beforeUnlink: (String) throws -> Void = { _ in }) throws {
    if try !cleanupReceiptExists(record.id) {
      guard try readRecord(record.id) == record, record.stage == .completed else {
        throw DiaryEditIssue.changed
      }
      let directory = try directory(record.id)
      let receipt = EditCleanupReceipt(
        schema: 1, record: record,
        directoryIdentity: try CommittedDiaryResource.rootIdentity(directory))
      let url = root.appending(path: cleanupReceiptName(record.id))
      try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
      try protect(url)
    }
    try completeRetirement(
      record.id, installation: record.installationBinding, beforeUnlink: beforeUnlink)
  }

  func completeRetirement(
    _ id: UUID, installation: String, beforeUnlink: (String) throws -> Void = { _ in }
  ) throws {
    let (data, receiptVersion) = try CatalogSafeFiles.read(
      root: root, components: [cleanupReceiptName(id)], maximum: 64 * 1_024)
    let receiptURL = root.appending(path: cleanupReceiptName(id))
    try protection.verify(receiptURL)
    guard
      try receiptURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        == true
    else {
      throw DiaryEditIssue.localData
    }
    let receipt = try JSONDecoder().decode(EditCleanupReceipt.self, from: data)
    guard receipt.schema == 1, receipt.record.id == id, receipt.record.stage == .completed,
      receipt.record.installationBinding == installation, receipt.record.markdownUploaded,
      receipt.record.audioUploaded, receipt.record.publishedVersion != nil,
      !receipt.directoryIdentity.isEmpty, receipt.directoryIdentity.utf8.count <= 128
    else { throw DiaryEditIssue.reviewRequired }
    let parent = try CatalogSafeFiles.descriptor(root: root, components: [], directory: true)
    defer { close(parent) }
    let retired = "completed-" + id.uuidString.lowercased()
    let liveExists = try childExists(id.uuidString.lowercased(), in: parent)
    let retiredExists = try childExists(retired, in: parent)
    if !retiredExists, liveExists {
      var current = try readRecord(id)
      current.issue = receipt.record.issue
      guard current == receipt.record,
        try CommittedDiaryResource.rootIdentity(directory(id)) == receipt.directoryIdentity
      else { throw DiaryEditIssue.changed }
      guard
        renameatx_np(parent, id.uuidString.lowercased(), parent, retired, UInt32(RENAME_EXCL))
          == 0
      else { throw DiaryEditIssue.storage }
    }
    if try childExists(retired, in: parent) {
      try removeRetiredContents(
        retired, receipt: receipt, parent: parent, beforeUnlink: beforeUnlink)
      try beforeUnlink("retired-directory")
      try requireRetiredIdentity(retired, parent: parent, expected: receipt.directoryIdentity)
      guard unlinkat(parent, retired, AT_REMOVEDIR) == 0 else { throw DiaryEditIssue.storage }
    }
    try beforeUnlink("retirement-receipt")
    let (_, unchanged) = try CatalogSafeFiles.read(
      root: root, components: [cleanupReceiptName(id)], maximum: 64 * 1_024)
    guard unchanged == receiptVersion, unlinkat(parent, cleanupReceiptName(id), 0) == 0 else {
      throw DiaryEditIssue.storage
    }
  }

  func retirementID(_ name: String) -> UUID? {
    guard name.hasPrefix("completed-") else { return nil }
    let suffix = String(name.dropFirst(10))
    let value = suffix.hasSuffix(".json") ? String(suffix.dropLast(5)) : suffix
    guard (try? WorkspaceID(value)) != nil else { return nil }
    return UUID(uuidString: value)
  }

  private func removeRetiredContents(
    _ name: String, receipt: EditCleanupReceipt, parent: Int32,
    beforeUnlink: (String) throws -> Void
  ) throws {
    try requireRetiredIdentity(name, parent: parent, expected: receipt.directoryIdentity)
    let directory = root.appending(path: name)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: [name], directory: true)
    defer { close(descriptor) }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    for child in names {
      guard
        child == "binding.json" || child == "record.json" || child == "publication.json"
          || child == "audio.m4a"
          || (child.hasSuffix(".md") && Self.validDigest(String(child.dropLast(3))))
      else { throw DiaryEditIssue.changed }
      var info = stat()
      guard fstatat(descriptor, child, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw DiaryEditIssue.localData
      }
      guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
        throw DiaryEditIssue.changed
      }
    }
    for child in names {
      // Observe immediately before use and retain the descriptor through the
      // checked unlink. Any intervening version change still defers retirement.
      let file = try CatalogSafeFiles.descriptor(
        root: directory, components: [child], directory: false)
      defer { close(file) }
      var before = stat()
      guard fstatat(descriptor, child, &before, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw DiaryEditIssue.localData
      }
      var opened = stat()
      guard fstat(file, &opened) == 0, opened.st_dev == before.st_dev,
        opened.st_ino == before.st_ino, (before.st_mode & S_IFMT) == S_IFREG,
        before.st_nlink == 1
      else { throw DiaryEditIssue.changed }
      try beforeUnlink(child)
      try requireRetiredIdentity(name, parent: parent, expected: receipt.directoryIdentity)
      var info = stat()
      guard fstatat(descriptor, child, &info, AT_SYMLINK_NOFOLLOW) == 0,
        (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1,
        DiaryFileIdentity.sameVersion(before, info),
        unlinkat(descriptor, child, 0) == 0
      else { throw DiaryEditIssue.changed }
    }
  }

  private func cleanupReceiptName(_ id: UUID) -> String {
    "completed-" + id.uuidString.lowercased() + ".json"
  }

  func cleanupReceiptExists(_ id: UUID) throws -> Bool {
    try CatalogSafeFiles.resourceExists(root: root, components: [cleanupReceiptName(id)])
  }

  private func childExists(_ name: String, in descriptor: Int32) throws -> Bool {
    var info = stat()
    if fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return true }
    guard errno == ENOENT else { throw DiaryEditIssue.localData }
    return false
  }

  private func requireRetiredIdentity(_ name: String, parent: Int32, expected: String) throws {
    var info = stat()
    guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
      (info.st_mode & S_IFMT) == S_IFDIR, "\(info.st_dev):\(info.st_ino)" == expected
    else { throw DiaryEditIssue.changed }
  }
}
