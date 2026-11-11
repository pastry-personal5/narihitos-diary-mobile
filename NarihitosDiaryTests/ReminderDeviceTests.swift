import Foundation
import Testing
import UserNotifications

@testable import NarihitosDiary

// M18a on-device checks against the real UserNotifications center. They use a private
// request identifier, so a real pending-work reminder on the phone is never touched.
// Precondition: notifications are allowed for the app (grant once in Settings > Notifications).

@MainActor
private func makeScheduler() -> AppleReminderScheduler {
  AppleReminderScheduler(identifier: "device-test-\(UUID().uuidString)")
}

@MainActor
private func pending(_ scheduler: AppleReminderScheduler) async -> [UNNotificationRequest] {
  await UNUserNotificationCenter.current().pendingNotificationRequests().filter {
    $0.identifier == scheduler.identifier
  }
}

private func calendar(_ zone: String) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: zone)!
  return calendar
}

@MainActor
struct ReminderDeviceTests {
  private func requireAuthorized(_ scheduler: AppleReminderScheduler) async throws {
    var status = await scheduler.authorization()
    // First run only: the system sheet must be answered by hand on the unlocked phone.
    if status == .notDetermined { status = await scheduler.requestAuthorization() }
    try #require(
      status == .authorized,
      "Allow notifications for Narihito's Diary on the test phone, then rerun.")
  }

  @Test func schedulesOneGenericNonrepeatingCalendarRequest() async throws {
    let scheduler = makeScheduler()
    try await requireAuthorized(scheduler)
    let cal = calendar("UTC")
    let target = Date().addingTimeInterval(2 * 86_400).rounded()
    let scheduled = await scheduler.schedule(at: target, calendar: cal)
    let requests = await pending(scheduler)
    await scheduler.cancel()
    #expect(scheduled)
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.content.body == "You have pending diary work.")
    #expect(request.content.title.isEmpty && request.content.userInfo.isEmpty)
    #expect(request.content.attachments.isEmpty && request.content.sound == nil)
    let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
    #expect(!trigger.repeats)
    #expect(trigger.nextTriggerDate() == target)
    #expect(await pending(scheduler).isEmpty)
  }

  @Test func replacingKeepsExactlyOneRequestAtTheNewestDate() async throws {
    let scheduler = makeScheduler()
    try await requireAuthorized(scheduler)
    let cal = calendar("UTC")
    let first = Date().addingTimeInterval(2 * 86_400).rounded()
    let second = first.addingTimeInterval(3_600)
    _ = await scheduler.schedule(at: first, calendar: cal)
    _ = await scheduler.schedule(at: second, calendar: cal)
    let requests = await pending(scheduler)
    await scheduler.cancel()
    #expect(requests.count == 1)
    let trigger = try #require(requests.first?.trigger as? UNCalendarNotificationTrigger)
    #expect(trigger.nextTriggerDate() == second)
  }

  @Test func pastAndInvalidTriggersAreRefusedNotFiredImmediately() async throws {
    let scheduler = makeScheduler()
    try await requireAuthorized(scheduler)
    let scheduled = await scheduler.schedule(
      at: Date().addingTimeInterval(-3_600).rounded(), calendar: calendar("UTC"))
    #expect(!scheduled)
    #expect(await pending(scheduler).isEmpty)
  }

  @Test(arguments: [
    ("America/New_York", "2027-03-13T07:30:00Z", "2027-03-14T07:00:00Z"),  // spring-forward gap
    ("America/New_York", "2027-11-06T05:30:00Z", "2027-11-07T05:30:00Z"),  // fall-back repeat
    ("Pacific/Auckland", "2027-12-31T10:00:00Z", "2028-01-01T10:00:00Z"),  // year boundary, +13
    // swiftlint:disable:next trailing_comma
    ("Pacific/Kiritimati", "2027-02-28T09:00:00Z", "2027-03-01T09:00:00Z"),  // date-line zone
  ])
  func productionTriggerMatchesTheComputedLocalInstant(
    zone: String, departure: String, expected: String
  ) async throws {
    let scheduler = makeScheduler()
    try await requireAuthorized(scheduler)
    let cal = calendar(zone)
    let formatter = ISO8601DateFormatter()
    let start = try #require(formatter.date(from: departure))
    let target = try #require(ReminderCalendar.nextTrigger(after: start, calendar: cal))
    #expect(target == formatter.date(from: expected))
    // The adapter itself compares nextTriggerDate() with the target, so a false here means the
    // real system trigger disagrees with the policy. Past dates are refused, so skip those.
    guard target > Date() else { return }
    #expect(await scheduler.schedule(at: target, calendar: cal))
    await scheduler.cancel()
  }

  @Test func coordinatorDrivesTheRealCenterFromDepartureToEmpty() async throws {
    let scheduler = makeScheduler()
    try await requireAuthorized(scheduler)
    let store = FileReminderStore(
      root: FileManager.default.temporaryDirectory
        .appendingPathComponent("reminder-\(UUID().uuidString)", isDirectory: true))
    let departure = Date().addingTimeInterval(60).rounded()
    let coordinator = PendingReminderCoordinator(
      scheduler: scheduler, store: store, installation: { "device-test" })
    defer { Task { await scheduler.cancel() } }

    coordinator.update(observation: .present, canPrompt: true)
    coordinator.departed(at: departure)
    try await waitUntil { await pending(scheduler).count == 1 }
    let trigger = try #require(
      await pending(scheduler).first?.trigger as? UNCalendarNotificationTrigger)
    #expect(
      trigger.nextTriggerDate()
        == ReminderCalendar.nextTrigger(after: departure, calendar: .current))
    #expect(store.load()?.trigger == trigger.nextTriggerDate())

    // Rapid churn must converge to at most one request, none once work is gone.
    for _ in 0..<5 {
      coordinator.update(observation: .unknown, canPrompt: true)
      coordinator.update(observation: .present, canPrompt: true)
    }
    coordinator.update(observation: .empty, canPrompt: false)
    try await waitUntil { await pending(scheduler).isEmpty && store.load()?.trigger == nil }
    #expect(store.load()?.departure == nil)
  }

  @Test func reminderRecordSurvivesOnDeviceWithFirstUnlockProtection() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileReminderStore(root: root)
    let record = ReminderRecord(
      installation: "i", permissionAttempted: true, departure: Date(timeIntervalSince1970: 100),
      trigger: Date(timeIntervalSince1970: 200))
    try store.save(record)
    #expect(store.load() == record)
    let file = root.appendingPathComponent("pending-reminder.json")
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect(
      attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
    try Data(repeating: 0x7B, count: 5_000).write(to: file)
    #expect(store.load() == nil)  // oversize/corrupt is ignored, never trusted
  }
}

@MainActor
private func waitUntil(
  timeout: Duration = .seconds(10), _ condition: () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(100))
  }
  Issue.record("Condition not met within \(timeout)")
}

extension Date {
  fileprivate func rounded() -> Date {
    Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
  }
}
