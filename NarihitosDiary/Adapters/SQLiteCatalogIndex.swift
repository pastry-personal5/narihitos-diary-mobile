// swiftlint:disable trailing_comma
import CryptoKit
import Foundation
import SQLite3

struct CatalogResourceStamp: Equatable, Sendable {
  let rowID: CatalogRowID
  let session: UUID
  let epoch: UUID
  let revision: Int64
  let invalidationRevision: Int64
}

/// All blocking SQL is synchronous inside this non-main actor; no transaction spans an await.
actor SQLiteCatalogIndex: CatalogIndexPort {
  private let files: CatalogProjectionFiles
  private let protectedDataAvailable: @Sendable () -> Bool
  private let maximumDatabaseBytes: Int64
  private var database: CatalogSQLiteDatabase?
  private var currentScope: CatalogIndexScope?
  private var session = UUID()
  private var epoch = UUID()
  private var resetAvailable = true

  init(
    root: URL, protection: any DraftFileProtectionPolicy = AppleDraftProtectionPolicy(),
    protectedDataAvailable: @escaping @Sendable () -> Bool = { true },
    maximumDatabaseBytes: Int64 = 63 * 1_024 * 1_024
  ) {
    files = CatalogProjectionFiles(root: root, protection: protection)
    self.protectedDataAvailable = protectedDataAvailable
    self.maximumDatabaseBytes = maximumDatabaseBytes
  }

  func page(
    scope: CatalogIndexScope, after cursor: CatalogIndexCursor?
  ) throws -> CatalogIndexPage {
    let database = try open(scope)
    let revision = try orderingRevision(database)
    if let cursor {
      guard cursor.scope == scope, cursor.session == session, cursor.epoch == epoch,
        cursor.orderingRevision == revision
      else { throw CatalogIndexFailure.changed }
    }
    var values: [CatalogSQLValue] = [.integer(Int64(scope.validatorRevision))]
    var predicate = ""
    if let key = cursor?.after {
      predicate = """
        AND (r.created_at < ? OR (r.created_at = ? AND
          (r.sort_id COLLATE SWIFT_STRING > ? OR
           (r.sort_id COLLATE SWIFT_STRING = ? AND r.resource_order COLLATE SWIFT_STRING > ?))))
        """
      values += [
        .real(key.instant.timeIntervalSinceReferenceDate),
        .real(key.instant.timeIntervalSinceReferenceDate), .text(key.sortID), .text(key.sortID),
        .text(key.resourceOrder),
      ]
    }
    var rows: [CatalogRememberedRow] = []
    try database.query(Self.pageSQL(predicate: predicate), values: values) { statement in
      rows.append(try Self.row(statement))
    }
    let more = rows.count > 10
    rows = Array(rows.prefix(10))
    let next =
      more
      ? rows.last.map {
        CatalogIndexCursor(
          scope: scope, session: session, epoch: epoch, orderingRevision: revision,
          after: CatalogTimelineKey(
            instant: $0.createdAt, sortID: $0.assetID ?? $0.resourceOrder,
            resourceOrder: $0.resourceOrder))
      } : nil
    var complete = false
    try database.query("SELECT complete FROM coverage WHERE range_key = 'all'") {
      complete = sqlite3_column_int($0, 0) == 1
    }
    return CatalogIndexPage(rows: rows, continuation: next, enumerationComplete: complete)
  }

  func close() {
    releaseConnection()
    resetAvailable = true
  }

  func suspend() { releaseConnection() }

  private func releaseConnection() {
    database = nil
    currentScope = nil
    session = UUID()
  }

  func discard() throws {
    close()
    try files.discard()
  }

  /// Metadata registration records a claim, never a remembered summary or action capability.
  func bind(
    _ candidate: CatalogCandidate, scope: CatalogIndexScope
  ) throws -> CatalogResourceStamp {
    let result = try bindCandidates([candidate], scope: scope)
    guard let stamp = result.first else { throw CatalogIndexFailure.unavailable }
    return stamp
  }

  func bindCandidates(
    _ candidates: [CatalogCandidate], scope: CatalogIndexScope
  ) throws -> [CatalogResourceStamp] {
    guard candidates.count <= 50 else { throw CatalogIndexFailure.unsafe }
    let database = try open(scope)
    return try database.transaction {
      let dirtyRevision = try CatalogSQLiteScanStore.invalidationRevision(database)
      let resources = CatalogSQLiteResourceStore(
        database: database, session: session, epoch: epoch, invalidationRevision: dirtyRevision)
      return try candidates.map { try resources.register($0) }
    }
  }

  /// A result can commit only while its resource revision and projection epoch still match.
  @discardableResult
  func apply(
    _ read: CatalogReadValue, to stamp: CatalogResourceStamp, scope: CatalogIndexScope
  ) throws -> Bool {
    let database = try open(scope)
    guard stamp.epoch == epoch, stamp.session == session else { return false }
    return try database.transaction {
      guard
        stamp.invalidationRevision == (try CatalogSQLiteScanStore.invalidationRevision(database))
      else {
        return false
      }
      var revision: Int64?
      try database.query(
        "SELECT resource_revision FROM resources WHERE row_id = ?",
        values: [.text(stamp.rowID.rawValue.uuidString)]
      ) { revision = try CatalogSQLiteDatabase.revision($0, 0) }
      guard revision == stamp.revision else { return false }
      if let issue = read.issue, issue.retryable {
        // A failed refresh is not proof that a historical successful summary was invalid.
        try database.execute(
          "UPDATE resources SET issue=?,resource_revision=resource_revision+1 WHERE row_id=?",
          values: [.text(issue.rawValue), .text(stamp.rowID.rawValue.uuidString)])
        try advanceOrdering(database)
        return true
      }
      let candidate = try candidate(for: stamp.rowID, database: database)
      let order = Self.resourceOrder(candidate)
      let valid = read.issue == nil && read.title != nil && read.createdAt != nil
      if valid { try Self.validateRead(read, candidate: candidate) }
      try database.execute(
        """
        UPDATE resources SET claimed_id=?,sort_id=?,resource_order=?,created_at=?,title=?,
          favorite=?,file_version=?,issue=?,validator_revision=?,resource_revision=resource_revision+1
        WHERE row_id=? AND resource_revision=?
        """,
        values: [
          (read.assetID ?? (candidate.stableID.isEmpty ? nil : candidate.stableID)).map(
            CatalogSQLValue.text) ?? .null,
          .text(read.assetID ?? order), .text(order),
          valid
            ? (read.createdAt.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null) : .null,
          valid ? (read.title.map(CatalogSQLValue.text) ?? .null) : .null,
          read.favorite.map { .integer($0 ? 1 : 0) } ?? .null,
          .text(read.version), read.issue.map { .text($0.rawValue) } ?? .null,
          .integer(Int64(scope.validatorRevision)), .text(stamp.rowID.rawValue.uuidString),
          .integer(stamp.revision),
        ])
      try advanceOrdering(database)
      return true
    }
  }

  func invalidate(scope: CatalogIndexScope) throws {
    let database = try open(scope)
    try database.transaction {
      try database.execute("UPDATE metadata SET invalidation_revision=invalidation_revision+1")
      try database.execute("UPDATE coverage SET complete=0")
      try advanceOrdering(database)
    }
  }

  func locator(for id: CatalogRowID, scope: CatalogIndexScope) throws -> CatalogCandidate {
    try candidate(for: id, database: open(scope))
  }

  func queryPlan(scope: CatalogIndexScope) throws -> [String] {
    let database = try open(scope)
    var result: [String] = []
    try database.query(
      "EXPLAIN QUERY PLAN " + Self.pageSQL(predicate: ""),
      values: [.integer(Int64(scope.validatorRevision))]
    ) { result.append(try CatalogSQLiteDatabase.text($0, 3)) }
    return result
  }

  func beginScan(scope: CatalogIndexScope) throws -> CatalogIndexScanStamp {
    try scanStore(scope).begin()
  }

  func markSeen(
    _ rows: [CatalogRowID], scan: CatalogIndexScanStamp, scope: CatalogIndexScope
  ) throws -> Bool {
    try scanStore(scope).markSeen(rows, scan: scan)
  }

  func unseen(
    scan: CatalogIndexScanStamp, scope: CatalogIndexScope
  ) throws -> [CatalogIndexedResource] {
    try scanStore(scope).unseen(scan: scan)
  }

  func retire(
    _ rows: [CatalogResourceStamp], scan: CatalogIndexScanStamp, scope: CatalogIndexScope
  ) throws -> Bool {
    try scanStore(scope).retire(rows, scan: scan)
  }

  func finishScan(_ scan: CatalogIndexScanStamp, scope: CatalogIndexScope) throws -> Bool {
    try scanStore(scope).finish(scan)
  }

  private func scanStore(_ scope: CatalogIndexScope) throws -> CatalogSQLiteScanStore {
    try CatalogSQLiteScanStore(database: open(scope), session: session, epoch: epoch)
  }

  private func open(_ scope: CatalogIndexScope) throws -> CatalogSQLiteDatabase {
    guard !Thread.isMainThread, protectedDataAvailable(), scope.key.utf8.count == 64,
      scope.key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      scope.validatorRevision > 0
    else { throw CatalogIndexFailure.unavailable }
    if currentScope == scope, let database { return database }
    releaseConnection()
    do {
      return try connect(scope)
    } catch let error as CatalogIndexFailure {
      guard resetAvailable, error == .corrupt || error == .incompatible else { throw error }
      resetAvailable = false
      try files.discard()
      return try connect(scope)
    } catch {
      throw CatalogIndexFailure.unavailable
    }
  }

  private func connect(_ scope: CatalogIndexScope) throws -> CatalogSQLiteDatabase {
    try files.prepare()
    let connection = try CatalogSQLiteDatabase(url: files.root.appending(path: "catalog.sqlite"))
    try connection.execute("PRAGMA journal_mode=PERSIST")
    try files.prepare()
    for pragma in [
      "PRAGMA temp_store=MEMORY", "PRAGMA cache_size=-4096", "PRAGMA synchronous=FULL",
      "PRAGMA foreign_keys=ON", "PRAGMA trusted_schema=OFF", "PRAGMA journal_size_limit=1048576",
    ] { try connection.execute(pragma) }
    var pageSize: Int64 = 0
    try connection.query("PRAGMA page_size") { pageSize = sqlite3_column_int64($0, 0) }
    guard (512...65_536).contains(pageSize),
      (16_384...63 * 1_024 * 1_024).contains(maximumDatabaseBytes)
    else { throw CatalogIndexFailure.corrupt }
    try connection.execute("PRAGMA max_page_count=\(maximumDatabaseBytes / pageSize)")
    try configureSchema(connection, scope: scope)
    try files.verify()
    currentScope = scope
    database = connection
    return connection
  }

}

extension SQLiteCatalogIndex {
  fileprivate func configureSchema(
    _ connection: CatalogSQLiteDatabase, scope: CatalogIndexScope
  ) throws {
    var version: Int32 = 0
    try connection.query("PRAGMA user_version") { version = sqlite3_column_int($0, 0) }
    guard version == 0 || version == 2 else { throw CatalogIndexFailure.incompatible }
    if version == 0 {
      var count: Int64 = 0
      try connection.query("SELECT count(*) FROM sqlite_master WHERE type='table'") {
        count = sqlite3_column_int64($0, 0)
      }
      guard count == 0 else { throw CatalogIndexFailure.corrupt }
    }
    try connection.transaction {
      for statement in Self.schema { try connection.execute(statement) }
      var storedScope: String?
      var storedValidator: Int64?
      try connection.query("SELECT scope,epoch,validator_revision FROM metadata WHERE id=1") {
        storedScope = try CatalogSQLiteDatabase.text($0, 0)
        guard let storedEpoch = UUID(uuidString: try CatalogSQLiteDatabase.text($0, 1)) else {
          throw CatalogIndexFailure.corrupt
        }
        epoch = storedEpoch
        storedValidator = sqlite3_column_int64($0, 2)
      }
      if let storedScope {
        guard storedScope == scope.key, storedValidator == Int64(scope.validatorRevision) else {
          throw CatalogIndexFailure.incompatible
        }
      } else {
        guard version == 0 else { throw CatalogIndexFailure.corrupt }
        epoch = UUID()
        try connection.execute(
          "INSERT INTO metadata(id,scope,epoch,validator_revision,ordering_revision) VALUES(1,?,?,?,0)",
          values: [
            .text(scope.key), .text(epoch.uuidString), .integer(Int64(scope.validatorRevision)),
          ])
      }
      try connection.execute("PRAGMA user_version=2")
    }
  }

  private func candidate(
    for id: CatalogRowID, database: CatalogSQLiteDatabase
  ) throws -> CatalogCandidate {
    var result: CatalogCandidate?
    try database.query(
      "SELECT candidate FROM resources WHERE row_id=?", values: [.text(id.rawValue.uuidString)]
    ) {
      let text = try CatalogSQLiteDatabase.text($0, 0)
      result = try Self.decodeCandidate(text)
    }
    guard let result else { throw CatalogIndexFailure.changed }
    try Self.validate(result)
    return result
  }

  private func orderingRevision(_ database: CatalogSQLiteDatabase) throws -> Int64 {
    var result: Int64?
    try database.query("SELECT ordering_revision FROM metadata WHERE id=1") {
      result = try CatalogSQLiteDatabase.revision($0, 0)
    }
    guard let result else { throw CatalogIndexFailure.corrupt }
    return result
  }

  private func advanceOrdering(_ database: CatalogSQLiteDatabase) throws {
    try database.execute("UPDATE metadata SET ordering_revision=ordering_revision+1 WHERE id=1")
  }
}

// swiftlint:enable trailing_comma
