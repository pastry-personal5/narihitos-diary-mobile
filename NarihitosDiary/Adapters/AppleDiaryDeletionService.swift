import Darwin
import Foundation
import UIKit

// swift-format wraps multiline closure parameters and result-type braces.
// swiftlint:disable closure_parameter_position opening_brace

@MainActor
final class AppleDiaryDeletionService: DiaryDeletionPort {
  private let catalog: any CatalogActionBindingSource
  private let destination: AppleDestinationService
  private let creationIsSettled: (String) throws -> Bool
  private let protectedDataAvailable: () -> Bool

  init(
    catalog: any CatalogActionBindingSource, destination: AppleDestinationService,
    creationIsSettled: @escaping (String) throws -> Bool,
    protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
  ) {
    self.catalog = catalog
    self.destination = destination
    self.creationIsSettled = creationIsSettled
    self.protectedDataAvailable = protectedDataAvailable
  }

  func delete(_ handle: CatalogItemHandle) async throws {
    guard protectedDataAvailable() else { throw DiaryDeletionIssue.unavailable }
    do {
      let binding = try await catalog.actionBinding(handle)
      // Current assets retain their recording UUID; legacy assets have no creation job.
      if !binding.resource.candidate.stableID.isEmpty {
        guard try creationIsSettled(binding.resource.candidate.stableID) else {
          throw DiaryDeletionIssue.busy
        }
      }
      try await destination.withCommittedDestination(binding.destination) { root in
        try await DiaryPairDeletion.remove(binding.resource, root: root)
      }
    } catch let issue as DiaryDeletionIssue {
      throw issue
    } catch let issue as CatalogIssue {
      switch issue {
      case .changed: throw DiaryDeletionIssue.changed
      case .unavailable: throw DiaryDeletionIssue.unavailable
      default: throw DiaryDeletionIssue.unsafe
      }
    } catch {
      throw DiaryDeletionIssue.unavailable
    }
  }

  static func creationIsSettled(id: String, queue: any QueueStorePort, captures: URL) throws -> Bool
  {
    guard (try? AssetID(id)) != nil else { throw DiaryDeletionIssue.unsafe }
    let jobs = try queue.jobs().filter { $0.id == id || $0.draftAssetID == id }
    guard jobs.allSatisfy({ $0.state == .saved && $0.commitCleanupDone == true }) else {
      return false
    }
    let descriptor = try CatalogSafeFiles.descriptor(
      root: captures, components: [], directory: true)
    defer { close(descriptor) }
    for name in Set([id] + jobs.map(\.id)) {
      var info = stat()
      guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
        return false
      }
    }
    return true
  }
}

/// Removes two exact files, never an assets subtree. A partial failure remains
/// discoverable as an incomplete pair; retained edits/creation must be excluded by the caller.
enum DiaryPairDeletion {
  static func remove(
    _ resource: CatalogActionResource, root: URL,
    beforeTextRemoval: @escaping @Sendable () throws -> Void = {}
  ) async throws {
    let facts = try await CommittedDiaryResource.coordinated(resource, root: root) {
      root, control in
      try CommittedDiaryResource.inspect(resource, root: root, control: control)
    }
    let stem = try CommittedDiaryResource.requiredStem(resource.candidate)
    let parent = Array(resource.candidate.components.dropLast())
    let markdown = parent + [stem + ".md"]
    if facts.audioComponents.isEmpty {
      try await removeManual(resource, facts: facts, root: root, markdown: markdown)
      return
    }
    let assets = Array(facts.audioComponents.dropLast())
    let paths = [[], parent, assets, markdown, facts.audioComponents]
    let intents = paths.enumerated().map { index, components in
      let url = components.reduce(root) { $0.appendingPathComponent($1) }
      return index == 0
        ? NSFileAccessIntent.readingIntent(with: url, options: .immediatelyAvailableMetadataOnly)
        : NSFileAccessIntent.writingIntent(with: url, options: index >= 3 ? .forDeleting : [])
    }
    try await BoundedFileCoordinator().perform(intents: intents, timeout: .seconds(120)) { urls in
      for (components, url) in zip(paths, urls) {
        guard
          url.standardizedFileURL
            == components.reduce(root, { $0.appendingPathComponent($1) }).standardizedFileURL
        else { throw CatalogIssue.changed }
      }
      let control = CatalogReadControl()
      control.allowAudio([facts.audioComponents])
      let current = try CommittedDiaryResource.inspect(resource, root: root, control: control)
      guard current.rootIdentity == facts.rootIdentity, current.version == facts.version else {
        throw CatalogIssue.changed
      }
      try unlinkPair(resource, facts: facts, root: root, beforeTextRemoval: beforeTextRemoval)
    }
  }

  private static func removeManual(
    _ resource: CatalogActionResource, facts: CommittedDiaryFacts, root: URL, markdown: [String]
  ) async throws {
    let target = markdown.reduce(root) { $0.appendingPathComponent($1) }
    try await BoundedFileCoordinator().perform(
      intents: [NSFileAccessIntent.writingIntent(with: target, options: .forDeleting)],
      timeout: .seconds(120)
    ) { urls in
      guard urls.first?.standardizedFileURL == target.standardizedFileURL else {
        throw CatalogIssue.changed
      }
      let current = try CommittedDiaryResource.inspect(
        resource, root: root, control: CatalogReadControl())
      guard current.rootIdentity == facts.rootIdentity, current.version == facts.version,
        current.snippet?.creationMethod == .manual
      else { throw CatalogIssue.changed }
      let parent = Array(markdown.dropLast())
      let day = try CatalogSafeFiles.descriptor(root: root, components: parent, directory: true)
      defer { close(day) }
      try attached(day, root: root, components: parent)
      try unlinkFile(markdown.last!, parent: day, version: facts.version.markdownIdentity)
    }
  }

  private static func unlinkPair(
    _ resource: CatalogActionResource, facts: CommittedDiaryFacts, root: URL,
    beforeTextRemoval: @Sendable () throws -> Void
  ) throws {
    let stem = try CommittedDiaryResource.requiredStem(resource.candidate)
    let parent = Array(resource.candidate.components.dropLast())
    let assets = Array(facts.audioComponents.dropLast())
    guard let audioName = facts.audioComponents.last else { throw CatalogIssue.unsafe }
    let day = try CatalogSafeFiles.descriptor(root: root, components: parent, directory: true)
    defer { close(day) }
    let audioParent = try CatalogSafeFiles.descriptor(
      root: root, components: assets, directory: true)
    defer { close(audioParent) }
    func validate() throws {
      guard try CommittedDiaryResource.rootIdentity(root) == facts.rootIdentity else {
        throw CatalogIssue.changed
      }
      try attached(day, root: root, components: parent)
      try attached(audioParent, root: root, components: assets)
    }
    try validate()
    try unlinkFile(audioName, parent: audioParent, version: facts.version.audioIdentity)
    do {
      try beforeTextRemoval()
      try validate()
      try unlinkFile(stem + ".md", parent: day, version: facts.version.markdownIdentity)
    } catch {
      throw DiaryDeletionIssue.incomplete
    }
    // Empty container cleanup is optional. ENOTEMPTY preserves all unrelated contents.
    if (try? validate()) != nil { _ = unlinkat(day, stem + ".assets", AT_REMOVEDIR) }
  }

  private static func attached(_ descriptor: Int32, root: URL, components: [String]) throws {
    let current = try CatalogSafeFiles.descriptor(
      root: root, components: components, directory: true)
    defer { close(current) }
    var original = stat()
    var observed = stat()
    guard fstat(descriptor, &original) == 0, fstat(current, &observed) == 0,
      original.st_dev == observed.st_dev, original.st_ino == observed.st_ino
    else { throw CatalogIssue.changed }
  }

  private static func unlinkFile(_ name: String, parent: Int32, version: String) throws {
    var info = stat()
    guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
      (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1,
      DiaryFileIdentity.versionIdentity(info) == version
    else { throw CatalogIssue.changed }
    guard unlinkat(parent, name, 0) == 0 else { throw DiaryDeletionIssue.unavailable }
  }
}

// swiftlint:enable closure_parameter_position opening_brace
