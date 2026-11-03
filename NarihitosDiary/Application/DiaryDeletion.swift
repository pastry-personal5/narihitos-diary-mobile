import Foundation

enum DiaryDeletionIssue: Error, Equatable {
  case busy
  case changed
  case unavailable
  case unsafe
  case incomplete

  var message: String {
    switch self {
    case .busy:
      "Finish pending saves and edits before deleting this Diary Snippet."
    case .changed:
      "This diary changed. Reopen its current version before deleting."
    case .unavailable:
      "The diary couldn’t be deleted. Check iCloud access and try again."
    case .unsafe:
      "This diary can’t be deleted safely. Review it in All."
    case .incomplete:
      "Deletion couldn’t finish. Review the remaining files in All → Incomplete Diary Snippets."
    }
  }
}

@MainActor
protocol DiaryDeletionPort: AnyObject {
  /// Returns only after coordinated mutation has relinquished all resources.
  func delete(_ handle: CatalogItemHandle) async throws
}
