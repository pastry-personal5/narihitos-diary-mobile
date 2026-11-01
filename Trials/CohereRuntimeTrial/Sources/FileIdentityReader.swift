import CryptoKit
import Foundation

enum FileIdentityReader {
  static func read(url: URL, cancellation: CancellationFlag? = nil) throws -> FileIdentity {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    guard let fileSize = values.fileSize else { throw CocoaError(.fileReadUnknown) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    var byteCount: Int64 = 0
    while let data = try handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty {
      if cancellation?.isCancelled() == true { throw CancellationError() }
      let (nextByteCount, overflow) = byteCount.addingReportingOverflow(Int64(data.count))
      guard !overflow else { throw CocoaError(.fileReadTooLarge) }
      byteCount = nextByteCount
      hasher.update(data: data)
    }
    if cancellation?.isCancelled() == true { throw CancellationError() }

    let finalValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    guard byteCount == Int64(fileSize), finalValues.fileSize == fileSize,
      finalValues.contentModificationDate == values.contentModificationDate
    else { throw TrialValidationError.inputsChangedAfterPreflight }

    return FileIdentity(
      filename: url.lastPathComponent,
      byteCount: byteCount,
      sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      modifiedAt: values.contentModificationDate
    )
  }
}

enum TrialPreflight {
  static func inspect(
    modelURL: URL,
    audioURL: URL,
    cancellation: CancellationFlag? = nil
  ) throws -> TrialInputSummary {
    let started = ProcessInfo.processInfo.systemUptime
    guard let quantization = ModelQuantization.from(filename: modelURL.lastPathComponent) else {
      throw TrialValidationError.unsupportedModelCandidate
    }
    let modelFile = try FileIdentityReader.read(url: modelURL, cancellation: cancellation)
    guard modelFile.sha256 == quantization.expectedSHA256 else {
      throw TrialValidationError.modelArtifactMismatch
    }
    return TrialInputSummary(
      model: ModelIdentity(
        file: modelFile,
        quantization: quantization
      ),
      audioFile: try FileIdentityReader.read(url: audioURL, cancellation: cancellation),
      audioDurationSeconds: try AudioDecoder.sourceDuration(url: audioURL),
      inspectionSeconds: ProcessInfo.processInfo.systemUptime - started
    )
  }

  static func verifyUnchanged(
    summary: TrialInputSummary,
    modelURL: URL,
    audioURL: URL,
    cancellation: CancellationFlag
  ) throws {
    if cancellation.isCancelled() { throw CancellationError() }
    try verify(identity: summary.model.file, url: modelURL, cancellation: cancellation)
    if cancellation.isCancelled() { throw CancellationError() }
    try verify(identity: summary.audioFile, url: audioURL, cancellation: cancellation)
  }

  private static func verify(
    identity: FileIdentity,
    url: URL,
    cancellation: CancellationFlag
  ) throws {
    let current = try FileIdentityReader.read(url: url, cancellation: cancellation)
    guard current == identity else {
      throw TrialValidationError.inputsChangedAfterPreflight
    }
  }
}
