import Foundation
import UserNotifications

enum DailyLogReminderAuthorization: Equatable {
    case unknown
    case notDetermined
    case allowed
    case denied
}

enum DailyLogReminderError: LocalizedError {
    case notificationsDisabled

    var errorDescription: String? {
        switch self {
        case .notificationsDisabled:
            "Notifications are disabled for PortOS. Enable them in Settings to receive Daily Log reminders."
        }
    }
}

@MainActor
protocol DailyLogReminderScheduling {
    func authorizationStatus() async -> DailyLogReminderAuthorization
    func scheduleDailyReminder(at time: Date) async throws
    func removeDailyReminder()
}

final class DailyLogReminderScheduler: DailyLogReminderScheduling {
    static let notificationIdentifier = "daily-log-reminder"
    static let destinationKey = "portdeck-destination"
    static let dailyLogDestination = "daily-log"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> DailyLogReminderAuthorization {
        let settings = await center.notificationSettings()
        return Self.authorization(from: settings.authorizationStatus)
    }

    func scheduleDailyReminder(at time: Date) async throws {
        var authorization = await authorizationStatus()
        if authorization == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorization = granted ? .allowed : .denied
        }
        guard authorization == .allowed else {
            throw DailyLogReminderError.notificationsDisabled
        }

        try await center.add(Self.notificationRequest(at: time))
    }

    func removeDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }

    static func notificationRequest(at time: Date, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time for your Daily Log"
        content.body = "Capture what happened today in PortOS."
        content.sound = .default
        content.userInfo = [destinationKey: dailyLogDestination]

        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)
        return UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )
    }

    private static func authorization(from status: UNAuthorizationStatus) -> DailyLogReminderAuthorization {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .allowed
        @unknown default:
            .denied
        }
    }
}
