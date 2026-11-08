import Foundation

/// Display identity is independent of the live capability required by detail and actions.
enum CatalogListRow: Equatable, Identifiable {
  case current(CatalogSummary)
  case remembered(CatalogRememberedRow)

  var id: CatalogRowID {
    switch self {
    case .current(let summary): CatalogRowID(summary.id)
    case .remembered(let row): row.id
    }
  }
  var title: String {
    switch self {
    case .current(let summary): summary.title
    case .remembered(let row): row.title
    }
  }
  var createdAt: Date {
    switch self {
    case .current(let summary): summary.createdAt
    case .remembered(let row): row.createdAt
    }
  }
  var currentHandle: CatalogItemHandle? {
    if case .current(let summary) = self { return summary.handle }
    return nil
  }
}

enum CatalogSelection: Hashable, Identifiable {
  case current(CatalogItemHandle)
  case remembered(CatalogRowID)

  var id: UUID {
    switch self {
    case .current(let handle): handle.id
    case .remembered(let row): row.rawValue
    }
  }
  var handle: CatalogItemHandle? {
    if case .current(let handle) = self { return handle }
    return nil
  }
}

struct CatalogListSection: Identifiable {
  let date: Date
  let entries: [CatalogListRow]
  var id: Date { date }

  static func group(_ rows: [CatalogListRow], calendar: Calendar) -> [Self] {
    Dictionary(grouping: rows) { calendar.startOfDay(for: $0.createdAt) }
      .map { Self(date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
  }
}

struct CatalogDateSection: Identifiable {
  let date: Date
  let entries: [CatalogSummary]
  var id: Date { date }
}

enum CatalogDateSections {
  static func group(_ summaries: [CatalogSummary], calendar: Calendar) -> [CatalogDateSection] {
    Dictionary(grouping: summaries) { calendar.startOfDay(for: $0.createdAt) }
      .map { CatalogDateSection(date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
  }
}
