import Foundation

extension AppleIndexedAssetCatalog {
  /// Clearing the session drops metadata/summary memory after actual access settlement.
  func releaseMemory() async {
    end()
    let generation = epoch
    await settled()
    guard generation == epoch else { return }
    onEvent?(.invalidated)
  }

  /// Internal repair only; failure preserves the authoritative strict-file route.
  func resetProjection() async {
    end()
    let generation = epoch
    await settled()
    guard generation == epoch else { return }
    do { try await index.discard() } catch { projectionDisabled = true }
    guard generation == epoch else { return }
    onEvent?(.invalidated)
  }
}
