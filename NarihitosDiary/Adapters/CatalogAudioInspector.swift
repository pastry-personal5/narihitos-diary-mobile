import AudioToolbox
import CryptoKit
import Darwin
import Foundation

final class CatalogReadControl: @unchecked Sendable {
  let metrics: CatalogPerformanceProbe?
  private let lock = NSLock()
  private var cancelled = false
  private var allowedAudio: Set<[String]>?
  private let deadline = ContinuousClock.now.advanced(by: .seconds(120))

  init(metrics: CatalogPerformanceProbe? = nil) { self.metrics = metrics }

  func allowAudio(_ paths: Set<[String]>) { lock.withLock { allowedAudio = paths } }
  func authorizeAudio(_ path: [String]) throws {
    guard lock.withLock({ allowedAudio == nil || allowedAudio?.contains(path) == true }) else {
      throw CatalogIssue.changed
    }
  }

  func cancel() { lock.withLock { cancelled = true } }
  func check() throws {
    guard !lock.withLock({ cancelled }), ContinuousClock.now < deadline else {
      throw CatalogIssue.unavailable
    }
  }
}

private final class CatalogAudioInput {
  let descriptor: Int32
  let size: Int64
  let control: CatalogReadControl
  init(descriptor: Int32, size: Int64, control: CatalogReadControl) {
    self.descriptor = descriptor
    self.size = size
    self.control = control
  }
}

struct CatalogAudioInspection: Sendable {
  let version: String
  let duration: Double
}

/// AudioToolbox reads a confined descriptor, never a path that could be swapped for a link.
enum CatalogAudioInspector {
  static let maximumBytes: Int64 = 64 * 1_024 * 1_024

  static func inspect(
    root: URL, components: [String], maximumDuration: Double,
    control: CatalogReadControl
  ) throws -> CatalogAudioInspection {
    try control.authorizeAudio(components)
    let descriptor = try CatalogSafeFiles.descriptor(
      root: root, components: components, directory: false)
    defer { close(descriptor) }
    var initial = stat()
    guard fstat(descriptor, &initial) == 0 else { throw CatalogIssue.unavailable }
    guard initial.st_size > 0, initial.st_size <= maximumBytes else {
      throw CatalogIssue.invalidAudio
    }
    let decodeStart = DispatchTime.now().uptimeNanoseconds
    let duration = try decodeDescriptor(
      descriptor, size: initial.st_size, maximumDuration: maximumDuration, control: control)
    control.metrics?.record(
      .audioDecodeNanoseconds, DispatchTime.now().uptimeNanoseconds - decodeStart)
    let hashStart = DispatchTime.now().uptimeNanoseconds
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    try handle.seek(toOffset: 0)
    var hash = SHA256()
    var count: Int64 = 0
    while let part = try handle.read(upToCount: 65_536), !part.isEmpty {
      try control.check()
      count += Int64(part.count)
      control.metrics?.record(.audioHashBytes, UInt64(part.count))
      guard count <= maximumBytes else { throw CatalogIssue.invalidAudio }
      hash.update(data: part)
    }
    var final = stat()
    let current = try CatalogSafeFiles.descriptor(
      root: root, components: components, directory: false)
    defer { close(current) }
    var path = stat()
    guard fstat(descriptor, &final) == 0, fstat(current, &path) == 0,
      DiaryFileIdentity.sameVersion(initial, final), DiaryFileIdentity.sameVersion(final, path),
      count == initial.st_size
    else { throw CatalogIssue.changed }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    control.metrics?.record(
      .audioHashNanoseconds, DispatchTime.now().uptimeNanoseconds - hashStart)
    return CatalogAudioInspection(
      version: DiaryFileIdentity.versionIdentity(final) + ":" + digest, duration: duration)
  }

  private static func decodeDescriptor(
    _ descriptor: Int32, size: Int64, maximumDuration: Double, control: CatalogReadControl
  ) throws -> Double {
    let input = CatalogAudioInput(descriptor: descriptor, size: size, control: control)
    defer { withExtendedLifetime(input) {} }
    let pointer = Unmanaged.passUnretained(input).toOpaque()
    var file: AudioFileID?
    let opened = AudioFileOpenWithCallbacks(
      pointer,
      { context, position, count, buffer, actual in
        let input = Unmanaged<CatalogAudioInput>.fromOpaque(context).takeUnretainedValue()
        guard (try? input.control.check()) != nil, position >= 0, position <= input.size else {
          actual.pointee = 0
          return kAudioFileUnspecifiedError
        }
        let bounded = min(Int64(count), input.size - position)
        let read = pread(input.descriptor, buffer, Int(bounded), off_t(position))
        guard read >= 0 else {
          actual.pointee = 0
          return kAudioFileUnspecifiedError
        }
        actual.pointee = UInt32(read)
        input.control.metrics?.record(.audioDecodeBytes, UInt64(read))
        return noErr
      }, nil,
      { context in Unmanaged<CatalogAudioInput>.fromOpaque(context).takeUnretainedValue().size },
      nil, 0, &file)
    guard opened == noErr, let file else { throw CatalogIssue.invalidAudio }
    defer { AudioFileClose(file) }
    return try decode(file, maximumDuration: maximumDuration, control: control)
  }

  private static func decode(
    _ file: AudioFileID, maximumDuration: Double, control: CatalogReadControl
  ) throws -> Double {
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var container: AudioFileTypeID = 0
    var containerSize = UInt32(MemoryLayout<AudioFileTypeID>.size)
    guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format) == noErr,
      AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &containerSize, &container) == noErr,
      container == kAudioFileM4AType || container == kAudioFileMPEG4Type,
      format.mFormatID == kAudioFormatMPEG4AAC,
      format.mSampleRate.isFinite, format.mSampleRate > 0, format.mChannelsPerFrame > 0
    else { throw CatalogIssue.invalidAudio }
    var wrapped: ExtAudioFileRef?
    guard ExtAudioFileWrapAudioFileID(file, false, &wrapped) == noErr, let wrapped else {
      throw CatalogIssue.invalidAudio
    }
    defer { ExtAudioFileDispose(wrapped) }
    let declaredFrames = try configure(
      wrapped, sampleRate: format.mSampleRate, maximumDuration: maximumDuration)
    let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 4_096)
    defer { buffer.deallocate() }
    var total: Int64 = 0
    while true {
      try control.check()
      var frames: UInt32 = 4_096
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 16_384, mData: buffer))
      guard ExtAudioFileRead(wrapped, &frames, &list) == noErr else {
        throw CatalogIssue.invalidAudio
      }
      if frames == 0 { break }
      total += Int64(frames)
      guard Double(total) / format.mSampleRate <= maximumDuration else {
        throw CatalogIssue.invalidAudio
      }
    }
    guard total == declaredFrames else { throw CatalogIssue.invalidAudio }
    return Double(total) / format.mSampleRate
  }
  private static func configure(
    _ wrapped: ExtAudioFileRef, sampleRate: Double, maximumDuration: Double
  ) throws -> Int64 {
    var client = AudioStreamBasicDescription(
      mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: 4,
      mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1,
      mBitsPerChannel: 32, mReserved: 0)
    guard
      ExtAudioFileSetProperty(
        wrapped, kExtAudioFileProperty_ClientDataFormat,
        UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client) == noErr
    else { throw CatalogIssue.invalidAudio }
    var declaredFrames: Int64 = 0
    var frameSize = UInt32(MemoryLayout<Int64>.size)
    guard
      ExtAudioFileGetProperty(
        wrapped, kExtAudioFileProperty_FileLengthFrames, &frameSize, &declaredFrames) == noErr,
      declaredFrames > 0, Double(declaredFrames) / sampleRate <= maximumDuration
    else { throw CatalogIssue.invalidAudio }
    return declaredFrames
  }

}
