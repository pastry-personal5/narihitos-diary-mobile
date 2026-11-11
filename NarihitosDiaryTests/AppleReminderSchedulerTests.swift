import Foundation
import Testing
import UserNotifications

@testable import NarihitosDiary

@MainActor
struct AppleReminderSchedulerTests {
  @Test(arguments: [
    // swiftlint:disable:next trailing_comma
    UNAuthorizationStatus.authorized, .provisional, .ephemeral, .denied, .notDetermined,
  ])
  func mapsLiveAuthorization(status: UNAuthorizationStatus) async {
    let center = TestReminderNotificationCenter()
    center.status = status
    let scheduler = AppleReminderScheduler(center: center)
    let expected: ReminderAuthorization =
      status == .denied ? .denied : status == .notDetermined ? .notDetermined : .authorized
    #expect(await scheduler.authorization() == expected)
    #expect(center.delegate === scheduler)
  }

  @Test func requestsOnlyAlertsAndRechecksStatusEvenWhenTheRequestFails() async {
    let center = TestReminderNotificationCenter()
    let scheduler = AppleReminderScheduler(center: center)
    center.statusAfterRequest = .authorized
    #expect(await scheduler.requestAuthorization() == .authorized)
    #expect(center.requestedOptions == [.alert])
    center.statusAfterRequest = .denied
    center.failRequest = true
    #expect(await scheduler.requestAuthorization() == .denied)
  }

  @Test(arguments: ["UTC", "America/New_York", "Pacific/Auckland", "Pacific/Kiritimati"])
  func buildsOneGenericCalendarRequestInTheSuppliedZone(zone: String) async throws {
    let center = TestReminderNotificationCenter()
    let scheduler = AppleReminderScheduler(identifier: "synthetic-reminder", center: center)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: zone))
    let target = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 172_800)
    #expect(await scheduler.schedule(at: target, calendar: calendar))
    let request = try #require(center.requests[scheduler.identifier])
    #expect(center.requests.count == 1)
    #expect(request.content.body == "You have pending diary work.")
    #expect(request.content.title.isEmpty && request.content.userInfo.isEmpty)
    #expect(request.content.attachments.isEmpty && request.content.sound == nil)
    let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
    #expect(!trigger.repeats)
    #expect(trigger.dateComponents.timeZone == calendar.timeZone)
    #expect(trigger.nextTriggerDate() == target)
    let later = target.addingTimeInterval(3_600)
    #expect(await scheduler.schedule(at: later, calendar: calendar))
    #expect(center.requests.count == 1)
    let replacement = try #require(
      center.requests[scheduler.identifier]?.trigger as? UNCalendarNotificationTrigger)
    #expect(replacement.nextTriggerDate() == later)
  }

  @Test func refusesPastTriggersAndReportsSystemAddFailure() async {
    let center = TestReminderNotificationCenter()
    let scheduler = AppleReminderScheduler(center: center)
    #expect(
      await scheduler.schedule(at: .now.addingTimeInterval(-3_600), calendar: .current) == false)
    #expect(center.addAttempts == 0)
    center.failAdd = true
    #expect(
      await scheduler.schedule(at: .now.addingTimeInterval(86_400), calendar: .current) == false)
    #expect(center.addAttempts == 1)
    #expect(center.requests.isEmpty)
  }

  @Test func cancelRemovesOnlyOwnedPendingAndDeliveredRequests() async throws {
    let center = TestReminderNotificationCenter()
    let scheduler = AppleReminderScheduler(identifier: "synthetic-reminder", center: center)
    let other = AppleReminderScheduler(identifier: "other-reminder", center: center)
    for item in [scheduler, other] {
      #expect(await item.schedule(at: .now.addingTimeInterval(86_400), calendar: .current))
    }
    center.delivered = Set(center.requests.keys)
    await scheduler.cancel()
    #expect(Set(center.requests.keys) == [other.identifier])
    #expect(center.delivered == [other.identifier])
    #expect(center.pendingRemovals == [[scheduler.identifier]])
    #expect(center.deliveredRemovals == [[scheduler.identifier]])
  }
}

@MainActor
private final class TestReminderNotificationCenter: ReminderNotificationCenter {
  weak var delegate: (any UNUserNotificationCenterDelegate)?
  var status = UNAuthorizationStatus.notDetermined
  var statusAfterRequest = UNAuthorizationStatus.authorized
  var failRequest = false
  var failAdd = false
  var requestedOptions: [UNAuthorizationOptions] = []
  var requests: [String: UNNotificationRequest] = [:]
  var delivered: Set<String> = []
  var addAttempts = 0
  var pendingRemovals: [[String]] = []
  var deliveredRemovals: [[String]] = []

  func authorizationStatus() async -> UNAuthorizationStatus { status }
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    requestedOptions.append(options)
    status = statusAfterRequest
    if failRequest { throw CocoaError(.userCancelled) }
    return status == .authorized
  }
  func add(_ request: UNNotificationRequest) async throws {
    addAttempts += 1
    if failAdd { throw CocoaError(.fileWriteNoPermission) }
    requests[request.identifier] = request
  }
  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    pendingRemovals.append(identifiers)
    for identifier in identifiers { requests[identifier] = nil }
  }
  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    deliveredRemovals.append(identifiers)
    delivered.subtract(identifiers)
  }
}

@MainActor
struct FileReminderStoreTests {
  @Test func recordReopensAndOversizedOrCorruptDataIsIgnored() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = ReminderRecord(
      installation: "synthetic", permissionAttempted: true,
      departure: Date(timeIntervalSince1970: 100), trigger: Date(timeIntervalSince1970: 200))
    try FileReminderStore(root: root).save(record)
    #expect(FileReminderStore(root: root).load() == record)
    let file = root.appending(path: "pending-reminder.json")
    for data in [Data("invalid".utf8), Data(repeating: 0x7B, count: 5_000)] {
      try data.write(to: file)
      #expect(FileReminderStore(root: root).load() == nil)
    }
  }
}
