import Foundation

/// Only the private candidate store persists the text returned by an adapter.
struct TranscriptionPayload: Codable, Equatable, Sendable {
  let text: String
  let sourceDigest: String
  let resolvedLocale: String
  let runtime: String
  let conversion: String
  let operatingSystemVersion: String
}

enum CandidateInspection: Equatable {
  case verified
  case missing
  case invalid
  case protectedDataUnavailable
}

enum TranscriptionCandidateFailure: Error, Equatable {
  case protectedDataUnavailable
  case invalidSource
}

@MainActor
protocol TranscriptionCandidateStore: AnyObject {
  /// Publishes and reopens a candidate bound to this exact durable claim and source.
  func publish(_ payload: TranscriptionPayload, request: TranscriptionRequest, job: QueueJob) throws
  func inspect(job: QueueJob) throws -> CandidateInspection
  func readVerified(job: QueueJob) throws -> TranscriptionPayload
  func discard(job: QueueJob) throws
}

/// Until a protected store is installed, production must fail closed rather than lose text.
@MainActor
final class UnavailableTranscriptionCandidateStore: TranscriptionCandidateStore {
  func publish(
    _: TranscriptionPayload, request _: TranscriptionRequest, job _: QueueJob
  ) throws { throw QueueStoreFailure.unavailable }

  func inspect(job _: QueueJob) throws -> CandidateInspection { .missing }
  func readVerified(job _: QueueJob) throws -> TranscriptionPayload {
    throw QueueStoreFailure.unavailable
  }
  func discard(job _: QueueJob) throws {}
}
