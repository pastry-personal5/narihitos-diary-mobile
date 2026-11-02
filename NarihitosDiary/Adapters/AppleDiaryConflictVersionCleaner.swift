import Foundation

struct DiaryObsoleteFileVersion: Equatable, Sendable {
  let providerKey: String
  let digest: String
  let byteCount: Int64
}

@MainActor
protocol DiaryConflictVersionCleanerPort: AnyObject {
  func removeObsolete(
    at url: URL, current: DiaryFileVersion,
    knownVersions: [DiaryObsoleteFileVersion]
  ) async -> DiaryConflictCleanupResult
}

/// Removes only named provider versions after the selected canonical file and
/// its upload have already been proved. Unknown conflicts block cleanup.
@MainActor
final class AppleDiaryConflictVersionCleaner: DiaryConflictVersionCleanerPort {
  // swiftlint:disable:next cyclomatic_complexity
  func removeObsolete(
    at url: URL, current: DiaryFileVersion,
    knownVersions: [DiaryObsoleteFileVersion]
  ) async -> DiaryConflictCleanupResult {
    guard !knownVersions.isEmpty,
      Set(knownVersions.map(\.providerKey)).count == knownVersions.count
    else { return .recoveryRequired }
    let expected = Dictionary(uniqueKeysWithValues: knownVersions.map { ($0.providerKey, $0) })
    let intent = NSFileAccessIntent.writingIntent(with: url, options: [])
    do {
      let settled = try await BoundedFileCoordinator().perform(
        intents: [intent], timeout: .seconds(15)
      ) { urls in
        guard urls.first?.standardizedFileURL == url.standardizedFileURL,
          try AppleDiaryConflictPairStore.fingerprint(
            url, maximumBytes: current.byteCount) == current
        else { throw DiaryFileObservationFailure.changed }
        guard let providerCurrent = NSFileVersion.currentVersionOfItem(at: url),
          let currentKey = AppleDiaryExternalVersionSource.key(for: providerCurrent)
        else { throw DiaryFileObservationFailure.unavailable }
        let unresolved = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        let others = NSFileVersion.otherVersionsOfItem(at: url) ?? []
        for version in unresolved {
          guard let key = AppleDiaryExternalVersionSource.key(for: version),
            key == currentKey || expected[key] != nil
          else { throw DiaryFileObservationFailure.changed }
        }
        for version in others {
          guard let key = AppleDiaryExternalVersionSource.key(for: version) else {
            throw DiaryFileObservationFailure.changed
          }
          guard key != currentKey else { continue }
          guard let known = expected[key] else {
            throw DiaryFileObservationFailure.changed
          }
          let observed = try AppleDiaryConflictPairStore.fingerprint(
            version.url, maximumBytes: known.byteCount)
          guard observed.digest == known.digest,
            observed.byteCount == known.byteCount
          else { throw DiaryFileObservationFailure.changed }
          try version.remove()
        }
        let remaining = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        return remaining.isEmpty
      }
      return settled ? .done : .waiting
    } catch DiaryFileObservationFailure.changed {
      return .recoveryRequired
    } catch DiaryFileObservationFailure.unsafeResource {
      return .recoveryRequired
    } catch { return .waiting }
  }
}
