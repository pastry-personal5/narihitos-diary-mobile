import CryptoKit
import Darwin
import Foundation

// swift-format places braces after multiline result types.
// swiftlint:disable opening_brace

struct CatalogActionResource: Sendable {
  let candidate: CatalogCandidate
  let version: String
  var preparation: (any CatalogReadPreparation)?
}

struct CatalogActionBinding: Sendable {
  let destination: StoredDestinationRecord
  let resource: CatalogActionResource
}

@MainActor
protocol CatalogActionBindingSource: AnyObject {
  func actionBinding(_ handle: CatalogItemHandle) async throws -> CatalogActionBinding
}

struct CommittedDiaryFacts: Sendable {
  let rootIdentity: String
  let version: DiaryPairVersion
  let markdownContentIdentity: String
  let audioContentIdentity: String
  let snippet: DiarySnippetV1?
  let audioComponents: [String]
  let audioBytes: Int64
  let duration: Double

  var audioVersion: DiaryFileVersion {
    DiaryFileVersion(
      identity: version.audioIdentity, digest: version.audioDigest, byteCount: audioBytes)
  }
}

enum CommittedDiaryResource {
  static func rootIdentity(_ root: URL) throws -> String {
    let descriptor = try CatalogSafeFiles.descriptor(root: root, components: [], directory: true)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw CatalogIssue.unavailable }
    return "\(info.st_dev):\(info.st_ino)"
  }

  static func resourceKey(destinationID: String, rootIdentity: String, candidate: CatalogCandidate)
    -> String
  {
    digest(Data((destinationID + "\n" + rootIdentity + "\n" + candidate.key).utf8))
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func submissionDigest(_ change: DiaryEditChange) -> String {
    switch change {
    case .body(let text): digest(Data(("body\0" + text).utf8))
    case .favorite(let desired): digest(Data((desired ? "favorite:1" : "favorite:0").utf8))
    }
  }

  static func inspect(
    _ resource: CatalogActionResource, root: URL, control: CatalogReadControl
  ) throws -> CommittedDiaryFacts {
    let handler = DiaryCatalogHandler(
      preparedLegacy: resource.preparation as? CatalogLegacySiblingProof)
    let read = try handler.readCoordinated(resource.candidate, root: root, control: control)
    if let issue = read.issue { throw issue }
    if read.version == resource.version, let detail = read.payload as? DiaryCatalogDetail,
      !detail.isLegacy, !detail.audioAvailable, read.files.isEmpty
    {
      return try inspectManual(resource, read: read, root: root)
    }
    guard read.version == resource.version, let detail = read.payload as? DiaryCatalogDetail,
      detail.audioAvailable, let duration = detail.duration,
      let audio = read.files.first(where: { !$0.directory })
    else { throw CatalogIssue.changed }
    let parts = read.version.split(separator: ":").map(String.init)
    guard parts.count == 4 else { throw CatalogIssue.changed }
    let version = DiaryPairVersion(
      markdownIdentity: parts[0], audioIdentity: parts[2],
      markdownDigest: parts[1], audioDigest: parts[3])
    let stem = try requiredStem(resource.candidate)
    let markdown = Array(resource.candidate.components.dropLast()) + [stem + ".md"]
    let (bytes, observed) = try CatalogSafeFiles.read(
      root: root, components: markdown, maximum: 1_114_122)
    guard observed == parts[0] + ":" + parts[1] else { throw CatalogIssue.changed }
    let snippet: DiarySnippetV1?
    if case .supported(let decoded) = DiarySnippetMarkdownCodec().decode(bytes) {
      snippet = decoded
    } else {
      guard detail.isLegacy else { throw CatalogIssue.unsupported }
      snippet = nil
    }
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: audio.components, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0,
      DiaryFileIdentity.versionIdentity(info) == version.audioIdentity
    else { throw CatalogIssue.changed }
    let markdownDescriptor = try CatalogSafeFiles.descriptor(
      root: root, components: markdown, directory: false)
    defer { close(markdownDescriptor) }
    var textInfo = stat()
    guard fstat(markdownDescriptor, &textInfo) == 0,
      DiaryFileIdentity.versionIdentity(textInfo) == version.markdownIdentity
    else { throw CatalogIssue.changed }
    return CommittedDiaryFacts(
      rootIdentity: try rootIdentity(root), version: version,
      markdownContentIdentity: DiaryFileIdentity.contentVersionIdentity(textInfo),
      audioContentIdentity: DiaryFileIdentity.contentVersionIdentity(info), snippet: snippet,
      audioComponents: audio.components, audioBytes: info.st_size, duration: duration)
  }

  /// Absence has an internal sentinel in the existing edit journal's pair-version
  /// envelope. It is never a file reference or evidence of an uploaded audio file.
  static let absentAudio = digest(Data())

  private static func inspectManual(
    _ resource: CatalogActionResource, read: CatalogReadValue, root: URL
  ) throws -> CommittedDiaryFacts {
    let stem = try requiredStem(resource.candidate)
    let markdown = Array(resource.candidate.components.dropLast()) + [stem + ".md"]
    let (bytes, observed) = try CatalogSafeFiles.read(
      root: root, components: markdown, maximum: 1_114_122)
    let parts = observed.split(separator: ":").map(String.init)
    guard observed == read.version, parts.count == 2,
      case .supported(let snippet) = DiarySnippetMarkdownCodec().decode(bytes),
      snippet.creationMethod == .manual
    else { throw CatalogIssue.changed }
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: markdown, directory: false)
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, DiaryFileIdentity.versionIdentity(info) == parts[0] else {
      throw CatalogIssue.changed
    }
    return CommittedDiaryFacts(
      rootIdentity: try rootIdentity(root),
      version: DiaryPairVersion(
        markdownIdentity: parts[0], audioIdentity: absentAudio,
        markdownDigest: parts[1], audioDigest: absentAudio, audioRequired: false),
      markdownContentIdentity: DiaryFileIdentity.contentVersionIdentity(info),
      audioContentIdentity: absentAudio, snippet: snippet, audioComponents: [], audioBytes: 0,
      duration: 0)
  }

  static func requiredStem(_ candidate: CatalogCandidate) throws -> String {
    guard let stem = candidate.components.last, candidate.components.count == 4,
      candidate.safe, candidate.handler == DiarySnippetSupportPolicy.kind
    else { throw CatalogIssue.unsafe }
    return stem
  }

  /// Exact-resource coordination is shared by edit/replay, without exposing URLs
  /// or provider versions as browse capabilities in Application.
  static func coordinated<Value: Sendable>(
    _ resource: CatalogActionResource, root: URL,
    operation: @escaping @Sendable (URL, CatalogReadControl) throws -> Value
  ) async throws -> Value {
    let control = CatalogReadControl()
    let handler = DiaryCatalogHandler(
      preparedLegacy: resource.preparation as? CatalogLegacySiblingProof)
    let plan = try await BoundedFileCoordinator().perform(
      intents: [
        NSFileAccessIntent.readingIntent(with: root, options: .immediatelyAvailableMetadataOnly)
      ],
      timeout: .seconds(15)
    ) { urls in
      guard urls.first?.standardizedFileURL == root.standardizedFileURL else {
        throw CatalogIssue.changed
      }
      return try handler.planRead(resource.candidate, root: root, control: control)
    }
    control.allowAudio(plan.audio)
    let paths = [[]] + plan.metadata + plan.files
    let intents = paths.enumerated().map { index, components in
      NSFileAccessIntent.readingIntent(
        with: components.reduce(root) { $0.appendingPathComponent($1) },
        options: index < 1 + plan.metadata.count ? .immediatelyAvailableMetadataOnly : [])
    }
    return try await withTaskCancellationHandler {
      try await BoundedFileCoordinator().perform(intents: intents, timeout: .seconds(120)) { urls in
        for (components, url) in zip(paths, urls) {
          guard
            url.standardizedFileURL
              == components.reduce(root, { $0.appendingPathComponent($1) }).standardizedFileURL
          else { throw CatalogIssue.changed }
        }
        return try operation(root, control)
      }
    } onCancel: {
      control.cancel()
    }
  }
}

// swiftlint:enable opening_brace
