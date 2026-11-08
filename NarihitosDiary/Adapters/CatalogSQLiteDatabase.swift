import Foundation
import SQLite3

private let catalogSwiftCollation:
  @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafeRawPointer?, Int32, UnsafeRawPointer?
  ) -> Int32 = { _, leftSize, leftBytes, rightSize, rightBytes in
    let left = CatalogSQLiteDatabase.collationString(leftBytes, count: leftSize)
    let right = CatalogSQLiteDatabase.collationString(rightBytes, count: rightSize)
    return left == right ? 0 : (left < right ? -1 : 1)
  }

/// Connection and statements remain confined to the owning index actor's synchronous operations.
final class CatalogSQLiteDatabase: @unchecked Sendable {
  private let connection: CatalogSQLiteConnection
  var handle: OpaquePointer { connection.handle }

  init(url: URL) throws {
    var connection: OpaquePointer?
    let flags =
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
      | SQLITE_OPEN_NOFOLLOW
    let status = sqlite3_open_v2(url.path, &connection, flags, nil)
    guard status == SQLITE_OK, let connection else {
      if let connection { sqlite3_close(connection) }
      throw Self.failure(status)
    }
    self.connection = CatalogSQLiteConnection(connection)
    sqlite3_extended_result_codes(handle, 1)
    sqlite3_busy_timeout(handle, 250)
    sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 65_536)
    let collation = sqlite3_create_collation(
      handle, "SWIFT_STRING", SQLITE_UTF8, nil, catalogSwiftCollation)
    guard collation == SQLITE_OK else { throw Self.failure(collation) }
  }

  func execute(_ sql: String, values: [CatalogSQLValue] = []) throws {
    try query(sql, values: values) { _ in }
  }

  func query(
    _ sql: String, values: [CatalogSQLValue] = [], row: (OpaquePointer) throws -> Void
  ) throws {
    var prepared: OpaquePointer?
    let status = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
    guard status == SQLITE_OK, let prepared else { throw Self.failure(status) }
    defer { sqlite3_finalize(prepared) }
    try bind(values, to: prepared)
    while true {
      switch sqlite3_step(prepared) {
      case SQLITE_ROW: try row(prepared)
      case SQLITE_DONE: return
      case let error: throw Self.failure(error)
      }
    }
  }

  private func bind(_ values: [CatalogSQLValue], to prepared: OpaquePointer) throws {
    for (index, value) in values.enumerated() {
      let parameter = Int32(index + 1)
      let bound: Int32
      switch value {
      case .text(let text):
        guard !text.contains("\0"), text.utf8.count <= 16_384 else {
          throw CatalogIndexFailure.unsafe
        }
        bound = text.withCString {
          sqlite3_bind_text(
            prepared, parameter, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
      case .integer(let number): bound = sqlite3_bind_int64(prepared, parameter, number)
      case .real(let number):
        guard number.isFinite else { throw CatalogIndexFailure.unsafe }
        bound = sqlite3_bind_double(prepared, parameter, number)
      case .null: bound = sqlite3_bind_null(prepared, parameter)
      }
      guard bound == SQLITE_OK else { throw Self.failure(bound) }
    }
  }

  func transaction<Value>(_ work: () throws -> Value) throws -> Value {
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try work()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  static func text(_ row: OpaquePointer, _ column: Int32) throws -> String {
    guard sqlite3_column_type(row, column) == SQLITE_TEXT,
      let bytes = sqlite3_column_text(row, column)
    else { throw CatalogIndexFailure.corrupt }
    let length = Int(sqlite3_column_bytes(row, column))
    guard length <= 16_384,
      let value = String(bytes: UnsafeBufferPointer(start: bytes, count: length), encoding: .utf8),
      !value.contains("\0")
    else { throw CatalogIndexFailure.corrupt }
    return value
  }

  static func optionalText(_ row: OpaquePointer, _ column: Int32) throws -> String? {
    sqlite3_column_type(row, column) == SQLITE_NULL ? nil : try text(row, column)
  }

  static func revision(_ row: OpaquePointer, _ column: Int32) throws -> Int64 {
    let value = sqlite3_column_int64(row, column)
    guard sqlite3_column_type(row, column) == SQLITE_INTEGER, value >= 0, value < Int64.max else {
      throw CatalogIndexFailure.corrupt
    }
    return value
  }

  static func failure(_ code: Int32) -> CatalogIndexFailure {
    switch code & 0xFF {
    case SQLITE_BUSY, SQLITE_LOCKED: .busy
    case SQLITE_FULL, SQLITE_NOMEM, SQLITE_TOOBIG: .capacity
    case SQLITE_CORRUPT, SQLITE_NOTADB: .corrupt
    case SQLITE_SCHEMA: .incompatible
    default: .unavailable
    }
  }

  static func collationString(_ bytes: UnsafeRawPointer?, count: Int32) -> String {
    guard let bytes else { return "" }
    return String(
      bytes: UnsafeBufferPointer(
        start: bytes.assumingMemoryBound(to: UInt8.self), count: Int(count)),
      encoding: .utf8) ?? ""
  }
}

private final class CatalogSQLiteConnection: @unchecked Sendable {
  let handle: OpaquePointer
  init(_ handle: OpaquePointer) { self.handle = handle }
  deinit { sqlite3_close(handle) }
}

enum CatalogSQLValue {
  case text(String)
  case integer(Int64)
  case real(Double)
  case null
}
