import Darwin
import Foundation

private struct ReplayCacheOwner: Codable {
  let schema: Int
  let leaseID: UUID
}

actor DiaryReplayCache {
  let files: DiaryEditPrivateFiles
  private let capacity: @Sendable (URL) -> Int64?

  init(
    root: URL? = nil, protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    capacity: @escaping @Sendable (URL) -> Int64? = { url in
      try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
    }
  ) {
    self.capacity = capacity
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    files = DiaryEditPrivateFiles(
      root: root ?? support.appending(path: "NarihitosDiary/PrivateWorkspaces/DiaryReplay"),
      protection: protection)
  }

  func prepare(_ id: UUID, bytes: Int64) throws -> URL {
    guard bytes > 0, bytes <= CatalogAudioInspector.maximumBytes else {
      throw DiaryEditIssue.unsupported
    }
    try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
    try files.protect(files.root)
    if let available = capacity(files.root), available < bytes { throw DiaryEditIssue.storage }
    let directory = try files.directory(id)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try files.protect(directory)
    try files.write(
      JSONEncoder().encode(ReplayCacheOwner(schema: 1, leaseID: id)), named: "owner.json", id: id)
    return directory
  }

  func validate(_ id: UUID, digest: String, maximumDuration: Double) throws -> Double {
    let directory = try files.directory(id)
    let audioURL = directory.appending(path: "audio.m4a")
    try files.protection.verify(audioURL)
    guard
      try audioURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else {
      throw DiaryEditIssue.localData
    }
    let result = try CatalogAudioInspector.inspect(
      root: directory, components: ["audio.m4a"], maximumDuration: maximumDuration,
      control: CatalogReadControl())
    guard result.version.split(separator: ":").last.map(String.init) == digest else {
      throw DiaryEditIssue.changed
    }
    return result.duration
  }

  func remove(_ id: UUID) throws {
    let data = try files.read("owner.json", id: id, maximum: 4_096)
    let owner = try JSONDecoder().decode(ReplayCacheOwner.self, from: data)
    guard owner.schema == 1, owner.leaseID == id else { throw DiaryEditIssue.changed }
    let directory = try files.directory(id)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: directory, components: [], directory: true)
    defer { close(descriptor) }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    guard names.allSatisfy({ $0 == "owner.json" || $0 == "audio.m4a" }) else {
      throw DiaryEditIssue.changed
    }
    for name in names {
      let file = try CatalogSafeFiles.descriptor(
        root: directory, components: [name], directory: false)
      close(file)
    }
    if names.contains("audio.m4a"), unlinkat(descriptor, "audio.m4a", 0) != 0 {
      throw DiaryEditIssue.storage
    }
    guard unlinkat(descriptor, "owner.json", 0) == 0 else { throw DiaryEditIssue.storage }
    let parent = try CatalogSafeFiles.descriptor(root: files.root, components: [], directory: true)
    defer { close(parent) }
    guard unlinkat(parent, id.uuidString.lowercased(), AT_REMOVEDIR) == 0 else {
      throw DiaryEditIssue.storage
    }
  }

  /// The caller invokes this only when no live lease/acquisition exists, after
  /// the purge barrier is checked. Unknown or malformed files are preserved.
  func reconcile() async throws {
    try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: files.root, components: [], directory: true)
    guard let stream = fdopendir(descriptor) else {
      close(descriptor)
      throw DiaryEditIssue.localData
    }
    defer { closedir(stream) }
    var visited = 0
    while let entry = readdir(stream) {
      var name = entry.pointee.d_name
      let value = withUnsafePointer(to: &name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: 1_024) { String(cString: $0) }
      }
      if let id = UUID(uuidString: value), id.uuidString.lowercased() == value { try? remove(id) }
      visited += 1
      if visited.isMultiple(of: 50) { await Task.yield() }
    }
  }
}
