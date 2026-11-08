// swiftlint:disable trailing_comma
import Foundation

/// Metadata registration stays in its caller's bounded transaction.
struct CatalogSQLiteResourceStore {
  let database: CatalogSQLiteDatabase
  let session: UUID
  let epoch: UUID
  let invalidationRevision: Int64

  func register(_ candidate: CatalogCandidate) throws -> CatalogResourceStamp {
    try SQLiteCatalogIndex.validate(candidate)
    var existing: CatalogResourceStamp?
    var previous: CatalogCandidate?
    try database.query(
      "SELECT row_id,resource_revision,candidate FROM resources WHERE locator_key=?",
      values: [.text(SQLiteCatalogIndex.key(candidate))]
    ) {
      guard let id = UUID(uuidString: try CatalogSQLiteDatabase.text($0, 0)) else {
        throw CatalogIndexFailure.corrupt
      }
      existing = CatalogResourceStamp(
        rowID: CatalogRowID(id), session: session, epoch: epoch,
        revision: try CatalogSQLiteDatabase.revision($0, 1),
        invalidationRevision: invalidationRevision)
      let text = try CatalogSQLiteDatabase.text($0, 2)
      previous = try SQLiteCatalogIndex.decodeCandidate(text)
    }
    if let existing {
      return previous == candidate ? existing : try refresh(candidate, stamp: existing)
    }
    let id = CatalogRowID()
    let locator = try SQLiteCatalogIndex.utf8(JSONEncoder().encode(candidate))
    try database.execute(
      """
      INSERT INTO resources(row_id,locator_key,candidate,claimed_id,resource_revision)
      VALUES(?,?,?,?,0)
      """,
      values: [
        .text(id.rawValue.uuidString), .text(SQLiteCatalogIndex.key(candidate)), .text(locator),
        candidate.stableID.isEmpty ? .null : .text(candidate.stableID),
      ])
    try database.execute("UPDATE metadata SET ordering_revision=ordering_revision+1")
    return CatalogResourceStamp(
      rowID: id, session: session, epoch: epoch, revision: 0,
      invalidationRevision: invalidationRevision)
  }

  private func refresh(
    _ candidate: CatalogCandidate, stamp: CatalogResourceStamp
  ) throws -> CatalogResourceStamp {
    let locator = try SQLiteCatalogIndex.utf8(JSONEncoder().encode(candidate))
    let order = SQLiteCatalogIndex.resourceOrder(candidate)
    try database.execute(
      """
      UPDATE resources SET candidate=?,resource_order=?,sort_id=COALESCE(claimed_id,?),
        title=CASE WHEN ?=1 THEN title ELSE NULL END,issue=?,resource_revision=resource_revision+1
      WHERE row_id=? AND resource_revision=?
      """,
      values: [
        .text(locator), .text(order), .text(order), .integer(candidate.safe ? 1 : 0),
        .text(candidate.safe ? CatalogIssue.changed.rawValue : CatalogIssue.unsafe.rawValue),
        .text(stamp.rowID.rawValue.uuidString), .integer(stamp.revision),
      ])
    try database.execute("UPDATE metadata SET ordering_revision=ordering_revision+1")
    return CatalogResourceStamp(
      rowID: stamp.rowID, session: session, epoch: epoch, revision: stamp.revision + 1,
      invalidationRevision: invalidationRevision)
  }
}

// swiftlint:enable trailing_comma
