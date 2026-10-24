#if DEBUG
import Foundation
import SwiftData

/// UI-test-only dependencies. No Keychain, cloud, network, or shared defaults access.
@MainActor
enum FleetRemovalFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-fleet-removal-test")
    }

    static func makeState() -> AppState {
        let suiteName = "net.shadowpuppet.PortDeck.fleet-removal-test"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: AppState.iCloudSyncKey)
        let state = AppState(
            api: PortOSAPIClient(transport: DemoHTTPTransport()),
            credentials: DemoCredentialStore(),
            fleetSyncStore: RemovalFixtureStore(
                failFirstDeletion: ProcessInfo.processInfo.arguments.contains("-fail-first-removal")
            ),
            defaults: defaults,
            isOfflineDemo: true
        )
        state.selectedInstanceID = DemoData.primaryInstanceID
        return state
    }
}

private final class RemovalFixtureStore: FleetSyncStore, @unchecked Sendable {
    private var profiles: [SyncedInstanceProfile] = []
    private var failFirstDeletion: Bool

    init(failFirstDeletion: Bool) { self.failFirstDeletion = failFirstDeletion }
    func loadProfiles() throws -> [SyncedInstanceProfile] { profiles }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws {
        if failFirstDeletion && profiles.contains(where: \.isDeleted) {
            failFirstDeletion = false
            throw NSError(domain: "FleetRemovalFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cloud removal is temporarily unavailable."])
        }
        self.profiles = profiles
    }
}
#endif
