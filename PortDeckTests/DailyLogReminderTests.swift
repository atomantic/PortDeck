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

        try await state.setDailyLogReminderTime(newTime)

        let components = Calendar.current.dateComponents([.hour, .minute], from: try XCTUnwrap(scheduler.scheduledTimes.last))
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute, 45)
        XCTAssertEqual(defaults.integer(forKey: "dailyLogReminderMinutes"), 19 * 60 + 45)
    }

    func testReminderKeepsWallClockTimeAcrossDaylightSavingTransitions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day) in [(3, 8), (11, 1)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
            for minutes in [22 * 60 + 15, 2 * 60 + 30] {
                let time = AppState.reminderTime(minutes: minutes, on: date, calendar: calendar)
                let request = DailyLogReminderScheduler.notificationRequest(at: time, calendar: calendar)
                let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)

                XCTAssertEqual(trigger.dateComponents.hour, minutes / 60)
                XCTAssertEqual(trigger.dateComponents.minute, minutes % 60)
            }
        }
    }

    func testFailedTimeChangePreservesPreviouslyScheduledTime() async throws {
        let (state, scheduler, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        try await state.setDailyLogReminderEnabled(true)
        scheduler.scheduleError = DailyLogReminderError.notificationsDisabled
        scheduler.authorization = .denied
        let newTime = try XCTUnwrap(Calendar.current.date(bySettingHour: 19, minute: 45, second: 0, of: Date()))

        do {
            try await state.setDailyLogReminderTime(newTime)
            XCTFail("Expected scheduling error")
        } catch {
            XCTAssertEqual(state.dailyLogReminderMinutes, 22 * 60)
            XCTAssertNil(defaults.object(forKey: "dailyLogReminderMinutes"))
            XCTAssertEqual(scheduler.scheduledTimes.count, 1)
            XCTAssertEqual(state.dailyLogReminderAuthorization, .denied)
        }
    }

    func testDisablingDuringTimeChangeLeavesNoPendingNotification() async throws {
        let (state, scheduler, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        try await state.setDailyLogReminderEnabled(true)
        let scheduleStarted = expectation(description: "Time change reached notification scheduler")
        scheduler.suspendNextSchedule = scheduleStarted
        let newTime = try XCTUnwrap(Calendar.current.date(bySettingHour: 19, minute: 45, second: 0, of: Date()))
        let update = Task { try await state.setDailyLogReminderTime(newTime) }
        await fulfillment(of: [scheduleStarted], timeout: 2)

        let disableStarted = expectation(description: "Disable requested while scheduler is suspended")
        let disable = Task {
            disableStarted.fulfill()
            try await state.setDailyLogReminderEnabled(false)
        }
        await fulfillment(of: [disableStarted], timeout: 2)
        scheduler.resumeSchedule()
        try await update.value
        try await disable.value

        XCTAssertFalse(state.dailyLogReminderEnabled)
        XCTAssertNil(scheduler.pendingTime)
        XCTAssertEqual(scheduler.removeCallCount, 1)
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

    func testOpeningDailyLogResetsPreviousLogDateAndPreservesTasksRoute() throws {
        let (state, _, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        state.dailyLogCaptureDate = .distantPast

        state.openDailyLogCapture()

        XCTAssertTrue(Calendar.current.isDateInToday(state.dailyLogCaptureDate))
        state.handle(url: try XCTUnwrap(URL(string: "portdeck://tasks")))
        XCTAssertEqual(state.selectedTab, .tasks)
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
    var suspendNextSchedule: XCTestExpectation?
    private(set) var scheduledTimes: [Date] = []
    private(set) var removeCallCount = 0
    private(set) var pendingTime: Date?
    private var scheduleContinuation: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> DailyLogReminderAuthorization { authorization }

    func scheduleDailyReminder(at time: Date) async throws {
        if let scheduleError { throw scheduleError }
        if let started = suspendNextSchedule {
            suspendNextSchedule = nil
            await withCheckedContinuation { continuation in
                scheduleContinuation = continuation
                started.fulfill()
            }
        }
        scheduledTimes.append(time)
        pendingTime = time
    }

    func resumeSchedule() {
        scheduleContinuation?.resume()
        scheduleContinuation = nil
    }

    func removeDailyReminder() {
        removeCallCount += 1
        pendingTime = nil
    }
}
