import Foundation
import Observation
import SwiftData

enum AppTab: String, Hashable {
    case fleet
    case capture
    case actions
    case settings
}

enum CaptureDestination: String, CaseIterable, Identifiable {
    case brain = "Brain"
    case dailyLog = "Daily Log"

    var id: String { rawValue }
    var icon: String { self == .brain ? "brain.head.profile" : "book.pages" }
}

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .fleet
    var captureDestination: CaptureDestination = .brain
    private(set) var dailyLogReminderEnabled: Bool
    private(set) var dailyLogReminderMinutes: Int
    private(set) var dailyLogReminderAuthorization: DailyLogReminderAuthorization = .unknown
    var selectedInstanceID: UUID? {
        didSet {
            if let selectedInstanceID {
                defaults.set(selectedInstanceID.uuidString, forKey: Self.selectedInstanceKey)
            } else {
                defaults.removeObject(forKey: Self.selectedInstanceKey)
            }
        }
    }

    let api: PortOSAPIClient
    let credentials: any CredentialStore
    let isOfflineDemo: Bool
    private(set) var iCloudSyncEnabled: Bool
    private let fleetSyncCoordinator: FleetSyncCoordinator
    private let dailyLogReminders: any DailyLogReminderScheduling
    private let defaults: UserDefaults
    private static let selectedInstanceKey = "selectedPortOSInstanceID"
    private static let dailyLogReminderEnabledKey = "dailyLogReminderEnabled"
    private static let dailyLogReminderMinutesKey = "dailyLogReminderMinutes"
    private static let defaultDailyLogReminderMinutes = 22 * 60
    nonisolated static let iCloudSyncKey = "iCloudFleetAndPasswordSyncEnabled"

    init(
        api: PortOSAPIClient = PortOSAPIClient(),
        credentials: any CredentialStore = KeychainCredentialStore(),
        fleetSyncStore: any FleetSyncStore = ICloudFleetSyncStore(),
        dailyLogReminders: (any DailyLogReminderScheduling)? = nil,
        defaults: UserDefaults = .standard,
        isOfflineDemo: Bool = false
    ) {
        self.api = api
        self.credentials = credentials
        self.defaults = defaults
        self.isOfflineDemo = isOfflineDemo
        self.dailyLogReminders = dailyLogReminders ?? DailyLogReminderScheduler()
        iCloudSyncEnabled = defaults.bool(forKey: Self.iCloudSyncKey)
        dailyLogReminderEnabled = defaults.bool(forKey: Self.dailyLogReminderEnabledKey)
        dailyLogReminderMinutes = defaults.object(forKey: Self.dailyLogReminderMinutesKey) == nil
            ? Self.defaultDailyLogReminderMinutes
            : defaults.integer(forKey: Self.dailyLogReminderMinutesKey)
        fleetSyncCoordinator = FleetSyncCoordinator(store: fleetSyncStore, credentials: credentials)
        if let value = defaults.string(forKey: Self.selectedInstanceKey) {
            selectedInstanceID = UUID(uuidString: value)
        }
    }

    func select(_ instance: PortOSInstance) {
        selectedInstanceID = instance.localID
    }

    var dailyLogReminderTime: Date {
        Calendar.current.date(
            byAdding: .minute,
            value: dailyLogReminderMinutes,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
    }

    func setDailyLogReminderEnabled(_ enabled: Bool) async throws {
        if enabled {
            do {
                try await dailyLogReminders.scheduleDailyReminder(at: dailyLogReminderTime)
                dailyLogReminderAuthorization = .allowed
            } catch {
                dailyLogReminderAuthorization = await dailyLogReminders.authorizationStatus()
                throw error
            }
        } else {
            dailyLogReminders.removeDailyReminder()
        }
        dailyLogReminderEnabled = enabled
        defaults.set(enabled, forKey: Self.dailyLogReminderEnabledKey)
    }

    func setDailyLogReminderTime(_ time: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        dailyLogReminderMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        defaults.set(dailyLogReminderMinutes, forKey: Self.dailyLogReminderMinutesKey)
    }

    func rescheduleDailyLogReminder() async throws {
        guard dailyLogReminderEnabled else { return }
        try await dailyLogReminders.scheduleDailyReminder(at: dailyLogReminderTime)
        dailyLogReminderAuthorization = .allowed
    }

    func refreshDailyLogReminderAuthorization() async {
        dailyLogReminderAuthorization = await dailyLogReminders.authorizationStatus()
    }

    func openDailyLogCapture() {
        captureDestination = .dailyLog
        selectedTab = .capture
    }

    func setICloudSyncEnabled(_ enabled: Bool, modelContext: ModelContext) throws -> FleetSyncSummary {
        let instances = try modelContext.fetch(FetchDescriptor<PortOSInstance>())
        try credentials.migratePasswords(for: instances.map(\.localID), toICloud: enabled)

        let previous = iCloudSyncEnabled
        iCloudSyncEnabled = enabled
        defaults.set(enabled, forKey: Self.iCloudSyncKey)
        guard enabled else { return .noChanges }

        do {
            let result = try fleetSyncCoordinator.synchronize(modelContext: modelContext)
            try reconcileSelectedInstance(modelContext: modelContext)
            return result
        } catch {
            iCloudSyncEnabled = previous
            defaults.set(previous, forKey: Self.iCloudSyncKey)
            throw error
        }
    }

    func synchronizeFleet(modelContext: ModelContext) throws -> FleetSyncSummary {
        guard iCloudSyncEnabled else { return .noChanges }
        let result = try fleetSyncCoordinator.synchronize(modelContext: modelContext)
        try reconcileSelectedInstance(modelContext: modelContext)
        return result
    }

    func recordFleetDeletion(_ instance: PortOSInstance) throws {
        guard iCloudSyncEnabled else { return }
        try fleetSyncCoordinator.recordDeletion(instance)
    }

    private func reconcileSelectedInstance(modelContext: ModelContext) throws {
        let instances = try modelContext.fetch(FetchDescriptor<PortOSInstance>())
        guard let selectedInstanceID else {
            self.selectedInstanceID = instances.first?.localID
            return
        }
        if !instances.contains(where: { $0.localID == selectedInstanceID }) {
            self.selectedInstanceID = instances.first?.localID
        }
    }

    func handle(url: URL) {
        let destination = url.host ?? url.pathComponents.dropFirst().first
        switch destination {
        case "capture":
            if url.pathComponents.contains("daily-log") {
                captureDestination = .dailyLog
            }
            selectedTab = .capture
        case "actions": selectedTab = .actions
        case "settings": selectedTab = .settings
        default: selectedTab = .fleet
        }
    }
}
