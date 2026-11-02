import Foundation

enum BoundedCoordinationFailure: Error, Equatable {
  case timedOut
  case cancelled
  case provider
}

/// Cancellation never acknowledges a still-running accessor. The coordinator
/// callback is the settlement point for a per-job mutation barrier.
private final class CoordinationTicket: @unchecked Sendable {
  private let lock = NSLock()
  private let coordinator: NSFileCoordinator
  private var settled = false
  private var timedOut = false
  private var cancelled = false

  init(_ coordinator: NSFileCoordinator) { self.coordinator = coordinator }

  func timeout() {
    lock.lock()
    guard !settled else {
      lock.unlock()
      return
    }
    timedOut = true
    lock.unlock()
    coordinator.cancel()
  }

  func cancel() {
    lock.lock()
    let shouldCancel = !settled
    cancelled = true
    lock.unlock()
    if shouldCancel { coordinator.cancel() }
  }

  func mayAccess() -> Bool {
    lock.lock()
    let allowed = !timedOut && !cancelled
    lock.unlock()
    return allowed
  }

  func finish() -> (timedOut: Bool, cancelled: Bool) {
    lock.lock()
    settled = true
    let result = (timedOut, cancelled)
    lock.unlock()
    return result
  }
}

struct BoundedFileCoordinator {
  func perform<Value: Sendable>(
    intents: [NSFileAccessIntent], timeout: Duration,
    accessor: @escaping @Sendable ([URL]) throws -> Value
  ) async throws -> Value {
    let coordinator = NSFileCoordinator()
    let ticket = CoordinationTicket(coordinator)
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let timer = Task.detached {
          try? await Task.sleep(for: timeout)
          guard !Task.isCancelled else { return }
          ticket.timeout()
        }
        coordinator.coordinate(with: intents, queue: queue) { error in
          let result: Result<Value, Error>
          if !ticket.mayAccess() {
            result = .failure(BoundedCoordinationFailure.cancelled)
          } else if let error {
            result = .failure(error)
          } else {
            result = Result { try accessor(intents.map(\.url)) }
          }
          timer.cancel()
          let status = ticket.finish()
          if status.timedOut {
            continuation.resume(throwing: BoundedCoordinationFailure.timedOut)
          } else if status.cancelled {
            continuation.resume(throwing: BoundedCoordinationFailure.cancelled)
          } else {
            continuation.resume(with: result)
          }
        }
      }
    } onCancel: {
      ticket.cancel()
    }
  }
}
