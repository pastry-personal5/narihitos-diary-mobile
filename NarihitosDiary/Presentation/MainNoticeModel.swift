import Combine
import Foundation

struct MainNotice: Equatable, Sendable, Identifiable {
  enum Category: Int, Comparable, Sendable {
    case processing, queued, recovery
    static func < (left: Category, right: Category) -> Bool { left.rawValue < right.rawValue }
  }
  let category: Category
  let destination: CatalogRecoveryDestination
  let message: String
  var id: String { "\(category.rawValue):\(destination.rawValue)" }
}

@MainActor
final class MainNoticeModel: ObservableObject {
  @Published private(set) var current: MainNotice?
  var announce: (@MainActor (String) -> Void)?
  private var notices: [MainNotice] = []
  private var announced: Set<String> = []
  private var timer: Task<Void, Never>?
  private var visible = false
  private var paused = false
  private var recoveryIndex = 0
  private let sleep: @Sendable () async throws -> Void

  init(
    sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(10)) }
  ) {
    self.sleep = sleep
  }

  func update(_ values: [MainNotice]) {
    var unique: [String: MainNotice] = [:]
    for value in values where unique[value.id] == nil { unique[value.id] = value }
    let ordered = unique.values.sorted {
      $0.category == $1.category
        ? $0.destination.rawValue < $1.destination.rawValue : $0.category < $1.category
    }
    let previous = Set(notices.map(\.id))
    let changed = previous != Set(ordered.map(\.id))
    notices = ordered
    if changed {
      current = ordered.first
      recoveryIndex = current?.category == .recovery ? 1 : 0
      announced.formIntersection(Set(ordered.map(\.id)))
    } else if let current {
      self.current = ordered.first { $0.id == current.id }
    }
    announcePending()
    if changed { restartTimer() }
  }

  func setEnvironment(visible: Bool, paused: Bool) {
    guard self.visible != visible || self.paused != paused else { return }
    self.visible = visible
    self.paused = paused
    announcePending()
    restartTimer()
  }

  func advance() {
    guard !paused, visible, !notices.isEmpty else { return }
    let categories = Array(Set(notices.map(\.category))).sorted()
    guard let current, let index = categories.firstIndex(of: current.category) else {
      self.current = notices.first
      return
    }
    let category = categories[(index + 1) % categories.count]
    let matching = notices.filter { $0.category == category }
    if category == .recovery {
      self.current = matching[recoveryIndex % matching.count]
      recoveryIndex += 1
    } else {
      self.current = matching.first
    }
  }

  private func announcePending() {
    guard visible else { return }
    for notice in notices where !announced.contains(notice.id) {
      announced.insert(notice.id)
      announce?(notice.message)
    }
  }

  private func restartTimer() {
    timer?.cancel()
    timer = nil
    guard visible, !paused, notices.count > 1 else { return }
    let sleep = sleep
    timer = Task { [weak self] in
      while !Task.isCancelled {
        do { try await sleep() } catch { return }
        guard !Task.isCancelled, let self else { return }
        advance()
      }
    }
  }
}
