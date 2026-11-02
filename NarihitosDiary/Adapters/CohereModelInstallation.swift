// swiftlint:disable file_length

import Combine
import CryptoKit
import Darwin
import Foundation
import UIKit

// The downloaded GGUF is data. Executable runtime code is the separately pinned,
// app-signed XCFramework described by CohereRuntimeProvenance.
struct CohereTrustedModel: Codable, Equatable, Sendable {
  static let schemaVersion = 1

  let schema: Int
  let descriptorRevision: String
  let modelID: String
  let quantization: String
  let repository: String
  let repositoryRevision: String
  let filename: String
  let downloadURL: String
  let byteCount: Int64
  let sha256: String
  let allowedRedirectHosts: Set<String>
  let approvedLanguages: Set<String>
  let runtimeIdentity: String
  let conversionIdentity: String
  let chunkingIdentity: String
  let revoked: Bool

  static let productionQ4 = CohereTrustedModel(
    schema: schemaVersion,
    descriptorRevision: "ndm.cohere-model-approval-v1",
    modelID: "cohere-transcribe-03-2026",
    quantization: "Q4_K_M",
    repository: "handy-computer/cohere-transcribe-03-2026-gguf",
    repositoryRevision: "7353b6040bdc1be9e5a3823d99d5fe12afe88264",
    filename: "cohere-transcribe-03-2026-Q4_K_M.gguf",
    downloadURL:
      "https://huggingface.co/handy-computer/cohere-transcribe-03-2026-gguf/resolve/"
      + "7353b6040bdc1be9e5a3823d99d5fe12afe88264/"
      + "cohere-transcribe-03-2026-Q4_K_M.gguf",
    byteCount: 1_558_162_944,
    sha256: "0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb",
    allowedRedirectHosts: ["huggingface.co", "us.aws.cdn.hf.co"],
    approvedLanguages: ["en", "ko"],
    runtimeIdentity: CohereRuntimeProvenance.identity,
    conversionIdentity: CohereAudioConversion.identity,
    chunkingIdentity: CohereChunkPlanner.identity,
    revoked: false)

  static let productionQ5 = CohereTrustedModel(
    schema: schemaVersion,
    descriptorRevision: "ndm.cohere-model-approval-v1-q5",
    modelID: "cohere-transcribe-03-2026",
    quantization: "Q5_K_M",
    repository: "handy-computer/cohere-transcribe-03-2026-gguf",
    repositoryRevision: "7353b6040bdc1be9e5a3823d99d5fe12afe88264",
    filename: "cohere-transcribe-03-2026-Q5_K_M.gguf",
    downloadURL:
      "https://huggingface.co/handy-computer/cohere-transcribe-03-2026-gguf/resolve/"
      + "7353b6040bdc1be9e5a3823d99d5fe12afe88264/"
      + "cohere-transcribe-03-2026-Q5_K_M.gguf",
    byteCount: 1_770_270_208,
    sha256: "14d02f1ad6dd77b3a60f82639879012c3adb4fe25c50a5a47a2c4c661daf1558",
    allowedRedirectHosts: ["huggingface.co", "us.aws.cdn.hf.co"],
    approvedLanguages: ["en", "ko"],
    runtimeIdentity: CohereRuntimeProvenance.identity,
    conversionIdentity: CohereAudioConversion.identity,
    chunkingIdentity: CohereChunkPlanner.identity,
    revoked: false)

  // Kept as the compatibility name for existing Q4 callers and historical tests.
  static let production = productionQ4

  var installationIdentity: String {
    "\(descriptorRevision):\(repositoryRevision):\(quantization):\(sha256)"
  }

  func validatedURL() throws -> URL {
    guard schema == Self.schemaVersion, !revoked,
      !descriptorRevision.isEmpty, modelID == "cohere-transcribe-03-2026",
      quantization == "Q4_K_M" || quantization == "Q5_K_M",
      repository == "handy-computer/cohere-transcribe-03-2026-gguf",
      repositoryRevision.utf8.count == 40,
      repositoryRevision.utf8.allSatisfy(Self.isLowerHex),
      filename == "cohere-transcribe-03-2026-\(quantization).gguf",
      byteCount > 0, sha256.utf8.count == 64, sha256.utf8.allSatisfy(Self.isLowerHex),
      allowedRedirectHosts == ["huggingface.co", "us.aws.cdn.hf.co"],
      approvedLanguages == ["en", "ko"],
      runtimeIdentity == CohereRuntimeProvenance.identity,
      conversionIdentity == CohereAudioConversion.identity,
      chunkingIdentity == CohereChunkPlanner.identity,
      let url = URL(string: downloadURL), url.scheme == "https",
      url.host == "huggingface.co", url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil,
      url.path == "/\(repository)/resolve/\(repositoryRevision)/\(filename)"
    else { throw CohereModelFailure.invalidDescriptor }
    return url
  }

  private static func isLowerHex(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (97...102).contains(byte)
  }
}

enum CohereRuntimeProvenance {
  static let version = "0.2.4"
  static let commit = "4807eda"
  static let identity = "transcribe.cpp/\(version)+\(commit)"
  static let archiveBytes: Int64 = 8_399_649
  static let archiveSHA256 = "243e96ea569583245c9732de3955111210d986c03a34b81424dacde169f9de6a"
}

enum CohereModelFailure: Error, Equatable, Sendable {
  case invalidDescriptor
  case insufficientSpace
  case unavailableCapacity
  case invalidRedirect
  case invalidResponse
  case invalidSize
  case invalidDigest
  case invalidModel
  case unsafeResource
  case protectedDataUnavailable
  case contended
  case cancelled
  case storage

  var userMessage: String {
    switch self {
    case .insufficientSpace: "Not enough storage is available to install the Cohere model."
    case .unavailableCapacity: "Storage availability could not be checked. Try again later."
    case .protectedDataUnavailable: "Unlock this iPhone to check the Cohere model."
    case .contended: "The Cohere model is currently in use. Try again when transcription finishes."
    case .cancelled: "Cohere model installation was cancelled."
    default: "The Cohere model could not be installed. Try again."
    }
  }
}

enum CohereModelReadiness: Equatable, Sendable {
  case checking
  case notInstalled
  case ready(String)
  case failed(CohereModelFailure)
}

struct CohereInstallProgress: Equatable, Sendable {
  let receivedBytes: Int64
  let expectedBytes: Int64

  var fraction: Double? {
    guard expectedBytes > 0 else { return nil }
    return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
  }
}

struct CohereModelLease: Equatable, Sendable {
  let url: URL
  let identity: String
}

protocol CohereModelDownloading: Sendable {
  func download(
    from source: URL, to destination: URL, expectedBytes: Int64, allowedHosts: Set<String>,
    progress: @escaping @Sendable (Int64) -> Void
  ) async throws
}

final class HTTPSCohereModelDownloader: NSObject, CohereModelDownloading, @unchecked Sendable {
  func download(
    from source: URL, to destination: URL, expectedBytes: Int64, allowedHosts: Set<String>,
    progress: @escaping @Sendable (Int64) -> Void
  ) async throws {
    let operation = DownloadOperation(
      source: source, destination: destination, expectedBytes: expectedBytes,
      allowedHosts: allowedHosts, progress: progress)
    try await operation.run()
  }
}

private final class DownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let source: URL
  private let destination: URL
  private let expectedBytes: Int64
  private let allowedHosts: Set<String>
  private let progress: @Sendable (Int64) -> Void
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var failure: CohereModelFailure?
  private var didMoveFile = false
  private var redirectCount = 0
  private var session: URLSession?

  init(
    source: URL, destination: URL, expectedBytes: Int64, allowedHosts: Set<String>,
    progress: @escaping @Sendable (Int64) -> Void
  ) {
    self.source = source
    self.destination = destination
    self.expectedBytes = expectedBytes
    self.allowedHosts = allowedHosts
    self.progress = progress
  }

  func run() async throws {
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await startDownload()
    } onCancel: {
      self.fail(.cancelled)
    }
  }

  private func startDownload() async throws {
    let _: Void = try await withCheckedThrowingContinuation { continuation in
      guard !Task<Never, Never>.isCancelled else {
        continuation.resume(throwing: CohereModelFailure.cancelled)
        return
      }
      lock.withLock { self.continuation = continuation }
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieStorage = nil
      configuration.urlCredentialStorage = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      configuration.timeoutIntervalForRequest = 60
      configuration.timeoutIntervalForResource = 60 * 60 * 4
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      lock.withLock { self.session = session }
      session.downloadTask(with: source).resume()
      if lock.withLock({ failure != nil }) { session.invalidateAndCancel() }
    }
  }

  func urlSession(
    _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    let allowed = lock.withLock { () -> Bool in
      redirectCount += 1
      guard redirectCount <= 3, request.url?.scheme == "https",
        let host = request.url?.host, allowedHosts.contains(host), request.url?.user == nil,
        request.url?.password == nil
      else {
        failure = .invalidRedirect
        return false
      }
      return true
    }
    completionHandler(allowed ? request : nil)
  }

  func urlSession(
    _: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64
  ) {
    guard totalBytesWritten <= expectedBytes else {
      lock.withLock { failure = .invalidSize }
      downloadTask.cancel()
      return
    }
    progress(totalBytesWritten)
  }

  func urlSession(
    _: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard lock.withLock({ failure == nil }) else { return }
    guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
      response.url?.scheme == "https", let host = response.url?.host,
      allowedHosts.contains(host),
      response.value(forHTTPHeaderField: "Content-Encoding").map({ $0 == "identity" }) ?? true,
      response.expectedContentLength == NSURLSessionTransferSizeUnknown
        || response.expectedContentLength == expectedBytes,
      downloadTask.countOfBytesReceived == expectedBytes
    else {
      lock.withLock { failure = .invalidResponse }
      return
    }
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      lock.withLock { didMoveFile = true }
    } catch {
      lock.withLock { failure = .storage }
    }
  }

  func urlSession(
    _: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    let outcome: Result<Void, any Error> = lock.withLock {
      if let failure { return .failure(failure) }
      if error != nil { return .failure(CohereModelFailure.invalidResponse) }
      return didMoveFile ? .success(()) : .failure(CohereModelFailure.invalidResponse)
    }
    finish(outcome)
  }

  private func fail(_ failure: CohereModelFailure) {
    let session = lock.withLock { () -> URLSession? in
      if self.failure == nil { self.failure = failure }
      return self.session
    }
    session?.invalidateAndCancel()
  }

  private func finish(_ result: Result<Void, any Error>) {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
      let value = self.continuation
      self.continuation = nil
      session?.finishTasksAndInvalidate()
      session = nil
      return value
    }
    continuation?.resume(with: result)
  }
}

private struct CohereInstallationRecord: Codable, Equatable {
  let schema: Int
  let descriptorRevision: String
  let installationIdentity: String
  let byteCount: Int64
  let modificationSeconds: TimeInterval
}

// The manager keeps installation and lease mutation on the main actor. Network and hashing work
// stream through bounded adapter operations rather than retaining model bytes here.
@MainActor
// swiftlint:disable:next type_body_length
final class CohereModelManager: ObservableObject {
  static let reserveBytes: Int64 = 1_073_741_824
  static let metadataAllowanceBytes: Int64 = 1_048_576
  private static var activeInstallationIdentity: String?

  @Published private(set) var readiness: CohereModelReadiness = .checking
  @Published private(set) var progress: CohereInstallProgress?
  @Published private(set) var isInstalling = false

  let descriptor: CohereTrustedModel
  private let root: URL
  private let manager: FileManager
  private let downloader: any CohereModelDownloading
  private let availableCapacity: @Sendable (URL) throws -> Int64?
  private let protectedDataAvailable: () -> Bool
  private var installationTask: Task<Void, Never>?
  private var leaseCount = 0

  init(
    descriptor: CohereTrustedModel = .production, root: URL? = nil,
    manager: FileManager = .default,
    downloader: any CohereModelDownloading = HTTPSCohereModelDownloader(),
    availableCapacity: @escaping @Sendable (URL) throws -> Int64? = { url in
      try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
    },
    protectedDataAvailable: @escaping () -> Bool = {
      UIApplication.shared.isProtectedDataAvailable
    }
  ) {
    self.descriptor = descriptor
    self.manager = manager
    self.downloader = downloader
    self.availableCapacity = availableCapacity
    self.protectedDataAvailable = protectedDataAvailable
    if let root {
      self.root = root
    } else {
      let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "NarihitosDiary/CohereModel", directoryHint: .isDirectory)
      // Keep the shipped Q4 location for upgrade compatibility; Q5 gets an
      // isolated root so records, staging, and leases can never cross variants.
      self.root =
        descriptor.quantization == "Q4_K_M"
        ? base
        : base.appending(path: descriptor.quantization, directoryHint: .isDirectory)
    }
  }

  var downloadByteCount: Int64 { descriptor.byteCount }

  func refresh() async -> CohereModelReadiness {
    if isInstalling { return .checking }
    readiness = .checking
    guard protectedDataAvailable() else {
      readiness = .failed(.protectedDataUnavailable)
      return readiness
    }
    do {
      _ = try descriptor.validatedURL()
      try prepareRoot()
      try removeAbandonedStaging()
      guard try verifyPublishedInstallation() else {
        readiness = .notInstalled
        return readiness
      }
      readiness = .ready(descriptor.installationIdentity)
    } catch let failure as CohereModelFailure {
      readiness = .failed(failure)
    } catch {
      readiness = .failed(.storage)
    }
    return readiness
  }

  func install() {
    guard installationTask == nil else { return }
    guard Self.activeInstallationIdentity == nil else {
      readiness = .failed(.contended)
      return
    }
    Self.activeInstallationIdentity = descriptor.installationIdentity
    isInstalling = true
    progress = CohereInstallProgress(receivedBytes: 0, expectedBytes: descriptor.byteCount)
    installationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.performInstallation()
        self.isInstalling = false
        _ = await self.refresh()
      } catch let failure as CohereModelFailure {
        self.readiness = .failed(failure)
      } catch is CancellationError {
        self.readiness = .failed(.cancelled)
      } catch {
        self.readiness = .failed(.storage)
      }
      self.isInstalling = false
      self.progress = nil
      self.installationTask = nil
      if Self.activeInstallationIdentity == self.descriptor.installationIdentity {
        Self.activeInstallationIdentity = nil
      }
    }
  }

  func cancelInstallation() { installationTask?.cancel() }

  func acquireLease() throws -> CohereModelLease {
    guard case .ready(let identity) = readiness,
      identity == descriptor.installationIdentity, try verifyPublishedInstallation()
    else { throw CohereModelFailure.invalidModel }
    leaseCount += 1
    return CohereModelLease(url: modelURL, identity: identity)
  }

  func release(_ lease: CohereModelLease) {
    guard lease.identity == descriptor.installationIdentity, leaseCount > 0 else { return }
    leaseCount -= 1
  }

  private var modelURL: URL {
    root.appending(path: "approved-model-v1.gguf", directoryHint: .notDirectory)
  }

  private var recordURL: URL {
    root.appending(path: "active-installation-v1.json", directoryHint: .notDirectory)
  }

  // swiftlint:disable:next function_body_length
  private func performInstallation() async throws {
    guard protectedDataAvailable() else { throw CohereModelFailure.protectedDataUnavailable }
    let source = try descriptor.validatedURL()
    try prepareRoot()
    if try verifyPublishedInstallation() { return }
    guard leaseCount == 0 else { throw CohereModelFailure.contended }
    let preservedBytes = manager.fileExists(atPath: modelURL.path) ? descriptor.byteCount : 0
    let required = try Self.requiredAvailableBytes(
      modelBytes: descriptor.byteCount, preservedBytes: preservedBytes)
    guard let capacity = try availableCapacity(root) else {
      throw CohereModelFailure.unavailableCapacity
    }
    guard capacity >= required, capacity >= Self.reserveBytes else {
      throw CohereModelFailure.insufficientSpace
    }
    let staging = root.appending(path: ".download-\(UUID().uuidString.lowercased())")
    defer { try? manager.removeItem(at: staging) }
    try await downloader.download(
      from: source, to: staging, expectedBytes: descriptor.byteCount,
      allowedHosts: descriptor.allowedRedirectHosts
    ) { [weak self] received in
      Task { @MainActor in
        guard let self, self.installationTask != nil else { return }
        self.progress = CohereInstallProgress(
          receivedBytes: received, expectedBytes: self.descriptor.byteCount)
      }
    }
    try Task.checkCancellation()
    try Self.verifyArtifact(staging, descriptor: descriptor)
    try Task.checkCancellation()
    try applyBackupExclusion(staging)
    try manager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: staging.path)
    try Task.checkCancellation()
    if manager.fileExists(atPath: modelURL.path) {
      _ = try manager.replaceItemAt(modelURL, withItemAt: staging)
    } else {
      try manager.moveItem(at: staging, to: modelURL)
    }
    try applyBackupExclusion(modelURL)
    try Self.verifyArtifact(modelURL, descriptor: descriptor)
    let publishedAttributes = try manager.attributesOfItem(atPath: modelURL.path)
    let modified =
      (publishedAttributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
    let record = CohereInstallationRecord(
      schema: 1, descriptorRevision: descriptor.descriptorRevision,
      installationIdentity: descriptor.installationIdentity,
      byteCount: descriptor.byteCount, modificationSeconds: modified)
    let data = try JSONEncoder().encode(record)
    try data.write(
      to: recordURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try applyBackupExclusion(recordURL)
  }

  static func requiredAvailableBytes(modelBytes: Int64, preservedBytes: Int64) throws -> Int64 {
    guard modelBytes > 0, preservedBytes >= 0,
      modelBytes <= (Int64.max - preservedBytes - reserveBytes - metadataAllowanceBytes) / 2
    else { throw CohereModelFailure.invalidDescriptor }
    return modelBytes * 2 + preservedBytes + reserveBytes + metadataAllowanceBytes
  }

  private func prepareRoot() throws {
    try manager.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw CohereModelFailure.unsafeResource
    }
    try applyBackupExclusion(root)
  }

  private func removeAbandonedStaging() throws {
    guard leaseCount == 0 else { return }
    let contents = try manager.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    for url in contents where url.lastPathComponent.hasPrefix(".download-") {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink == false else {
        throw CohereModelFailure.unsafeResource
      }
      try manager.removeItem(at: url)
    }
  }

  private func verifyPublishedInstallation() throws -> Bool {
    guard manager.fileExists(atPath: modelURL.path), manager.fileExists(atPath: recordURL.path)
    else { return false }
    let recordDescriptor = Darwin.open(recordURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard recordDescriptor >= 0 else { throw CohereModelFailure.unsafeResource }
    let recordHandle = FileHandle(fileDescriptor: recordDescriptor, closeOnDealloc: true)
    var recordStatus = stat()
    guard fstat(recordDescriptor, &recordStatus) == 0,
      (recordStatus.st_mode & S_IFMT) == S_IFREG, recordStatus.st_nlink == 1,
      recordStatus.st_size > 0, recordStatus.st_size <= 16 * 1_024,
      try recordURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        == true,
      let recordData = try recordHandle.read(upToCount: 16 * 1_024 + 1),
      Int64(recordData.count) == recordStatus.st_size,
      let record = try? JSONDecoder().decode(CohereInstallationRecord.self, from: recordData),
      record.schema == 1, record.descriptorRevision == descriptor.descriptorRevision,
      record.installationIdentity == descriptor.installationIdentity,
      record.byteCount == descriptor.byteCount
    else { return false }
    let attributes = try manager.attributesOfItem(atPath: modelURL.path)
    guard (attributes[.size] as? NSNumber)?.int64Value == descriptor.byteCount,
      let modified = attributes[.modificationDate] as? Date
    else { return false }
    // swiftlint:disable trailing_comma
    let values = try modelURL.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isExcludedFromBackupKey,
    ])
    // swiftlint:enable trailing_comma
    guard values.isRegularFile == true, values.isSymbolicLink == false,
      values.isAliasFile != true, values.isExcludedFromBackup == true
    else { return false }
    guard abs(modified.timeIntervalSinceReferenceDate - record.modificationSeconds) <= 0.001
    else { return false }
    try Self.verifyArtifact(modelURL, descriptor: descriptor)
    return true
  }

  private func applyBackupExclusion(_ url: URL) throws {
    var mutable = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try mutable.setResourceValues(values)
    guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else { throw CohereModelFailure.storage }
  }

  private static func verifyArtifact(_ url: URL, descriptor: CohereTrustedModel) throws {
    let fileDescriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fileDescriptor >= 0 else { throw CohereModelFailure.unsafeResource }
    let handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    var initial = stat()
    guard fstat(fileDescriptor, &initial) == 0, (initial.st_mode & S_IFMT) == S_IFREG,
      initial.st_nlink == 1, initial.st_size == descriptor.byteCount
    else { throw CohereModelFailure.invalidSize }
    guard let header = try handle.read(upToCount: 8), header.count == 8,
      Array(header.prefix(4)) == [0x47, 0x47, 0x55, 0x46]
    else { throw CohereModelFailure.invalidModel }
    let version = header.dropFirst(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    guard (2...3).contains(UInt32(littleEndian: version)) else {
      throw CohereModelFailure.invalidModel
    }
    try handle.seek(toOffset: 0)
    var hash = SHA256()
    var readBytes: Int64 = 0
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      readBytes += Int64(data.count)
      guard readBytes <= descriptor.byteCount else { throw CohereModelFailure.invalidSize }
      hash.update(data: data)
    }
    var final = stat()
    guard fstat(fileDescriptor, &final) == 0, initial.st_dev == final.st_dev,
      initial.st_ino == final.st_ino, initial.st_size == final.st_size,
      initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
      initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
      readBytes == descriptor.byteCount
    else { throw CohereModelFailure.invalidSize }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest == descriptor.sha256 else { throw CohereModelFailure.invalidDigest }
  }
}
