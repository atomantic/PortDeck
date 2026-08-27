import UserNotifications
import XCTest
@testable import PortDeck

@MainActor
final class DailyLogReminderTests: XCTestCase {
    func testDefaultsToTenPMAndPersistsEnabledReminder() async throws {
        let (state, scheduler, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }

        let components = Calendar.current.dateComponents([.hour, .minute], from: state.dailyLogReminderTime)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 0)

        try await state.setDailyLogReminderEnabled(true)

        XCTAssertTrue(state.dailyLogReminderEnabled)
        XCTAssertEqual(scheduler.scheduledTimes.count, 1)
        XCTAssertTrue(defaults.bool(forKey: "dailyLogReminderEnabled"))
    }

    func testChangingEnabledReminderReschedulesAtNewTime() async throws {
        let (state, scheduler, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        try await state.setDailyLogReminderEnabled(true)
        let newTime = try XCTUnwrap(Calendar.current.date(bySettingHour: 19, minute: 45, second: 0, of: Date()))

        state.setDailyLogReminderTime(newTime)
        try await state.rescheduleDailyLogReminder()

        let components = Calendar.current.dateComponents([.hour, .minute], from: try XCTUnwrap(scheduler.scheduledTimes.last))
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute, 45)
        XCTAssertEqual(defaults.integer(forKey: "dailyLogReminderMinutes"), 19 * 60 + 45)
    }

    func testDeniedPermissionDoesNotEnableReminder() async throws {
        let (state, scheduler, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        scheduler.authorization = .denied
        scheduler.scheduleError = DailyLogReminderError.notificationsDisabled

        do {
            try await state.setDailyLogReminderEnabled(true)
            XCTFail("Expected notification permission error")
        } catch {
            XCTAssertFalse(state.dailyLogReminderEnabled)
            XCTAssertEqual(state.dailyLogReminderAuthorization, .denied)
        }
    }

    func testDisablingReminderRemovesScheduledRequest() async throws {
        let (state, scheduler, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        try await state.setDailyLogReminderEnabled(true)

        try await state.setDailyLogReminderEnabled(false)

        XCTAssertFalse(state.dailyLogReminderEnabled)
        XCTAssertEqual(scheduler.removeCallCount, 1)
        XCTAssertFalse(defaults.bool(forKey: "dailyLogReminderEnabled"))
    }

    func testDailyLogDeepLinkSelectsCaptureDestination() throws {
        let (state, _, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }

        state.handle(url: try XCTUnwrap(URL(string: "portdeck://capture/daily-log")))

        XCTAssertEqual(state.selectedTab, .capture)
        XCTAssertEqual(state.captureDestination, .dailyLog)
    }

    func testNotificationRequestRepeatsAtSelectedTimeAndTargetsDailyLog() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let time = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 22, minute: 15)))

        let request = DailyLogReminderScheduler.notificationRequest(at: time, calendar: calendar)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)

        XCTAssertEqual(request.identifier, DailyLogReminderScheduler.notificationIdentifier)
        XCTAssertEqual(trigger.dateComponents.hour, 22)
        XCTAssertEqual(trigger.dateComponents.minute, 15)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(
            request.content.userInfo[DailyLogReminderScheduler.destinationKey] as? String,
            DailyLogReminderScheduler.dailyLogDestination
        )
    }

    private func makeState() throws -> (AppState, FakeDailyLogReminderScheduler, UserDefaults, String) {
        let suite = "DailyLogReminderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let scheduler = FakeDailyLogReminderScheduler()
        let state = AppState(dailyLogReminders: scheduler, defaults: defaults)
        return (state, scheduler, defaults, suite)
    }
}

@MainActor
private final class FakeDailyLogReminderScheduler: DailyLogReminderScheduling {
    var authorization = DailyLogReminderAuthorization.allowed
    var scheduleError: Error?
    private(set) var scheduledTimes: [Date] = []
    private(set) var removeCallCount = 0

    func authorizationStatus() async -> DailyLogReminderAuthorization { authorization }

    func scheduleDailyReminder(at time: Date) async throws {
        if let scheduleError { throw scheduleError }
        scheduledTimes.append(time)
    }

    func removeDailyReminder() {
        removeCallCount += 1
    }
}
