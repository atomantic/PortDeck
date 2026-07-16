import Foundation
import Observation
import SwiftData

enum AppTab: String, Hashable {
    case fleet
    case capture
    case actions
    case settings
}

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .fleet
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
    private(set) var iCloudSyncEnabled: Bool
    private let fleetSyncCoordinator: FleetSyncCoordinator
    private let defaults: UserDefaults
    private static let selectedInstanceKey = "selectedPortOSInstanceID"
    nonisolated static let iCloudSyncKey = "iCloudFleetAndPasswordSyncEnabled"

    init(
        api: PortOSAPIClient = PortOSAPIClient(),
        credentials: any CredentialStore = KeychainCredentialStore(),
        fleetSyncStore: any FleetSyncStore = ICloudFleetSyncStore(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.credentials = credentials
        self.defaults = defaults
        iCloudSyncEnabled = defaults.bool(forKey: Self.iCloudSyncKey)
        fleetSyncCoordinator = FleetSyncCoordinator(store: fleetSyncStore, credentials: credentials)
        if let value = defaults.string(forKey: Self.selectedInstanceKey) {
            selectedInstanceID = UUID(uuidString: value)
        }
    }

    func select(_ instance: PortOSInstance) {
        selectedInstanceID = instance.localID
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
        case "capture": selectedTab = .capture
        case "actions": selectedTab = .actions
        case "settings": selectedTab = .settings
        default: selectedTab = .fleet
        }
    }
}
