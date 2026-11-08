import Foundation

extension DiaryCatalogHandler {
  func mayAppearInTimeline(_ candidate: CatalogCandidate) -> Bool { candidate.date != nil }
  func hasKnownTimelineOrder(_ candidate: CatalogCandidate) -> Bool { candidate.date != nil }

  /// The next UTC bucket boundary is an exclusive upper bound after layout validation.
  func unexploredDateUpperBound(in components: [String]) -> Date? {
    guard !components.isEmpty, descends(into: components) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
    calendar.timeZone = utc
    guard let year = Int(components[0]), year > 0 else { return nil }
    let month = components.count > 1 ? Int(components[1]) : 1
    let day = components.count > 2 ? Int(components[2]) : 1
    guard let month, let day,
      let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      calendar.component(.year, from: start) == year,
      calendar.component(.month, from: start) == month,
      calendar.component(.day, from: start) == day
    else { return nil }
    let unit: Calendar.Component =
      components.count == 1 ? .year : (components.count == 2 ? .month : .day)
    return calendar.date(byAdding: unit, value: 1, to: start)
  }
}
