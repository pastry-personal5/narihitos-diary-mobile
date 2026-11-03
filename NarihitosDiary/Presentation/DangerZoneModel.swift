import Combine
import Foundation

@MainActor
final class DangerZoneModel: ObservableObject {
  struct Confirmation: Equatable {
    let id = UUID()
    let transaction: PurgeTransaction
  }

  @Published private(set) var confirmation: Confirmation?
  @Published private(set) var isRunning = false
  @Published private(set) var removedCount = 0
  @Published private(set) var message: String?
  @Published private(set) var recovery: PurgeTransaction?
  @Published private(set) var blocksWork = false
  private var port: (any PurgePort)?
  private var generation = UUID()
  var acquireMaintenance: () -> Bool = { false }
  var releaseMaintenance: () -> Void = {}

  func configure(_ port: any PurgePort) {
    self.port = port
    reloadBarrier()
  }

  func reloadBarrier() {
    guard let port, !isRunning else { return }
    do {
      recovery = try port.pendingTransaction()
      blocksWork = recovery != nil
      if recovery != nil {
        message = "A purge was interrupted. Processing is paused. Confirm the same purge to retry."
      }
    } catch {
      blocksWork = true
      message = "Purge recovery data is unavailable. Processing is paused until it can be read."
    }
  }

  func request(_ scope: PurgeScope) async {
    guard !isRunning, confirmation == nil, let port else { return }
    let token = UUID()
    generation = token
    message = nil
    do {
      let transaction = try await port.prepare(scope)
      guard generation == token, !isRunning else { return }
      if blocksWork, recovery != transaction {
        message = "Complete the interrupted purge before starting another."
        return
      }
      confirmation = Confirmation(transaction: transaction)
    } catch {
      guard generation == token else { return }
      message = Self.failureMessage(error)
    }
  }

  func disarm() {
    generation = UUID()
    confirmation = nil
  }

  func confirm(_ id: UUID) async {
    guard let confirmation, confirmation.id == id, !isRunning, let port else { return }
    let transaction = confirmation.transaction
    disarm()
    guard acquireMaintenance() else {
      message =
        "Work is still running. Wait for recording, transcription, or saving to stop, then retry."
      return
    }
    isRunning = true
    blocksWork = true
    removedCount = 0
    let attempt = UUID()
    generation = attempt
    defer { isRunning = false }
    do {
      // Recheck after confirmation and maintenance admission, before durable intent.
      guard try await port.prepare(transaction.scope) == transaction else {
        throw PurgeFailure.changedDestination
      }
      try port.begin(transaction)
      recovery = transaction
      try await port.perform(transaction) { [weak self] count in
        Task { @MainActor in
          guard let self, self.isRunning, self.generation == attempt else { return }
          self.removedCount = count
        }
      }
      try port.finish()
      recovery = nil
      blocksWork = false
      message = "Purge complete."
      releaseMaintenance()
    } catch {
      message = "Purge did not complete. " + Self.failureMessage(error)
      // An unsuccessful journal write must not clear an existing barrier.
      reloadAfterFailure(port)
    }
  }

  private func reloadAfterFailure(_ port: any PurgePort) {
    do {
      recovery = try port.pendingTransaction()
      blocksWork = recovery != nil
      if !blocksWork { releaseMaintenance() }
    } catch {
      blocksWork = true
    }
    if blocksWork {
      message = (message ?? "") + " Processing is paused. Confirm this purge to retry."
    }
  }

  private static func failureMessage(_ error: Error) -> String {
    switch error as? PurgeFailure {
    case .pendingWork:
      "Pending staging must finish or be purged separately before purging the active folder."
    case .changedDestination:
      "The active folder changed. Open Danger Zone again to confirm the current folder."
    case .unsafeResource:
      "Safe file access could not be verified. Some contents may remain."
    default:
      "Storage or iCloud access is unavailable. Some contents may remain. Retry when access returns."
    }
  }
}
