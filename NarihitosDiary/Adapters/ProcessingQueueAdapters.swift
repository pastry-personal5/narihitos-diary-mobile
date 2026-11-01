import Foundation
import Security

// swift-format and SwiftLint disagree on trailing commas in multiline collections.
// swiftlint:disable trailing_comma

@MainActor
final class KeychainInstallationIdentity: InstallationIdentityPort {
  private static let service = "com.narihitosdiary.mobile.installation"
  private static let account = "installation-id-v1"

  func currentOrCreate() -> InstallationIdentityResult {
    switch current() {
    case .available(let value): return .available(value)
    case .temporarilyUnavailable: return .temporarilyUnavailable
    case .missing:
      var bytes = [UInt8](repeating: 0, count: 32)
      guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
        return .temporarilyUnavailable
      }
      let value = Data(bytes).base64EncodedString()
      let status = SecItemAdd(
        [
          kSecClass: kSecClassGenericPassword,
          kSecAttrService: Self.service,
          kSecAttrAccount: Self.account,
          kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
          kSecValueData: Data(value.utf8),
        ] as CFDictionary, nil)
      if status == errSecDuplicateItem { return current() }
      return status == errSecSuccess ? .available(value) : .temporarilyUnavailable
    }
  }

  func current() -> InstallationIdentityResult {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: Self.service,
        kSecAttrAccount: Self.account,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
      ] as CFDictionary, &result)
    if status == errSecItemNotFound { return .missing }
    guard status == errSecSuccess, let data = result as? Data,
      data.count <= 128, let value = String(data: data, encoding: .utf8), !value.isEmpty
    else { return .temporarilyUnavailable }
    return .available(value)
  }
}

@MainActor
final class CaptureQueueReceiptSource: QueueReceiptSourcePort {
  private let files: CapturePrivateFiles

  init(files: CapturePrivateFiles) { self.files = files }

  func pendingReceipts() -> [QueueReceipt] { files.pendingQueueReceipts() }
  func receipt(jobID: String) -> QueueReceipt? { files.queueReceipt(jobID: jobID) }
  func removePrivateCapture(jobID: String) throws { try files.removeWorkspace(jobID: jobID) }
}

@MainActor
final class FileQueueStore: QueueStorePort {
  static let maximumRecordBytes = 64 * 1_024

  private let manager: FileManager
  private let root: URL
  private let failureInjector: (() throws -> Void)?

  init(
    manager: FileManager = .default, root: URL? = nil,
    failureInjector: (() throws -> Void)? = nil
  ) {
    self.manager = manager
    self.root =
      root
      ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "NarihitosDiary/ProcessingQueue", directoryHint: .isDirectory)
    self.failureInjector = failureInjector
    try? manager.createDirectory(at: self.root, withIntermediateDirectories: true)
    try? applyAttributes(to: self.root)
  }

  func jobs() throws -> [QueueJob] {
    try requirePlainDirectory(root)
    let urls = try manager.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return urls.compactMap { url in
      guard url.pathExtension == "json", (try? requirePlainFile(url)) != nil,
        let attributes = try? manager.attributesOfItem(atPath: url.path),
        let size = (attributes[.size] as? NSNumber)?.intValue,
        size > 0, size <= Self.maximumRecordBytes,
        let data = try? Data(contentsOf: url),
        let job = try? JSONDecoder().decode(QueueJob.self, from: data),
        job.schema == QueueJob.schemaVersion,
        job.id == url.deletingPathExtension().lastPathComponent,
        (try? WorkspaceID(job.id)) != nil
      else { return nil }
      return job
    }
  }

  func createIfAbsent(_ job: QueueJob) throws -> QueueJob {
    let url = recordURL(job.id)
    if manager.fileExists(atPath: url.path) {
      guard let existing = try jobs().first(where: { $0.id == job.id }) else {
        throw QueueStoreFailure.corrupt
      }
      return existing
    }
    try write(job, to: url, replacing: false)
    return job
  }

  func replace(_ job: QueueJob) throws {
    let url = recordURL(job.id)
    guard manager.fileExists(atPath: url.path) else { throw QueueStoreFailure.corrupt }
    try write(job, to: url, replacing: true)
  }

  func remove(jobID: String) throws {
    let url = recordURL(jobID)
    try requirePlainFile(url)
    try failureInjector?()
    try manager.removeItem(at: url)
  }

  private func write(_ job: QueueJob, to url: URL, replacing: Bool) throws {
    guard job.schema == QueueJob.schemaVersion, (try? WorkspaceID(job.id)) != nil else {
      throw QueueStoreFailure.corrupt
    }
    let data = try JSONEncoder().encode(job)
    guard data.count <= Self.maximumRecordBytes else { throw QueueStoreFailure.corrupt }
    try requirePlainDirectory(root)
    let temporary = root.appending(path: ".write-\(UUID().uuidString.lowercased())")
    try data.write(
      to: temporary,
      options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
    try applyAttributes(to: temporary)
    guard try Data(contentsOf: temporary) == data else { throw QueueStoreFailure.unavailable }
    try failureInjector?()
    if replacing {
      _ = try manager.replaceItemAt(url, withItemAt: temporary)
    } else {
      try manager.moveItem(at: temporary, to: url)
    }
    try applyAttributes(to: url)
    guard try Data(contentsOf: url) == data else { throw QueueStoreFailure.unavailable }
  }

  private func recordURL(_ id: String) -> URL {
    root.appending(path: "\(id).json", directoryHint: .notDirectory)
  }

  private func applyAttributes(to url: URL) throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutable = url
    try mutable.setResourceValues(values)
    try manager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
    let observed = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard observed.isExcludedFromBackup == true else { throw QueueStoreFailure.unavailable }
  }

  private func requirePlainDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw QueueStoreFailure.unsafeResource
    }
  }

  private func requirePlainFile(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink == false,
      values.isAliasFile != true
    else { throw QueueStoreFailure.unsafeResource }
  }
}

@MainActor
final class ProductionTranscriptionSettings: TranscriptionSettingsPort {
  func selectedMethodID(for _: CaptureLanguage) -> String? { nil }

  func effectiveSettings(
    methodID _: String, language _: CaptureLanguage
  ) -> EffectiveTranscriptionSettings {
    EffectiveTranscriptionSettings(
      values: [:], modelIdentity: "unavailable", conversionIdentity: "unavailable")
  }
}

// swiftlint:enable trailing_comma
