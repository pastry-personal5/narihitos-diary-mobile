import Foundation

@MainActor
private final class CatalogPurgeMaintenance {
  weak var catalog: AppleIndexedAssetCatalog?
  func settle() async { await catalog?.discardForPurge() }
}

@MainActor
enum CatalogProductionComposition {
  static func make(
    destination: AppleDestinationService, installation: any InstallationIdentityPort,
    support: URL? = nil
  ) -> (catalog: AppleIndexedAssetCatalog, purge: ApplePurgeService) {
    let root =
      support
      ?? FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "NarihitosDiary")
    let maintenance = CatalogPurgeMaintenance()
    let purge = ApplePurgeService(
      destination: destination, support: root, settleProjection: { await maintenance.settle() })
    var registry = CatalogAssetRegistry()
    registry.register(DiaryCatalogHandler())
    let catalog = AppleIndexedAssetCatalog(
      destination: destination, registry: registry,
      index: SQLiteCatalogIndex(root: root.appending(path: "CatalogProjection")),
      environment: CatalogProjectionEnvironment(
        installation: installation,
        maintenanceBlocked: {
          do { return try purge.pendingTransaction() != nil } catch { return true }
        }, projectionGeneration: { try purge.projectionGeneration() }))
    maintenance.catalog = catalog
    return (catalog, purge)
  }
}
