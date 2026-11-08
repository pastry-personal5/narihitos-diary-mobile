// swiftlint:disable trailing_comma
import CryptoKit
import Foundation
import SQLite3

extension SQLiteCatalogIndex {
  static func decodeCandidate(_ text: String) throws -> CatalogCandidate {
    do {
      let candidate = try JSONDecoder().decode(CatalogCandidate.self, from: Data(text.utf8))
      try validate(candidate)
      return candidate
    } catch { throw CatalogIndexFailure.corrupt }
  }
  static func validateRead(_ read: CatalogReadValue, candidate: CatalogCandidate) throws {
    guard candidate.safe, let title = read.title, title.utf8.count <= 4_096,
      let date = read.createdAt, date.timeIntervalSinceReferenceDate.isFinite,
      read.assetID?.utf8.count ?? 0 <= 256, read.version.utf8.count <= 4_096
    else { throw CatalogIndexFailure.unsafe }
  }

  static let schema = [
    """
    CREATE TABLE IF NOT EXISTS metadata(
      id INTEGER PRIMARY KEY CHECK(id=1),scope TEXT NOT NULL,epoch TEXT NOT NULL,
      validator_revision INTEGER NOT NULL,ordering_revision INTEGER NOT NULL,
      invalidation_revision INTEGER NOT NULL DEFAULT 0)
    """,
    """
    CREATE TABLE IF NOT EXISTS resources(
      row_id TEXT PRIMARY KEY NOT NULL,locator_key TEXT UNIQUE NOT NULL,candidate TEXT NOT NULL,
      claimed_id TEXT COLLATE SWIFT_STRING,sort_id TEXT COLLATE SWIFT_STRING,
      resource_order TEXT COLLATE SWIFT_STRING,created_at REAL,title TEXT,favorite INTEGER,
      file_version TEXT,issue TEXT,validator_revision INTEGER,resource_revision INTEGER NOT NULL,
      seen_epoch TEXT)
    """,
    """
    CREATE INDEX IF NOT EXISTS timeline ON resources(
      created_at DESC,sort_id COLLATE SWIFT_STRING,resource_order COLLATE SWIFT_STRING)
      WHERE title IS NOT NULL
    """,
    "CREATE INDEX IF NOT EXISTS identity_claims ON resources(claimed_id COLLATE SWIFT_STRING)",
    "CREATE INDEX IF NOT EXISTS scan_presence ON resources(seen_epoch)",
    """
    CREATE TABLE IF NOT EXISTS coverage(
      range_key TEXT PRIMARY KEY NOT NULL,epoch TEXT NOT NULL,dirty_revision INTEGER NOT NULL,
      complete INTEGER NOT NULL CHECK(complete IN(0,1)))
    """,
  ]

  static func pageSQL(predicate: String) -> String {
    """
    SELECT r.row_id,r.candidate,r.claimed_id,r.resource_order,r.created_at,r.title,r.favorite
    FROM resources r INDEXED BY timeline
    WHERE r.title IS NOT NULL AND (r.issue IS NULL OR r.issue IN ('unavailable','changed'))
      AND r.validator_revision=?
      AND (r.claimed_id IS NULL OR NOT EXISTS(
        SELECT 1 FROM resources other INDEXED BY identity_claims
        WHERE other.claimed_id = r.claimed_id COLLATE SWIFT_STRING AND other.row_id != r.row_id))
      \(predicate)
    ORDER BY r.created_at DESC,r.sort_id COLLATE SWIFT_STRING,r.resource_order COLLATE SWIFT_STRING
    LIMIT 11
    """
  }

  static func row(_ statement: OpaquePointer) throws -> CatalogRememberedRow {
    guard let id = UUID(uuidString: try CatalogSQLiteDatabase.text(statement, 0)) else {
      throw CatalogIndexFailure.corrupt
    }
    let encoded = try CatalogSQLiteDatabase.text(statement, 1)
    let candidate = try decodeCandidate(encoded)
    let assetID = try CatalogSQLiteDatabase.optionalText(statement, 2)
    let resourceOrder = try CatalogSQLiteDatabase.text(statement, 3)
    let date = sqlite3_column_double(statement, 4)
    let title = try CatalogSQLiteDatabase.text(statement, 5)
    let favorite: Bool?
    if sqlite3_column_type(statement, 6) == SQLITE_NULL {
      favorite = nil
    } else {
      let value = sqlite3_column_int(statement, 6)
      guard sqlite3_column_type(statement, 6) == SQLITE_INTEGER, value == 0 || value == 1 else {
        throw CatalogIndexFailure.corrupt
      }
      favorite = value == 1
    }
    guard candidate.safe, date.isFinite, sqlite3_column_type(statement, 4) == SQLITE_FLOAT,
      title.utf8.count <= 4_096, assetID?.utf8.count ?? 0 <= 256,
      resourceOrder == Self.resourceOrder(candidate)
    else { throw CatalogIndexFailure.corrupt }
    return CatalogRememberedRow(
      id: CatalogRowID(id), kind: candidate.handler, assetID: assetID,
      resourceOrder: resourceOrder, createdAt: Date(timeIntervalSinceReferenceDate: date),
      title: title, favorite: favorite)
  }

  static func validate(_ candidate: CatalogCandidate) throws {
    guard (1...16).contains(candidate.components.count), candidate.handler.utf8.count <= 128,
      !candidate.handler.isEmpty, candidate.stableID.utf8.count <= 256,
      candidate.components.allSatisfy({
        !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255
          && !$0.contains("/") && !$0.contains("\\") && !$0.contains("\0")
      })
    else { throw CatalogIndexFailure.unsafe }
  }

  static func key(_ candidate: CatalogCandidate) -> String {
    digest(candidate.key.precomposedStringWithCanonicalMapping)
  }

  static func resourceOrder(_ candidate: CatalogCandidate) -> String { digest(candidate.key) }

  static func utf8(_ bytes: Data) throws -> String {
    guard let text = String(data: bytes, encoding: .utf8), text.utf8.count <= 16_384 else {
      throw CatalogIndexFailure.unsafe
    }
    return text
  }

  private static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

// swiftlint:enable trailing_comma
