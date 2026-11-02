import Foundation
import Testing

@testable import NarihitosDiary

struct BoundedFileCoordinatorTests {
  @Test func localReadRunsOffMainAndReturnsExactData() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("diary".utf8).write(to: url)
    let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
    let result = try await BoundedFileCoordinator().perform(
      intents: [intent], timeout: .seconds(5)
    ) { urls in
      let data = try Data(contentsOf: urls[0])
      return (data, Thread.isMainThread)
    }
    #expect(result.0 == Data("diary".utf8))
    #expect(result.1 == false)
  }

  @Test func timeoutWaitsForAccessorToRelinquish() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("diary".utf8).write(to: url)
    let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
    let start = ContinuousClock.now
    do {
      _ = try await BoundedFileCoordinator().perform(
        intents: [intent], timeout: .milliseconds(100)
      ) { _ in
        Thread.sleep(forTimeInterval: 0.25)
        return true
      }
      Issue.record("Expected bounded timeout")
    } catch BoundedCoordinationFailure.timedOut {
      #expect(start.duration(to: .now) >= .milliseconds(250))
    }
  }

  @Test func cancellationWaitsForAccessorToRelinquish() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("diary".utf8).write(to: url)
    let entered = DispatchSemaphore(value: 0)
    let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
    let task = Task {
      try await BoundedFileCoordinator().perform(
        intents: [intent], timeout: .seconds(5)
      ) { _ in
        entered.signal()
        Thread.sleep(forTimeInterval: 0.25)
        return true
      }
    }
    let didEnter = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: entered.wait(timeout: .now() + 5) == .success)
      }
    }
    #expect(didEnter)
    let start = ContinuousClock.now
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch BoundedCoordinationFailure.cancelled {
      #expect(start.duration(to: .now) >= .milliseconds(100))
    }
  }
}
