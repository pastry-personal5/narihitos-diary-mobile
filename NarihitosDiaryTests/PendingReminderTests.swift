import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
private final class FakeScheduler: ReminderSchedulerPort {
  var status = ReminderAuthorization.authorized
  var grantOnRequest = true
  var requests = 0
  var scheduled: [Date] = []
  var cancels = 0
  var verified = true

  func authorization() async -> ReminderAuthorization { status }
  func requestAuthorization() async -> ReminderAuthorization {
    requests += 1
    status = grantOnRequest ? .authorized : .denied
    return status
  }
  func schedule(at trigger: Date, calendar: Calendar) async -> Bool {
    scheduled.append(trigger)
    return verified
  }
  func cancel() async { cancels += 1 }
}

@MainActor
private final class MemoryReminderStore: ReminderStorePort {
  var value: ReminderRecord?
  func load() -> ReminderRecord? { value }
  func save(_ record: ReminderRecord) throws { value = record }
}

@MainActor
private struct Rig {
  let scheduler = FakeScheduler()
  let store = MemoryReminderStore()
  let calendar: Calendar
  var clock: Date
  let coordinator: PendingReminderCoordinator

  init(now: Date = Date(timeIntervalSince1970: 1_800_000_000), installation: String = "a") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    self.calendar = calendar
    clock = now
    coordinator = PendingReminderCoordinator(
      scheduler: scheduler, store: store, installation: { installation }, now: { now },
      calendar: { calendar })
  }
}

@MainActor
private func settle() async {
  for _ in 0..<20 { await Task.yield() }
}

@MainActor
struct PendingReminderTests {
  private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
  }

  private func zoned(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
  }

  @Test func nextDayKeepsWallTimeAcrossMonthBoundary() {
    let next = ReminderCalendar.nextTrigger(
      after: date("2027-01-31T21:15:30Z"), calendar: zoned("UTC"))
    #expect(next == date("2027-02-01T21:15:30Z"))
  }

  @Test func springForwardGapUsesNextValidTime() {
    // 2027-03-13 02:30 EST -> 03-14 02:30 does not exist; next valid is 03:00 EDT.
    let next = ReminderCalendar.nextTrigger(
      after: date("2027-03-13T07:30:00Z"), calendar: zoned("America/New_York"))
    #expect(next == date("2027-03-14T07:00:00Z"))
  }

  @Test func fallBackRepeatedTimeUsesFirstOccurrence() {
    // 2027-11-06 01:30 EDT -> 11-07 01:30 occurs twice; first is EDT (05:30Z).
    let next = ReminderCalendar.nextTrigger(
      after: date("2027-11-06T05:30:00Z"), calendar: zoned("America/New_York"))
    #expect(next == date("2027-11-07T05:30:00Z"))
  }

  @Test func schedulesOnceAfterDepartureWithPendingWork() async {
    let rig = Rig()
    let departure = rig.clock
    rig.coordinator.update(observation: .present, canPrompt: true)
    rig.coordinator.departed(at: departure)
    rig.coordinator.departed(at: departure.addingTimeInterval(5))  // repeated: same anchor
    await settle()
    #expect(rig.scheduler.scheduled == [departure.addingTimeInterval(86_400)])
    #expect(rig.store.value?.trigger == departure.addingTimeInterval(86_400))
  }

  @Test func foregroundWithoutDepartureNeverSchedules() async {
    let rig = Rig()
    rig.coordinator.update(observation: .present, canPrompt: true)
    await settle()
    #expect(rig.scheduler.scheduled.isEmpty)
  }

  @Test func unknownIsNotEmptyAndChangesNothing() async {
    let rig = Rig()
    rig.coordinator.update(observation: .unknown, canPrompt: true)
    rig.coordinator.departed(at: rig.clock)
    await settle()
    #expect(rig.scheduler.scheduled.isEmpty)
    #expect(rig.scheduler.cancels == 0)
  }

  @Test func lastItemClearingCancels() async {
    let rig = Rig()
    rig.coordinator.update(observation: .present, canPrompt: true)
    rig.coordinator.departed(at: rig.clock)
    await settle()
    rig.coordinator.update(observation: .empty, canPrompt: false)
    await settle()
    #expect(rig.scheduler.cancels == 1)
    #expect(rig.store.value?.trigger == nil)
    #expect(rig.store.value?.departure == nil)
  }

  @Test func promptsOnceOnlyWhenSafeAndNeverRepeatsAfterDenial() async {
    let rig = Rig()
    rig.scheduler.status = .notDetermined
    rig.scheduler.grantOnRequest = false
    rig.coordinator.update(observation: .present, canPrompt: false)  // capturing/background
    await settle()
    #expect(rig.scheduler.requests == 0)
    rig.coordinator.update(observation: .present, canPrompt: true)
    await settle()
    #expect(rig.scheduler.requests == 1)
    #expect(rig.coordinator.notificationsDenied)
    rig.scheduler.status = .notDetermined  // even if the system still allows it
    rig.coordinator.update(observation: .unknown, canPrompt: true)
    rig.coordinator.update(observation: .present, canPrompt: true)
    await settle()
    #expect(rig.scheduler.requests == 1)
    #expect(rig.scheduler.scheduled.isEmpty)
  }

  @Test func deniedKeepsStateAndSchedulesNothing() async {
    let rig = Rig()
    rig.scheduler.status = .denied
    rig.coordinator.update(observation: .present, canPrompt: true)
    rig.coordinator.departed(at: rig.clock)
    await settle()
    #expect(rig.scheduler.scheduled.isEmpty)
    #expect(rig.coordinator.notificationsDenied)
  }

  @Test func unverifiedTriggerIsRecordedAsNotScheduled() async {
    let rig = Rig()
    rig.scheduler.verified = false
    rig.coordinator.update(observation: .present, canPrompt: true)
    rig.coordinator.departed(at: rig.clock)
    await settle()
    #expect(rig.store.value?.trigger == nil)
  }

  @Test func overdueDepartureIsRetiredOnReopen() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let rig = Rig(now: now)
    rig.store.value = ReminderRecord(
      installation: "a", departure: now.addingTimeInterval(-200_000),
      trigger: now.addingTimeInterval(-100_000))
    rig.coordinator.update(observation: .present, canPrompt: true)
    rig.coordinator.foregrounded()
    await settle()
    #expect(rig.scheduler.scheduled.isEmpty)
    #expect(rig.scheduler.cancels == 1)
    #expect(rig.store.value?.trigger == nil)
  }

  @Test func foregroundReopenConsumesAnchorSoLaterWorkWaitsForNextDeparture() async {
    let rig = Rig()
    rig.coordinator.update(observation: .present, canPrompt: true)
    rig.coordinator.departed(at: rig.clock)
    await settle()
    rig.coordinator.foregrounded()
    await settle()
    #expect(rig.store.value?.departure == nil)
    #expect(rig.store.value?.trigger != nil)
  }

  @Test func otherInstallationScheduleIsNeverReplayed() async {
    let rig = Rig(installation: "new")
    rig.store.value = ReminderRecord(
      installation: "old", departure: rig.clock, trigger: rig.clock.addingTimeInterval(1))
    rig.coordinator.update(observation: .present, canPrompt: true)
    await settle()
    #expect(rig.scheduler.cancels == 1)
    #expect(rig.store.value?.installation == "new")
    #expect(rig.store.value?.departure == nil)
    #expect(rig.scheduler.scheduled.isEmpty)
  }
}
