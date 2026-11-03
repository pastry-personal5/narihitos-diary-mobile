import Darwin
import Foundation

/// Namespace roots may persist without pending work. Any transaction, cache,
/// unknown entry, or unsafe namespace still blocks active-folder purge.
enum DiaryStagingNamespaces {
  static func isEmpty(_ root: URL) throws -> Bool {
    let cursor = try CatalogDirectoryCursor(root: root, components: [])
    repeat {
      let slice = try cursor.next(root: root, components: [], maximum: 50)
      for entry in slice.entries {
        guard entry.safe, entry.isDirectory,
          entry.name == "DiaryEdits" || entry.name == "DiaryReplay"
        else { return false }
        let descriptor = try CatalogSafeFiles.descriptor(
          root: root, components: [entry.name], directory: true)
        close(descriptor)
        guard try PurgeFileTree.isEmpty(root.appending(path: entry.name)) else { return false }
      }
      if slice.ended { return true }
    } while true
  }
}
