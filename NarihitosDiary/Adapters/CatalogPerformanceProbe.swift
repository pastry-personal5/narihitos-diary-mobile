import Foundation

/// Optional aggregate diagnostics. Keys and values never contain source identities or diary data.
enum CatalogPerformanceMetric: String, Sendable {
  case enumerationVisits
  case candidateVisits
  case validationAttempts
  case markdownBytes
  case audioDecodeBytes
  case audioHashBytes
  case audioDecodeNanoseconds
  case audioHashNanoseconds
}

final class CatalogPerformanceProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [CatalogPerformanceMetric: UInt64] = [:]

  func record(_ metric: CatalogPerformanceMetric, _ amount: UInt64 = 1) {
    lock.withLock { values[metric, default: 0] += amount }
  }

  var snapshot: [String: UInt64] {
    lock.withLock { Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }) }
  }
}
