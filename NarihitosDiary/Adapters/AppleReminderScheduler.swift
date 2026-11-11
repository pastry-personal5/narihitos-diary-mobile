import Foundation
import UserNotifications

@MainActor
final class AppleReminderScheduler: NSObject, ReminderSchedulerPort {
  static let productionIdentifier = "pending-diary-work"
  let identifier: String
  private let center = UNUserNotificationCenter.current()
  /// Called when the user taps the reminder; the owner opens All and rechecks state.
  var onOpen: (() -> Void)?

  init(identifier: String = AppleReminderScheduler.productionIdentifier) {
    self.identifier = identifier
    super.init()
    center.delegate = self
  }

  func authorization() async -> ReminderAuthorization {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: .authorized
    case .denied: .denied
    default: .notDetermined
    }
  }

  func requestAuthorization() async -> ReminderAuthorization {
    _ = try? await center.requestAuthorization(options: [.alert])
    return await authorization()
  }

  func schedule(at trigger: Date, calendar: Calendar) async -> Bool {
    var parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: trigger)
    parts.calendar = calendar
    parts.timeZone = calendar.timeZone
    let calendarTrigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    // Nil, past or mismatched dates are a typed failure, never a fallback interval.
    guard let next = calendarTrigger.nextTriggerDate(), abs(next.timeIntervalSince(trigger)) < 1
    else { return false }
    let content = UNMutableNotificationContent()
    content.body = "You have pending diary work."
    do {
      try await center.add(
        UNNotificationRequest(
          identifier: identifier, content: content, trigger: calendarTrigger))
      return true
    } catch {
      return false
    }
  }

  func cancel() async {
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }
}

extension AppleReminderScheduler: @preconcurrency UNUserNotificationCenterDelegate {
  // The in-app notice already covers the foreground.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.identifier == identifier { onOpen?() }
    completionHandler()
  }
}

@MainActor
final class FileReminderStore: ReminderStorePort {
  private let fileURL: URL

  init(root: URL? = nil) {
    let base =
      root
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("NarihitosDiary", isDirectory: true)
    fileURL = base.appendingPathComponent("pending-reminder.json", isDirectory: false)
  }

  func load() -> ReminderRecord? {
    guard let data = try? Data(contentsOf: fileURL), data.count <= 4_096 else { return nil }
    return try? JSONDecoder().decode(ReminderRecord.self, from: data)
  }

  func save(_ record: ReminderRecord) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Holds no diary content; first-unlock protection lets locked background settlement persist.
    try JSONEncoder().encode(record).write(
      to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
