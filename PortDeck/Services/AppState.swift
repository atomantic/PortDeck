import Foundation
import Observation
import SwiftData

enum AppTab: String, Hashable {
    case fleet
    case capture
    case tasks
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
    var dailyLogCaptureDate = Date()
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
    let tailcat: TailcatTunnelPool
    private(set) var iCloudSyncEnabled: Bool
    private let fleetSyncCoordinator: FleetSyncCoordinator
    private let dailyLogReminders: any DailyLogReminderScheduling
    @ObservationIgnored private var dailyLogReminderUpdateInProgress = false
    @ObservationIgnored private var dailyLogReminderUpdateWaiters: [CheckedContinuation<Void, Never>] = []
    private let saveFleetRemoval: (ModelContext) throws -> Void
    private let defaults: UserDefaults
    private static let selectedInstanceKey = "selectedPortOSInstanceID"
    private static let dailyLogReminderEnabledKey = "dailyLogReminderEnabled"
    private static let dailyLogReminderMinutesKey = "dailyLogReminderMinutes"
    private static let defaultDailyLogReminderMinutes = 22 * 60
    nonisolated static let iCloudSyncKey = "iCloudFleetAndPasswordSyncEnabled"

    init(
        api: PortOSAPIClient? = nil,
        credentials: (any CredentialStore)? = nil,
        fleetSyncStore: any FleetSyncStore = ICloudFleetSyncStore(),
        dailyLogReminders: (any DailyLogReminderScheduling)? = nil,
        defaults: UserDefaults = .standard,
        isOfflineDemo: Bool = false,
        tailcat: TailcatTunnelPool = .shared,
        saveFleetRemoval: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.saveFleetRemoval = saveFleetRemoval
        self.tailcat = tailcat
        self.api = api ?? PortOSAPIClient(transport: TailcatRoutingTransport(pool: tailcat))
        self.credentials = credentials ?? TailcatAwareCredentialStore(tailcat: tailcat.store)
        self.defaults = defaults
        self.isOfflineDemo = isOfflineDemo
        self.dailyLogReminders = dailyLogReminders ?? DailyLogReminderScheduler()
        iCloudSyncEnabled = defaults.bool(forKey: Self.iCloudSyncKey)
        dailyLogReminderEnabled = defaults.bool(forKey: Self.dailyLogReminderEnabledKey)
        dailyLogReminderMinutes = defaults.object(forKey: Self.dailyLogReminderMinutesKey) == nil
            ? Self.defaultDailyLogReminderMinutes
            : defaults.integer(forKey: Self.dailyLogReminderMinutesKey)
        fleetSyncCoordinator = FleetSyncCoordinator(store: fleetSyncStore, credentials: self.credentials)
        if let value = defaults.string(forKey: Self.selectedInstanceKey) {
            selectedInstanceID = UUID(uuidString: value)
        }
    }

    func select(_ instance: PortOSInstance) {
        selectedInstanceID = instance.localID
    }

    var dailyLogReminderTime: Date {
        Self.reminderTime(minutes: dailyLogReminderMinutes, on: Date())
    }

    static func reminderTime(minutes: Int, on date: Date, calendar: Calendar = .current) -> Date {
        // A skipped DST time must keep its hour/minute for the repeating trigger.
        calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: date,
            matchingPolicy: .strict
        ) ?? date
    }

    func setDailyLogReminderEnabled(_ enabled: Bool) async throws {
        await beginDailyLogReminderUpdate()
        defer { finishDailyLogReminderUpdate() }
        if enabled {
            try await scheduleDailyLogReminder(at: dailyLogReminderTime)
        } else {
            dailyLogReminders.removeDailyReminder()
        }
        dailyLogReminderEnabled = enabled
        defaults.set(enabled, forKey: Self.dailyLogReminderEnabledKey)
    }

    func setDailyLogReminderTime(_ time: Date) async throws {
        await beginDailyLogReminderUpdate()
        defer { finishDailyLogReminderUpdate() }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        if dailyLogReminderEnabled {
            try await scheduleDailyLogReminder(at: time)
        }
        dailyLogReminderMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        defaults.set(dailyLogReminderMinutes, forKey: Self.dailyLogReminderMinutesKey)
    }

    private func scheduleDailyLogReminder(at time: Date) async throws {
        do {
            try await dailyLogReminders.scheduleDailyReminder(at: time)
            dailyLogReminderAuthorization = .allowed
        } catch {
            dailyLogReminderAuthorization = await dailyLogReminders.authorizationStatus()
            throw error
        }
    }

    private func beginDailyLogReminderUpdate() async {
        if dailyLogReminderUpdateInProgress {
            await withCheckedContinuation { dailyLogReminderUpdateWaiters.append($0) }
        } else {
            dailyLogReminderUpdateInProgress = true
        }
    }

    private func finishDailyLogReminderUpdate() {
        if dailyLogReminderUpdateWaiters.isEmpty {
            dailyLogReminderUpdateInProgress = false
        } else {
            dailyLogReminderUpdateWaiters.removeFirst().resume()
        }
    }

    func refreshDailyLogReminderAuthorization() async {
        dailyLogReminderAuthorization = await dailyLogReminders.authorizationStatus()
    }

    func openDailyLogCapture() {
        dailyLogCaptureDate = Date()
        captureDestination = .dailyLog
        selectedTab = .capture
    }

    func setICloudSyncEnabled(_ enabled: Bool, modelContext: ModelContext) throws -> FleetSyncSummary {
        let instances = try modelContext.fetch(FetchDescriptor<PortOSInstance>())
        try credentials.migratePasswords(for: instances.filter { !$0.usesTailcat }.map(\.localID), toICloud: enabled)

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

    /// Sync-disabled removal is local-only; enabling sync later can import a remote copy.
    func removeFleetInstance(_ instance: PortOSInstance, modelContext: ModelContext) throws {
        let removedID = instance.localID
        let wasTailcat = instance.usesTailcat
        // Persist existing edits first so rollback below only undoes this deletion.
        try modelContext.save()
        let remaining = try modelContext.fetch(FetchDescriptor<PortOSInstance>())
            .filter { $0.localID != instance.localID }
        try recordFleetDeletion(instance)
        let previousPairing = wasTailcat ? try tailcat.store.connection(for: removedID) : nil
        var removedPairing = false
        do {
            if wasTailcat {
                // The password is inside this same device-only pairing item.
                try tailcat.removeSavedConnection(for: removedID)
                removedPairing = true
            } else {
                try credentials.removePassword(for: removedID)
            }
            modelContext.delete(instance)
            try saveFleetRemoval(modelContext)
        } catch {
            modelContext.rollback()
            if removedPairing, let previousPairing {
                do { try tailcat.store.setConnection(previousPairing, for: removedID) }
                catch {
                    throw TailcatError.pairingRestoreFailed
                }
            }
            throw error
        }
        if !remaining.contains(where: { $0.localID == selectedInstanceID }) {
            selectedInstanceID = remaining.first?.localID
        }
        if wasTailcat {
            Task { await tailcat.disconnect(removedID) }
        }
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
                openDailyLogCapture()
            }
            selectedTab = .capture
        case "tasks": selectedTab = .tasks
        case "actions": selectedTab = .actions
        case "settings": selectedTab = .settings
        default: selectedTab = .fleet
        }
    }
}
