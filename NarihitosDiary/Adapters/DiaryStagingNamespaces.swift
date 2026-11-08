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
          entry.name == "DiaryEdits" || entry.name == "DiaryReplay" || entry.name == "ManualDiaries"
        else { return false }
        let descriptor = try CatalogSafeFiles.descriptor(
          root: root, components: [entry.name], directory: true)
        close(descriptor)
        let namespace = root.appending(path: entry.name)
        if entry.name == "ManualDiaries" {
          guard try !ManualDiaryJournal.hasPending(in: namespace) else { return false }
        } else {
          guard try PurgeFileTree.isEmpty(namespace) else { return false }
        }
      }
      if slice.ended { return true }
    } while true
  }
}
