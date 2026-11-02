import Foundation

@MainActor
final class CaptureCommitCleanup: DiaryCommitCleanupPort {
  private let files: CapturePrivateFiles
  private let snapshots: FileDiaryConflictSnapshotStore?

  init(
    files: CapturePrivateFiles,
    snapshots: FileDiaryConflictSnapshotStore? = nil
  ) {
    self.files = files
    self.snapshots = snapshots
  }

  func removeOwnedStaging(job: QueueJob) throws {
    guard job.state == .saved, job.commit?.jobID == job.id,
      job.commit?.destinationReference == job.destinationReference,
      job.commit?.assetID == job.draftAssetID
    else { throw QueueStoreFailure.corrupt }
    if let resolution = job.conflictResolution {
      guard resolution.matches(job: job), resolution.pairVerified == true,
        resolution.providerCleanupDone == true,
        resolution.removalConfirmed == true,
        let snapshots,
        let first = try? WorkspaceID(resolution.firstSnapshotID),
        let second = try? WorkspaceID(resolution.secondSnapshotID)
      else { throw QueueStoreFailure.corrupt }
      try snapshots.removeVerifiedIfPresent(
        id: first, assetID: resolution.assetID, version: resolution.firstVersion)
      try snapshots.removeVerifiedIfPresent(
        id: second, assetID: resolution.assetID, version: resolution.secondVersion)
    }
    try files.removeWorkspace(jobID: job.id)
    try files.removeUnreferencedSnapshot(job.destinationReference)
  }
}
