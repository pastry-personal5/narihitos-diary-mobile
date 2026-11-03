import Darwin
import Foundation

// swift-format's multiline closure, result-type and collection layout differs from SwiftLint.
// swiftlint:disable closure_parameter_position opening_brace trailing_comma

private struct DiaryEditWriteReceipt: Codable, Sendable {
  let transactionID: UUID
  let token: UUID
  let contentIdentity: String
  let digest: String
  let sourceVersion: DiaryPairVersion
}

enum DiaryEditPublicationAdapter {
  static func publish(
    _ record: DiaryEditRecord, binding: DiaryEditBinding, candidate: DiarySnippetV1,
    root: URL, files: DiaryEditPrivateFiles
  ) async throws -> DiaryEditPublication {
    let components = try paths(binding, root: root)
    let markdownURL = components.markdown.reduce(root) { $0.appendingPathComponent($1) }
    let audioURL = binding.audioComponents.reduce(root) { $0.appendingPathComponent($1) }
    let expectedData = try DiarySnippetMarkdownCodec().encode(candidate)
    guard CommittedDiaryResource.digest(expectedData) == record.candidateDigest else {
      throw DiaryEditIssue.invalidCandidate
    }
    let intents = [
      NSFileAccessIntent.readingIntent(with: root, options: .immediatelyAvailableMetadataOnly),
      NSFileAccessIntent.writingIntent(with: markdownURL, options: .forReplacing),
      NSFileAccessIntent.readingIntent(with: audioURL, options: []),
    ]
    return try await BoundedFileCoordinator().perform(intents: intents, timeout: .seconds(120)) {
      urls in
      guard urls.count == 3, urls[0].standardizedFileURL == root.standardizedFileURL,
        urls[1].standardizedFileURL == markdownURL.standardizedFileURL,
        urls[2].standardizedFileURL == audioURL.standardizedFileURL
      else { throw DiaryEditIssue.changed }
      try assertUniqueClaim(binding, root: root)
      let current = try observedPair(binding, root: root)
      if current.markdownDigest == record.candidateDigest {
        guard try ownsPublication(record, binding: binding, root: root, files: files),
          current.audioDigest == binding.sourceVersion.audioDigest,
          try matchesAudioContent(binding, root: root)
        else { throw DiaryEditIssue.changed }
        return .verified(current)
      }
      guard record.stage == .ready,
        current.markdownDigest == binding.sourceVersion.markdownDigest,
        current.audioDigest == binding.sourceVersion.audioDigest,
        try matchesContent(
          root: root, components: components.markdown, identity: binding.markdownContentIdentity),
        try matchesAudioContent(binding, root: root)
      else {
        throw DiaryEditIssue.changed
      }
      try replace(
        expectedData, record: record, binding: binding, root: root,
        files: files)
      let published = try observedPair(binding, root: root)
      guard published.markdownDigest == record.candidateDigest,
        published.audioDigest == binding.sourceVersion.audioDigest,
        try matchesAudioContent(binding, root: root),
        try ownsPublication(record, binding: binding, root: root, files: files)
      else { throw DiaryEditIssue.changed }
      return .verified(published)
    }
  }

  static func verify(
    _ record: DiaryEditRecord, binding: DiaryEditBinding, root: URL, files: DiaryEditPrivateFiles
  ) async throws
    -> Bool
  {
    guard let expected = record.publishedVersion else { return false }
    let resource = CatalogActionResource(
      candidate: binding.candidate,
      version: expected.markdownIdentity + ":" + expected.markdownDigest
        + ":" + expected.audioIdentity + ":" + expected.audioDigest)
    return try await CommittedDiaryResource.coordinated(resource, root: root) { root, _ in
      let current = try observedPair(binding, root: root)
      guard current.markdownDigest == record.candidateDigest,
        current.audioDigest == binding.sourceVersion.audioDigest,
        try ownsPublication(record, binding: binding, root: root, files: files),
        try matchesAudioContent(binding, root: root)
      else { return false }
      // A provider metadata update changes ctime without changing content.
      // Re-observe/recheckpoint the owned versions before trusting upload proof.
      guard current == expected else { throw DiaryEditIssue.upload }
      return true
    }
  }

  static func uploads(
    _ record: DiaryEditRecord, binding: DiaryEditBinding, root: URL, files: DiaryEditPrivateFiles,
    observer: any DiaryFileObserverPort = AppleDiaryFileObserver()
  ) async throws -> DiaryPairUploadObservation {
    let paths = try paths(binding, root: root)
    let markdown = paths.markdown.reduce(root) { $0.appendingPathComponent($1) }
    let audio = binding.audioComponents.reduce(root) { $0.appendingPathComponent($1) }
    let text = try await observer.observeBounded(
      markdown, maximumBytes: 1_114_122, timeout: .seconds(15))
    let sound = try await observer.observeBounded(
      audio, maximumBytes: CatalogAudioInspector.maximumBytes, timeout: .seconds(15))
    guard try await verify(record, binding: binding, root: root, files: files) else {
      throw DiaryEditIssue.changed
    }
    return DiaryPairUploadObservation(
      markdown: text.uploaded && !text.hasUnresolvedConflict
        ? DiaryFileUploadProof(identity: text.identity, digest: text.digest) : nil,
      audio: sound.uploaded && !sound.hasUnresolvedConflict
        ? DiaryFileUploadProof(identity: sound.identity, digest: sound.digest) : nil)
  }

  private static func paths(_ binding: DiaryEditBinding, root: URL) throws -> (
    markdown: [String], parent: [String]
  ) {
    guard try CommittedDiaryResource.rootIdentity(root) == binding.rootIdentity else {
      throw DiaryEditIssue.changed
    }
    let stem = try CommittedDiaryResource.requiredStem(binding.candidate)
    let parent = Array(binding.candidate.components.dropLast())
    let parsed = try requiredLayout(stem)
    guard parent == parsed.directoryComponents,
      binding.audioComponents == parent + [parsed.assetsDirectoryName, parsed.audioFilename]
    else { throw DiaryEditIssue.changed }
    return (parent + [stem + ".md"], parent)
  }

  private static func requiredLayout(_ stem: String) throws -> DiarySnippetLayout {
    guard let parsed = DiaryCatalogHandler.currentStem(stem) else {
      throw DiaryEditIssue.unsupported
    }
    return try DiarySnippetLayout(id: parsed.id, createdAt: SchemaInstant.from(date: parsed.date))
  }

  private static func observedPair(_ binding: DiaryEditBinding, root: URL) throws
    -> DiaryPairVersion
  {
    let paths = try paths(binding, root: root)
    let text = try CatalogSafeFiles.read(root: root, components: paths.markdown, maximum: 1_114_122)
    guard case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(text.0),
      DiarySnippetLayout(id: snippet.id, createdAt: snippet.createdAt).markdownFilename
        == paths.markdown.last,
      snippet.audioFilename == binding.audioComponents.last
    else { throw DiaryEditIssue.unsupported }
    let sound = try CatalogAudioInspector.inspect(
      root: root, components: binding.audioComponents, maximumDuration: 301,
      control: CatalogReadControl())
    let textParts = text.1.split(separator: ":").map(String.init)
    let audioParts = sound.version.split(separator: ":").map(String.init)
    guard textParts.count == 2, audioParts.count == 2,
      snippet.audioSHA256 == nil || snippet.audioSHA256 == audioParts[1],
      !DiaryCatalogHandler.hasConflict(
        paths.markdown.reduce(root, { $0.appendingPathComponent($1) })),
      !DiaryCatalogHandler.hasConflict(
        binding.audioComponents.reduce(root, { $0.appendingPathComponent($1) }))
    else { throw DiaryEditIssue.conflict }
    return DiaryPairVersion(
      markdownIdentity: textParts[0], audioIdentity: audioParts[0],
      markdownDigest: textParts[1], audioDigest: audioParts[1])
  }

  private static func ownsPublication(
    _ record: DiaryEditRecord, binding: DiaryEditBinding, root: URL, files: DiaryEditPrivateFiles
  ) throws -> Bool {
    let bytes = try files.read("publication.json", id: record.id, maximum: 4_096)
    let receipt = try JSONDecoder().decode(DiaryEditWriteReceipt.self, from: bytes)
    let paths = try paths(binding, root: root)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: paths.markdown, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw DiaryEditIssue.unavailable }
    let url = paths.markdown.reduce(root) { $0.appendingPathComponent($1) }
    return receipt.transactionID == record.id && receipt.token == binding.publicationToken
      && receipt.sourceVersion == binding.sourceVersion && receipt.digest == record.candidateDigest
      && receipt.contentIdentity == DiaryFileIdentity.contentVersionIdentity(info)
      && DiaryFileCreationMarker.matches(binding.publicationToken, at: url)
  }

  private static func replace(
    _ bytes: Data, record: DiaryEditRecord, binding: DiaryEditBinding, root: URL,
    files: DiaryEditPrivateFiles
  ) throws {
    let markdown = try paths(binding, root: root).markdown
    let parent = Array(markdown.dropLast())
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: parent, directory: true)
    defer { close(descriptor) }
    guard let filename = markdown.last else { throw DiaryEditIssue.changed }
    let temporaryName = ".ndm-edit-" + binding.publicationToken.uuidString.lowercased()
    let temporary = parent.reduce(root) { $0.appendingPathComponent($1) }.appending(
      path: temporaryName)
    let output = openat(
      descriptor, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { throw DiaryEditIssue.changed }
    defer { close(output) }
    try write(bytes, to: output)
    DiaryFileCreationMarker.set(descriptor: output, token: binding.publicationToken)
    var prepared = stat()
    guard fsync(output) == 0, fstat(output, &prepared) == 0,
      DiaryFileCreationMarker.matches(binding.publicationToken, at: temporary)
    else { throw DiaryEditIssue.unavailable }
    let receipt = DiaryEditWriteReceipt(
      transactionID: record.id, token: binding.publicationToken,
      contentIdentity: DiaryFileIdentity.contentVersionIdentity(prepared),
      digest: record.candidateDigest, sourceVersion: binding.sourceVersion)
    try files.write(try JSONEncoder().encode(receipt), named: "publication.json", id: record.id)
    // Recheck the current whole pair at the replacement point. Coordination is
    // not a cross-device lock; publication is checked again before any cleanup.
    let current = try observedPair(binding, root: root)
    guard current.markdownDigest == binding.sourceVersion.markdownDigest,
      current.audioDigest == binding.sourceVersion.audioDigest,
      try matchesContent(
        root: root, components: markdown, identity: binding.markdownContentIdentity),
      try matchesAudioContent(binding, root: root)
    else {
      throw DiaryEditIssue.changed
    }
    let currentParent = try CatalogSafeFiles.descriptor(
      root: root, components: parent, directory: true)
    defer { close(currentParent) }
    var before = stat()
    var after = stat()
    guard fstat(descriptor, &before) == 0, fstat(currentParent, &after) == 0,
      before.st_dev == after.st_dev, before.st_ino == after.st_ino,
      renameat(descriptor, temporaryName, descriptor, filename) == 0,
      fsync(descriptor) == 0
    else { throw DiaryEditIssue.unavailable }
  }

  private static func assertUniqueClaim(_ binding: DiaryEditBinding, root: URL) throws {
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    var index = CatalogDirectoryIndex()
    let control = CatalogReadControl()
    repeat {
      try control.check()
      _ = try index.advance(root: root, registry: registry)
    } while !index.complete
    guard index.candidates.values.filter({ $0.stableID == binding.candidate.stableID }).count == 1
    else {
      throw DiaryEditIssue.conflict
    }
  }

  private static func write(_ bytes: Data, to descriptor: Int32) throws {
    try bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { throw DiaryEditIssue.invalidCandidate }
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
        guard count > 0 else { throw DiaryEditIssue.unavailable }
        offset += count
      }
    }
  }

  private static func matchesAudioContent(_ binding: DiaryEditBinding, root: URL) throws -> Bool {
    try matchesContent(
      root: root, components: binding.audioComponents, identity: binding.audioContentIdentity)
  }

  private static func matchesContent(root: URL, components: [String], identity: String) throws
    -> Bool
  {
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: components, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw DiaryEditIssue.unavailable }
    return DiaryFileIdentity.contentVersionIdentity(info) == identity
  }
}

// swiftlint:enable closure_parameter_position opening_brace trailing_comma
