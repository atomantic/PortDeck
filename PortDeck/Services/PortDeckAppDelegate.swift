import UIKit
import UserNotifications

final class PortDeckAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private weak var appState: AppState?
    private var shouldOpenDailyLogWhenConnected = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    @MainActor
    func connect(to appState: AppState) {
        self.appState = appState
        if shouldOpenDailyLogWhenConnected {
            shouldOpenDailyLogWhenConnected = false
            appState.openDailyLogCapture()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard Self.isDailyLogReminder(response.notification.request) else { return }
        await MainActor.run {
            if let appState {
                appState.openDailyLogCapture()
            } else {
                shouldOpenDailyLogWhenConnected = true
            }
        }
    }

    private static func isDailyLogReminder(_ request: UNNotificationRequest) -> Bool {
        request.identifier == DailyLogReminderScheduler.notificationIdentifier
            || request.content.userInfo[DailyLogReminderScheduler.destinationKey] as? String
                == DailyLogReminderScheduler.dailyLogDestination
    }
}
