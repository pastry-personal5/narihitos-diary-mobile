// swift-format wraps multiline declarations and collections.
// swiftlint:disable closure_parameter_position
import Darwin
import Foundation

private struct ManualPublicationReceipt: Codable {
  let token: UUID
  let digest: String
  let contentIdentity: String
}

/// Publishes one explicitly text-only resource. A local receipt written before
/// rename makes interrupted creation distinguishable from external replacement.
enum ManualDiaryPublication {
  static func publish(
    _ envelope: ManualDiaryEnvelope, root: URL, files: DiaryEditPrivateFiles,
    observer: any DiaryFileObserverPort
  ) async throws -> Bool {
    guard !envelope.needsTitle,
      case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(envelope.markdown),
      snippet.creationMethod == .manual
    else { throw DiaryEditIssue.invalidCandidate }
    let layout = DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt)
    let day = try await prepareDay(root: root, envelope: envelope, layout: layout)
    let target = day.appending(path: layout.markdownFilename)
    let access = NSFileAccessIntent.writingIntent(with: day, options: [])
    try await BoundedFileCoordinator().perform(intents: [access], timeout: .seconds(120)) { urls in
      guard urls.first?.standardizedFileURL == day.standardizedFileURL,
        try CommittedDiaryResource.rootIdentity(root) == envelope.rootIdentity,
        try !DiaryCatalogHandler.assetsExist(
          root: root, parent: layout.directoryComponents,
          name: layout.assetsDirectoryName)
      else { throw DiaryEditIssue.changed }
      try assertUnique(root: root, layout: layout, id: snippet.id.description)
      try ensureFile(envelope, root: root, layout: layout, files: files)
    }
    let first = try await observer.observeBounded(
      target, maximumBytes: 1_114_122, timeout: .seconds(15))
    guard first.uploaded, !first.hasUnresolvedConflict else { return false }
    let verify = NSFileAccessIntent.readingIntent(with: target, options: [])
    try await BoundedFileCoordinator().perform(intents: [verify], timeout: .seconds(15)) { urls in
      guard urls.first?.standardizedFileURL == target.standardizedFileURL,
        try CommittedDiaryResource.rootIdentity(root) == envelope.rootIdentity
      else { throw DiaryEditIssue.changed }
      let (_, version) = try ownedFile(envelope, root: root, layout: layout, files: files)
      guard version == first.identity + ":" + first.digest else { throw DiaryEditIssue.upload }
    }
    let second = try await observer.observeBounded(
      target, maximumBytes: 1_114_122, timeout: .seconds(15))
    return second.uploaded && !second.hasUnresolvedConflict && second.identity == first.identity
      && second.digest == first.digest && second.byteCount == first.byteCount
  }

  private static func prepareDay(
    root: URL, envelope: ManualDiaryEnvelope, layout: DiarySnippetLayout
  ) async throws -> URL {
    let access = NSFileAccessIntent.writingIntent(with: root, options: [])
    return try await BoundedFileCoordinator().perform(intents: [access], timeout: .seconds(15)) {
      urls in
      guard urls.first?.standardizedFileURL == root.standardizedFileURL,
        try CommittedDiaryResource.rootIdentity(root) == envelope.rootIdentity
      else { throw DiaryEditIssue.changed }
      var components: [String] = []
      for name in layout.directoryComponents {
        let parent = try CatalogSafeFiles.descriptor(
          root: root, components: components, directory: true)
        defer { close(parent) }
        guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else {
          throw DiaryEditIssue.unavailable
        }
        components.append(name)
        let child = try CatalogSafeFiles.descriptor(
          root: root, components: components, directory: true)
        close(child)
      }
      return components.reduce(root) { $0.appendingPathComponent($1) }
    }
  }

  private static func ensureFile(
    _ envelope: ManualDiaryEnvelope, root: URL, layout: DiarySnippetLayout,
    files: DiaryEditPrivateFiles
  ) throws {
    let components = layout.directoryComponents + [layout.markdownFilename]
    if try CatalogSafeFiles.resourceExists(root: root, components: components) {
      _ = try ownedFile(envelope, root: root, layout: layout, files: files)
      return
    }
    let directory = try files.directory(envelope.id)
    let hasReceipt = try CatalogSafeFiles.resourceExists(
      root: directory, components: ["publication.json"])
    let temporaryName = ".ndm-manual-" + envelope.token.uuidString.lowercased()
    let temporaryComponents = layout.directoryComponents + [temporaryName]
    let parent = try CatalogSafeFiles.descriptor(
      root: root, components: layout.directoryComponents, directory: true)
    defer { close(parent) }
    try prepareTemporary(
      envelope, root: root, files: files, components: temporaryComponents, hasReceipt: hasReceipt)
    let currentParent = try CatalogSafeFiles.descriptor(
      root: root, components: layout.directoryComponents, directory: true)
    defer { close(currentParent) }
    var reopened = stat()
    var original = stat()
    guard fstat(parent, &original) == 0, fstat(currentParent, &reopened) == 0,
      original.st_dev == reopened.st_dev, original.st_ino == reopened.st_ino,
      renameatx_np(parent, temporaryName, parent, layout.markdownFilename, UInt32(RENAME_EXCL))
        == 0,
      fsync(parent) == 0
    else { throw DiaryEditIssue.changed }
    _ = try ownedFile(envelope, root: root, layout: layout, files: files)
  }

  private static func prepareTemporary(
    _ envelope: ManualDiaryEnvelope, root: URL, files: DiaryEditPrivateFiles,
    components temporaryComponents: [String], hasReceipt: Bool
  ) throws {
    guard let temporaryName = temporaryComponents.last else { throw DiaryEditIssue.changed }
    let temporary = temporaryComponents.reduce(root) { $0.appendingPathComponent($1) }
    let parent = try CatalogSafeFiles.descriptor(
      root: root,
      components: Array(temporaryComponents.dropLast()), directory: true)
    defer { close(parent) }
    if try !CatalogSafeFiles.resourceExists(root: root, components: temporaryComponents) {
      // A persisted receipt with neither inode present could mean external deletion.
      guard !hasReceipt else { throw DiaryEditIssue.changed }
      let output = openat(
        parent, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard output >= 0 else { throw DiaryEditIssue.unavailable }
      defer { close(output) }
      try write(envelope.markdown, descriptor: output)
      DiaryFileCreationMarker.set(descriptor: output, token: envelope.token)
      guard fsync(output) == 0 else { throw DiaryEditIssue.unavailable }
    }
    let (bytes, _) = try CatalogSafeFiles.read(
      root: root, components: temporaryComponents, maximum: 1_114_122)
    guard bytes == envelope.markdown, DiaryFileCreationMarker.matches(envelope.token, at: temporary)
    else {
      throw DiaryEditIssue.changed
    }
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: temporaryComponents, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw DiaryEditIssue.unavailable }
    let receipt = ManualPublicationReceipt(
      token: envelope.token,
      digest: CommittedDiaryResource.digest(bytes),
      contentIdentity: DiaryFileIdentity.contentVersionIdentity(info))
    if hasReceipt {
      let prior = try JSONDecoder().decode(
        ManualPublicationReceipt.self,
        from: files.read("publication.json", id: envelope.id, maximum: 4_096))
      guard prior.token == receipt.token, prior.digest == receipt.digest,
        prior.contentIdentity == receipt.contentIdentity
      else { throw DiaryEditIssue.changed }
    } else {
      try files.write(try JSONEncoder().encode(receipt), named: "publication.json", id: envelope.id)
    }
  }

  private static func ownedFile(
    _ envelope: ManualDiaryEnvelope, root: URL, layout: DiarySnippetLayout,
    files: DiaryEditPrivateFiles
  ) throws -> (Data, String) {
    let components = layout.directoryComponents + [layout.markdownFilename]
    let target = components.reduce(root) { $0.appendingPathComponent($1) }
    let receipt = try JSONDecoder().decode(
      ManualPublicationReceipt.self,
      from: files.read("publication.json", id: envelope.id, maximum: 4_096))
    let value = try CatalogSafeFiles.read(root: root, components: components, maximum: 1_114_122)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: components, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, value.0 == envelope.markdown,
      receipt.token == envelope.token, receipt.digest == CommittedDiaryResource.digest(value.0),
      receipt.contentIdentity == DiaryFileIdentity.contentVersionIdentity(info),
      DiaryFileCreationMarker.matches(envelope.token, at: target),
      !DiaryCatalogHandler.hasConflict(target)
    else { throw DiaryEditIssue.changed }
    return value
  }

  private static func assertUnique(root: URL, layout: DiarySnippetLayout, id: String) throws {
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    var index = CatalogDirectoryIndex()
    repeat { _ = try index.advance(root: root, registry: registry) } while !index.complete
    let expected = layout.directoryComponents + [String(layout.markdownFilename.dropLast(3))]
    guard
      index.candidates.values.filter({ $0.stableID == id }).allSatisfy({ $0.components == expected }
      )
    else {
      throw DiaryEditIssue.conflict
    }
  }

  private static func write(_ bytes: Data, descriptor: Int32) throws {
    try bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { throw DiaryEditIssue.invalidCandidate }
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
        guard count > 0 else { throw DiaryEditIssue.storage }
        offset += count
      }
    }
  }
}

// swiftlint:enable closure_parameter_position
