// swiftlint:disable trailing_comma
import Foundation
import SQLite3

struct CatalogIndexScanStamp: Equatable, Sendable {
  let id: UUID
  let session: UUID
  let epoch: UUID
  let invalidationRevision: Int64
}

struct CatalogIndexedResource: Sendable {
  let stamp: CatalogResourceStamp
  let candidate: CatalogCandidate
}

/// These synchronous operations run only inside the index actor, without provider access.
struct CatalogSQLiteScanStore {
  let database: CatalogSQLiteDatabase
  let session: UUID
  let epoch: UUID

  func begin() throws -> CatalogIndexScanStamp {
    try database.transaction {
      try database.execute("UPDATE metadata SET invalidation_revision=invalidation_revision+1")
      let scan = CatalogIndexScanStamp(
        id: UUID(), session: session, epoch: epoch,
        invalidationRevision: try Self.invalidationRevision(database))
      try database.execute(
        "INSERT OR REPLACE INTO coverage(range_key,epoch,dirty_revision,complete) VALUES('all',?,?,0)",
        values: [.text(scan.id.uuidString), .integer(scan.invalidationRevision)])
      return scan
    }
  }

  func markSeen(_ rows: [CatalogRowID], scan: CatalogIndexScanStamp) throws -> Bool {
    guard rows.count <= 50 else { throw CatalogIndexFailure.unsafe }
    return try database.transaction {
      guard try matches(scan) else { return false }
      for row in rows {
        try database.execute(
          "UPDATE resources SET seen_epoch=? WHERE row_id=?",
          values: [.text(scan.id.uuidString), .text(row.rawValue.uuidString)])
      }
      return true
    }
  }

  func unseen(scan: CatalogIndexScanStamp) throws -> [CatalogIndexedResource] {
    guard try matches(scan) else { throw CatalogIndexFailure.changed }
    var result: [CatalogIndexedResource] = []
    // Three disjoint indexed ranges avoid an offset or repeated full scan of already-seen rows.
    for predicate in ["seen_epoch IS NULL", "seen_epoch < ?", "seen_epoch > ?"] {
      let values: [CatalogSQLValue] = predicate.contains("?") ? [.text(scan.id.uuidString)] : []
      let remaining = 50 - result.count
      guard remaining > 0 else { break }
      try database.query(
        """
        SELECT row_id,candidate,resource_revision FROM resources INDEXED BY scan_presence
        WHERE \(predicate) LIMIT \(remaining)
        """, values: values
      ) { statement in
        guard let id = UUID(uuidString: try CatalogSQLiteDatabase.text(statement, 0)) else {
          throw CatalogIndexFailure.corrupt
        }
        let encoded = try CatalogSQLiteDatabase.text(statement, 1)
        let candidate = try SQLiteCatalogIndex.decodeCandidate(encoded)
        result.append(
          CatalogIndexedResource(
            stamp: CatalogResourceStamp(
              rowID: CatalogRowID(id), session: session, epoch: epoch,
              revision: try CatalogSQLiteDatabase.revision(statement, 2),
              invalidationRevision: scan.invalidationRevision), candidate: candidate))
      }
    }
    return result
  }

  func retire(_ rows: [CatalogResourceStamp], scan: CatalogIndexScanStamp) throws -> Bool {
    guard rows.count <= 50 else { throw CatalogIndexFailure.unsafe }
    return try database.transaction {
      guard try matches(scan) else { return false }
      guard
        rows.allSatisfy({
          $0.epoch == epoch && $0.session == session
            && $0.invalidationRevision == scan.invalidationRevision
        })
      else { return false }
      for row in rows {
        try database.execute(
          """
          DELETE FROM resources WHERE row_id=? AND resource_revision=?
            AND (seen_epoch IS NULL OR seen_epoch != ?)
          """,
          values: [
            .text(row.rowID.rawValue.uuidString), .integer(row.revision), .text(scan.id.uuidString),
          ])
      }
      if !rows.isEmpty {
        try database.execute("UPDATE metadata SET ordering_revision=ordering_revision+1")
      }
      return true
    }
  }

  func finish(_ scan: CatalogIndexScanStamp) throws -> Bool {
    try database.transaction {
      guard try matches(scan), try unseen(scan: scan).isEmpty else { return false }
      try database.execute("UPDATE coverage SET complete=1 WHERE range_key='all'")
      return true
    }
  }

  private func matches(_ scan: CatalogIndexScanStamp) throws -> Bool {
    guard scan.session == session, scan.epoch == epoch,
      scan.invalidationRevision == (try Self.invalidationRevision(database))
    else { return false }
    var valid = false
    try database.query("SELECT epoch,dirty_revision FROM coverage WHERE range_key='all'") {
      valid =
        try CatalogSQLiteDatabase.text($0, 0) == scan.id.uuidString
        && CatalogSQLiteDatabase.revision($0, 1) == scan.invalidationRevision
    }
    return valid
  }

  static func invalidationRevision(_ database: CatalogSQLiteDatabase) throws -> Int64 {
    var revision: Int64?
    try database.query("SELECT invalidation_revision FROM metadata WHERE id=1") {
      revision = try CatalogSQLiteDatabase.revision($0, 0)
    }
    guard let revision else { throw CatalogIndexFailure.corrupt }
    return revision
  }
}

// swiftlint:enable trailing_comma
