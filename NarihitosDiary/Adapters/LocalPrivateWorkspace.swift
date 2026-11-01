import Foundation

// swift-format's canonical multiline collections conflict with SwiftLint's trailing-comma rule.
// swiftlint:disable trailing_comma

protocol FileProtectionPolicy: Sendable {
  func applyAndVerify(to fileURL: URL) throws
}

struct NoFileProtectionPolicy: FileProtectionPolicy {
  func applyAndVerify(to _: URL) throws {}
}

enum WorkspaceFailurePoint: Equatable, Sendable {
  case afterTemporaryWrite
  case afterAttributes
  case afterRecoveryMove
  case afterDestinationMove
}

final class LocalPrivateWorkspace: PrivateWorkspacePort {
  static let maximumArtifactBytes = 64 * 1_024 * 1_024

  private let fileManager: FileManager
  private let root: URL
  private let adapterID = UUID()
  private let protectionPolicy: any FileProtectionPolicy
  private let failureInjector: (@Sendable (WorkspaceFailurePoint) throws -> Void)?
  private var issuedHandles: [WorkspaceID: UUID] = [:]
  private let lock = NSLock()

  var resolvedRoot: URL { root }

  static func production(
    fileManager: FileManager = .default,
    protectionPolicy: any FileProtectionPolicy = NoFileProtectionPolicy()
  ) throws -> LocalPrivateWorkspace {
    guard
      let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      throw PrivateWorkspaceFailureCode.storageUnavailable
    }
    return try LocalPrivateWorkspace(
      root: support.appending(
        path: "NarihitosDiary/PrivateWorkspaces", directoryHint: .isDirectory),
      fileManager: fileManager,
      protectionPolicy: protectionPolicy)
  }

  init(
    root: URL,
    fileManager: FileManager = .default,
    protectionPolicy: any FileProtectionPolicy = NoFileProtectionPolicy(),
    failureInjector: (@Sendable (WorkspaceFailurePoint) throws -> Void)? = nil
  ) throws {
    guard root.isFileURL, root.pathComponents.count > 2 else {
      throw PrivateWorkspaceFailureCode.unsafeResource
    }
    self.fileManager = fileManager
    self.root = root.standardizedFileURL
    self.protectionPolicy = protectionPolicy
    self.failureInjector = failureInjector
    do {
      try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
      try Self.requirePlainDirectory(self.root)
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch {
      throw PrivateWorkspaceFailureCode.storageUnavailable
    }
  }

  func allocate(id: WorkspaceID) throws -> WorkspaceHandle {
    let url = workspaceURL(id)
    do {
      try Self.requirePlainDirectory(root)
      try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
      try Self.requirePlainDirectory(url)
      return issueHandle(id)
    } catch CocoaError.fileWriteFileExists {
      throw PrivateWorkspaceFailureCode.invalidIdentity
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch {
      throw PrivateWorkspaceFailureCode.storageUnavailable
    }
  }

  func reopen(id: WorkspaceID) throws -> WorkspaceHandle {
    let url = workspaceURL(id)
    do {
      try Self.requirePlainDirectory(root)
      try Self.requirePlainDirectory(url)
      return issueHandle(id)
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch {
      throw PrivateWorkspaceFailureCode.resourceMissing
    }
  }

  func artifact(_ role: PrivateArtifactRole, in handle: WorkspaceHandle) throws -> ArtifactHandle {
    _ = try validatedWorkspaceURL(handle)
    return ArtifactHandle(workspace: handle, role: role)
  }

  func read(_ artifact: ArtifactHandle) throws -> Data {
    let url = try validatedArtifactURL(artifact, mustExist: true)
    guard let stream = InputStream(url: url) else {
      throw PrivateWorkspaceFailureCode.storageUnavailable
    }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else { throw PrivateWorkspaceFailureCode.storageUnavailable }
      if count == 0 { break }
      guard result.count <= Self.maximumArtifactBytes - count else {
        throw PrivateWorkspaceFailureCode.resourceTooLarge
      }
      result.append(buffer, count: count)
    }
    return result
  }

  func replace(_ artifact: ArtifactHandle, with data: Data) throws {
    guard data.count <= Self.maximumArtifactBytes else {
      throw PrivateWorkspaceFailureCode.resourceTooLarge
    }
    let workspace = try validatedWorkspaceURL(artifact.workspace)
    let destination = workspace.appending(
      path: artifact.role.ownedFilename, directoryHint: .notDirectory)
    let temporary = workspace.appending(
      path: ".write-\(UUID().uuidString.lowercased())", directoryHint: .notDirectory)
    let recovery = workspace.appending(
      path: ".recovery-\(artifact.role.rawValue)", directoryHint: .notDirectory)
    var hadPrior = false
    var publishedReplacement = false
    do {
      try Self.requirePlainDirectory(workspace)
      try prepareTemporary(temporary, with: data)
      guard !fileManager.fileExists(atPath: recovery.path) else {
        throw PrivateWorkspaceFailureCode.atomicWriteFailed
      }

      if fileManager.fileExists(atPath: destination.path) {
        hadPrior = true
        try Self.requirePlainFile(destination)
        _ = try fileManager.replaceItemAt(
          destination, withItemAt: temporary, backupItemName: recovery.lastPathComponent,
          options: [.withoutDeletingBackupItem])
        publishedReplacement = true
        try Self.requirePlainFile(recovery)
        try applyAndVerifyAttributes(recovery)
      } else {
        try failureInjector?(.afterRecoveryMove)
        try fileManager.moveItem(at: temporary, to: destination)
        publishedReplacement = true
      }
      if hadPrior { try failureInjector?(.afterRecoveryMove) }
      try failureInjector?(.afterDestinationMove)
      try applyAndVerifyAttributes(destination)
      try verify(destination, equals: data)
      if hadPrior { try fileManager.removeItem(at: recovery) }
    } catch let code as PrivateWorkspaceFailureCode {
      rollbackReplacement(
        destination: destination, recovery: recovery, hadPrior: hadPrior,
        publishedReplacement: publishedReplacement, temporary: temporary)
      throw code
    } catch {
      rollbackReplacement(
        destination: destination, recovery: recovery, hadPrior: hadPrior,
        publishedReplacement: publishedReplacement, temporary: temporary)
      throw PrivateWorkspaceFailureCode.atomicWriteFailed
    }
  }

  func remove(_ artifact: ArtifactHandle) throws {
    let url = try validatedArtifactURL(artifact, mustExist: true)
    do {
      try fileManager.removeItem(at: url)
    } catch {
      throw PrivateWorkspaceFailureCode.storageUnavailable
    }
  }

  func remove(_ workspace: WorkspaceHandle) throws {
    let url = try validatedWorkspaceURL(workspace)
    do {
      let children = try fileManager.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
      for child in children {
        let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
          throw PrivateWorkspaceFailureCode.unsafeResource
        }
      }
      try fileManager.removeItem(at: url)
      lock.lock()
      issuedHandles.removeValue(forKey: workspace.workspaceID)
      lock.unlock()
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch {
      throw PrivateWorkspaceFailureCode.storageUnavailable
    }
  }

  private func issueHandle(_ id: WorkspaceID) -> WorkspaceHandle {
    let nonce = UUID()
    lock.lock()
    issuedHandles[id] = nonce
    lock.unlock()
    return WorkspaceHandle(adapterID: adapterID, workspaceID: id, nonce: nonce)
  }

  private func workspaceURL(_ id: WorkspaceID) -> URL {
    root.appending(path: id.description, directoryHint: .isDirectory).standardizedFileURL
  }

  private func validatedWorkspaceURL(_ handle: WorkspaceHandle) throws -> URL {
    guard handle.adapterID == adapterID else { throw PrivateWorkspaceFailureCode.invalidHandle }
    lock.lock()
    let expectedNonce = issuedHandles[handle.workspaceID]
    lock.unlock()
    guard expectedNonce == handle.nonce else { throw PrivateWorkspaceFailureCode.invalidHandle }
    let candidate = workspaceURL(handle.workspaceID)
    let candidateParent = candidate.deletingLastPathComponent().standardizedFileURL
    guard candidateParent.pathComponents == root.pathComponents else {
      throw PrivateWorkspaceFailureCode.unsafeResource
    }
    try Self.requirePlainDirectory(root)
    try Self.requirePlainDirectory(candidate)
    return candidate
  }

  private func validatedArtifactURL(_ handle: ArtifactHandle, mustExist: Bool) throws -> URL {
    let workspace = try validatedWorkspaceURL(handle.workspace)
    let candidate = workspace.appending(
      path: handle.role.ownedFilename, directoryHint: .notDirectory
    )
    .standardizedFileURL
    guard candidate.deletingLastPathComponent() == workspace else {
      throw PrivateWorkspaceFailureCode.unsafeResource
    }
    if mustExist { try Self.requirePlainFile(candidate) }
    return candidate
  }

}

extension LocalPrivateWorkspace {
  fileprivate func applyAndVerifyAttributes(_ url: URL) throws {
    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutableURL = url
      try mutableURL.setResourceValues(values)
      let check = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      guard check.isExcludedFromBackup == true else {
        throw PrivateWorkspaceFailureCode.backupExclusionFailed
      }
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch {
      throw PrivateWorkspaceFailureCode.backupExclusionFailed
    }
    do {
      try protectionPolicy.applyAndVerify(to: url)
    } catch {
      throw PrivateWorkspaceFailureCode.protectionPolicyFailed
    }
  }

  fileprivate func prepareTemporary(_ url: URL, with data: Data) throws {
    try data.write(to: url, options: [.withoutOverwriting])
    try failureInjector?(.afterTemporaryWrite)
    try applyAndVerifyAttributes(url)
    try verify(url, equals: data)
    try failureInjector?(.afterAttributes)
  }

  fileprivate func verify(_ url: URL, equals expected: Data) throws {
    guard let stream = InputStream(url: url) else {
      throw PrivateWorkspaceFailureCode.verificationFailed
    }
    stream.open()
    defer { stream.close() }
    var offset = 0
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else { throw PrivateWorkspaceFailureCode.verificationFailed }
      if count == 0 { break }
      guard offset + count <= expected.count,
        expected[offset..<(offset + count)].elementsEqual(buffer[0..<count])
      else { throw PrivateWorkspaceFailureCode.verificationFailed }
      offset += count
    }
    guard offset == expected.count else { throw PrivateWorkspaceFailureCode.verificationFailed }
  }

  fileprivate func restore(
    destination: URL, recovery: URL, hadPrior: Bool, publishedReplacement: Bool
  ) {
    guard publishedReplacement else { return }
    if hadPrior, fileManager.fileExists(atPath: recovery.path) {
      if fileManager.fileExists(atPath: destination.path) {
        try? fileManager.removeItem(at: destination)
      }
      try? fileManager.moveItem(at: recovery, to: destination)
    } else if !hadPrior, fileManager.fileExists(atPath: destination.path) {
      try? fileManager.removeItem(at: destination)
    }
  }

  fileprivate func rollbackReplacement(
    destination: URL, recovery: URL, hadPrior: Bool, publishedReplacement: Bool, temporary: URL
  ) {
    restore(
      destination: destination, recovery: recovery, hadPrior: hadPrior,
      publishedReplacement: publishedReplacement)
    try? fileManager.removeItem(at: temporary)
  }

  fileprivate static func requirePlainDirectory(_ url: URL) throws {
    do {
      let values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey,
      ])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw PrivateWorkspaceFailureCode.unsafeResource
      }
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch CocoaError.fileReadNoSuchFile {
      throw PrivateWorkspaceFailureCode.resourceMissing
    } catch {
      throw PrivateWorkspaceFailureCode.unsafeResource
    }
  }

  fileprivate static func requirePlainFile(_ url: URL) throws {
    do {
      let values = try url.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
      ])
      guard values.isRegularFile == true, values.isSymbolicLink != true,
        values.isAliasFile != true
      else { throw PrivateWorkspaceFailureCode.unsafeResource }
    } catch let code as PrivateWorkspaceFailureCode {
      throw code
    } catch CocoaError.fileReadNoSuchFile {
      throw PrivateWorkspaceFailureCode.resourceMissing
    } catch {
      throw PrivateWorkspaceFailureCode.unsafeResource
    }
  }
}

// swiftlint:enable trailing_comma
