import Foundation

// M18a: one generic local reminder for pending diary work. No platform types here.

enum PendingWorkObservation: Equatable, Sendable {
  case present
  case empty
  /// Storage not yet or not fully observed; never treated as empty.
  case unknown
}

enum ReminderAuthorization: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
}

struct ReminderRecord: Codable, Equatable, Sendable {
  var installation: String
  var permissionAttempted = false
  var departure: Date?
  var trigger: Date?
}

@MainActor
protocol ReminderStorePort: AnyObject {
  func load() -> ReminderRecord?
  func save(_ record: ReminderRecord) throws
}

@MainActor
protocol ReminderSchedulerPort: AnyObject {
  func authorization() async -> ReminderAuthorization
  func requestAuthorization() async -> ReminderAuthorization
  /// Replaces the single app-owned request. True only when the system trigger was verified.
  func schedule(at trigger: Date, calendar: Calendar) async -> Bool
  /// Removes the pending request and any delivered copy.
  func cancel() async
}

enum ReminderCalendar {
  /// Same wall time on the next local calendar day; missing DST time -> next valid, repeated -> first.
  static func nextTrigger(after departure: Date, calendar: Calendar) -> Date? {
    let wall = calendar.dateComponents([.hour, .minute, .second], from: departure)
    let today = calendar.startOfDay(for: departure)
    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
    let result = calendar.nextDate(
      after: nextDay.addingTimeInterval(-1), matching: wall, matchingPolicy: .nextTime,
      repeatedTimePolicy: .first, direction: .forward)
    return result.flatMap { $0 > departure ? $0 : nil }
  }
}

@MainActor
final class PendingReminderCoordinator {
  private let scheduler: any ReminderSchedulerPort
  private let store: any ReminderStorePort
  private let installation: () -> String?
  private let now: () -> Date
  private let calendar: () -> Calendar
  private var record: ReminderRecord?
  private var observation = PendingWorkObservation.unknown
  private var canPrompt = false
  private var inBackground = false
  private var pendingDeparture: Date?
  private var running = false
  private var dirty = false
  private(set) var notificationsDenied = false
  var onChange: (() -> Void)?

  init(
    scheduler: any ReminderSchedulerPort, store: any ReminderStorePort,
    installation: @escaping () -> String?, now: @escaping () -> Date = Date.init,
    calendar: @escaping () -> Calendar = { Calendar.current }
  ) {
    self.scheduler = scheduler
    self.store = store
    self.installation = installation
    self.now = now
    self.calendar = calendar
  }

  /// `canPrompt` is true only in the foreground with no capture in progress.
  func update(observation: PendingWorkObservation, canPrompt: Bool) {
    guard observation != self.observation || canPrompt != self.canPrompt else { return }
    self.observation = observation
    self.canPrompt = canPrompt
    reconcile()
  }

  /// Genuine foreground-to-background transition only; repeats reuse the first anchor.
  func departed(at date: Date) {
    guard !inBackground else {
      onChange?()
      return
    }
    inBackground = true
    canPrompt = false
    pendingDeparture = date
    reconcile()
  }

  func foregrounded() {
    inBackground = false
    reconcile()
  }

  private func reconcile() {
    dirty = true
    guard !running else { return }
    running = true
    Task {
      while dirty {
        dirty = false
        await converge()
      }
      running = false
      onChange?()
    }
  }

  private func persist(_ value: ReminderRecord) {
    record = value
    try? store.save(value)  // shortcut: a failed write keeps the in-memory state until relaunch
  }

  private func converge() async {
    guard let installation = installation() else { return }
    var value = record ?? store.load() ?? ReminderRecord(installation: installation)
    if value.installation != installation {
      // A restored schedule from another installation is never replayed.
      await scheduler.cancel()
      value = ReminderRecord(installation: installation)
      persist(value)
    }
    if let departure = pendingDeparture {
      pendingDeparture = nil
      value.departure = departure
      persist(value)
    }
    switch observation {
    case .unknown:
      return
    case .empty:
      notificationsDenied = false
      await scheduler.cancel()
      value.departure = nil
      value.trigger = nil
      persist(value)
    case .present:
      var auth = await scheduler.authorization()
      if auth == .notDetermined, canPrompt, !value.permissionAttempted {
        value.permissionAttempted = true
        persist(value)
        auth = await scheduler.requestAuthorization()
      }
      notificationsDenied = auth == .denied
      guard !dirty, auth == .authorized else { return }
      await schedulePresent(&value)
    }
  }

  private func schedulePresent(_ value: inout ReminderRecord) async {
    guard let departure = value.departure else {
      if let trigger = value.trigger, trigger <= now() {
        value.trigger = nil
        persist(value)
      }
      return
    }
    let calendar = calendar()
    guard let target = ReminderCalendar.nextTrigger(after: departure, calendar: calendar),
      target > now()
    else {
      // Overdue: retire rather than fire immediately or repeat; the next departure re-arms.
      await scheduler.cancel()
      value.departure = nil
      value.trigger = nil
      persist(value)
      return
    }
    let scheduled = await scheduler.schedule(at: target, calendar: calendar)
    // A change during the await reruns converge serially, which cancels or replaces this request.
    value.trigger = scheduled ? target : nil
    // The anchor only matters while backgrounded or until reopen has reconciled it.
    if !inBackground { value.departure = nil }
    persist(value)
  }
}
