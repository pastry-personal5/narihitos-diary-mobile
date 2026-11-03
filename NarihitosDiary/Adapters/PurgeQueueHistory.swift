import Foundation

/// Completed queue receipts are inert history, retained after private cleanup.
/// Unlike ordinary queue inventory, this admission check never skips an unknown
/// or malformed entry. It reads bounded, stable, nonlinked files off the main actor.
enum PurgeQueueHistory {
  static func isComplete(_ root: URL, maximumRecordBytes: Int) throws -> Bool {
    let cursor = try CatalogDirectoryCursor(root: root, components: [])
    while true {
      let slice = try cursor.next(root: root, components: [], maximum: 64)
      for entry in slice.entries {
        guard entry.safe, !entry.isDirectory, entry.name.hasSuffix(".json") else { return false }
        let (data, _) = try CatalogSafeFiles.read(
          root: root, components: [entry.name], maximum: maximumRecordBytes)
        let job = try JSONDecoder().decode(QueueJob.self, from: data)
        guard entry.name == "\(job.id).json", (try? WorkspaceID(job.id)) != nil,
          job.schema == QueueJob.schemaVersion, job.state == .saved,
          job.commitCleanupDone == true, job.commitNoticeDelivered == true,
          let commit = job.commit, commit.schema == 1,
          commit.jobID == job.id, commit.attemptID == job.attemptID,
          commit.generation == job.attemptGeneration,
          commit.installationBinding == job.installationBinding,
          commit.destinationReference == job.destinationReference,
          commit.destinationRevision == job.destinationRevision,
          commit.bodyRevision == job.bodyRevision, commit.assetID == job.draftAssetID,
          (try? AssetID(commit.assetID)) != nil,
          commit.audioVersion?.digest == commit.audioDigest,
          commit.audioVersion?.byteCount == commit.audioByteCount,
          commit.markdownVersion?.digest == commit.markdownDigest,
          commit.markdownVersion?.byteCount == commit.markdownByteCount
        else { return false }
      }
      if slice.ended { return true }
    }
  }
}
