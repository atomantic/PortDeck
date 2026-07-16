import SwiftData
import XCTest
@testable import PortDeck

@MainActor
final class FleetSyncCoordinatorTests: XCTestCase {
    func testImportsRemoteFleetProfile() throws {
        let context = try makeContext()
        let remote = makeInstance(label: "Studio", updatedAt: Date(timeIntervalSince1970: 200))
        let store = FakeFleetSyncStore(profiles: [SyncedInstanceProfile(instance: remote)])
        let credentials = FakeCredentialStore()

        let result = try FleetSyncCoordinator(store: store, credentials: credentials)
            .synchronize(modelContext: context)

        let instances = try context.fetch(FetchDescriptor<PortOSInstance>())
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances.first?.localLabel, "Studio")
        XCTAssertEqual(result, FleetSyncSummary(imported: 1, updated: 0, deleted: 0))
    }

    func testNewerRemoteProfileUpdatesLocalProfile() throws {
        let context = try makeContext()
        let localID = UUID()
        let local = makeInstance(
            localID: localID,
            label: "Old label",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(local)
        try context.save()

        let remote = makeInstance(
            localID: localID,
            label: "New label",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let store = FakeFleetSyncStore(profiles: [SyncedInstanceProfile(instance: remote)])

        let result = try FleetSyncCoordinator(store: store, credentials: FakeCredentialStore())
            .synchronize(modelContext: context)

        XCTAssertEqual(local.localLabel, "New label")
        XCTAssertEqual(result, FleetSyncSummary(imported: 0, updated: 1, deleted: 0))
    }

    func testNewerRemoteTombstoneDeletesLocalProfileAndCredential() throws {
        let context = try makeContext()
        let local = makeInstance(label: "Studio", updatedAt: Date(timeIntervalSince1970: 100))
        context.insert(local)
        try context.save()

        let deletedAt = Date(timeIntervalSince1970: 200)
        let tombstone = SyncedInstanceProfile(instance: local, deletedAt: deletedAt)
        let credentials = FakeCredentialStore()
        let store = FakeFleetSyncStore(profiles: [tombstone])

        let result = try FleetSyncCoordinator(store: store, credentials: credentials)
            .synchronize(modelContext: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<PortOSInstance>()).isEmpty)
        XCTAssertEqual(credentials.removedInstanceIDs, [local.localID])
        XCTAssertEqual(result, FleetSyncSummary(imported: 0, updated: 0, deleted: 1))
    }

    func testNewerLocalProfileWinsAndIsUploaded() throws {
        let context = try makeContext()
        let localID = UUID()
        let local = makeInstance(
            localID: localID,
            label: "Phone edit",
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        context.insert(local)
        try context.save()

        let remote = makeInstance(
            localID: localID,
            label: "Older cloud edit",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let store = FakeFleetSyncStore(profiles: [SyncedInstanceProfile(instance: remote)])

        let result = try FleetSyncCoordinator(store: store, credentials: FakeCredentialStore())
            .synchronize(modelContext: context)

        XCTAssertEqual(result, .noChanges)
        XCTAssertEqual(store.profiles.first?.localLabel, "Phone edit")
        XCTAssertEqual(local.localLabel, "Phone edit")
    }

    func testICloudOptInMigratesPasswordsAndUploadsFleet() throws {
        let context = try makeContext()
        let instance = makeInstance(label: "Studio", updatedAt: Date(timeIntervalSince1970: 200))
        context.insert(instance)
        try context.save()
        let credentials = FakeCredentialStore()
        let store = FakeFleetSyncStore(profiles: [])
        let suiteName = "FleetSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            credentials: credentials,
            fleetSyncStore: store,
            defaults: defaults
        )

        _ = try appState.setICloudSyncEnabled(true, modelContext: context)

        XCTAssertTrue(appState.iCloudSyncEnabled)
        XCTAssertEqual(credentials.migrations, [.init(instanceIDs: [instance.localID], toICloud: true)])
        XCTAssertEqual(store.profiles.map(\.localID), [instance.localID])
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PortOSInstance.self, configurations: configuration)
        return ModelContext(container)
    }

    private func makeInstance(
        localID: UUID = UUID(),
        label: String,
        updatedAt: Date
    ) -> PortOSInstance {
        let instance = PortOSInstance(
            localID: localID,
            baseURL: URL(string: "https://studio.example.ts.net:5555")!,
            localLabel: label,
            health: PortOSHealth(
                status: "ok",
                version: "1.2.3",
                hostname: "studio",
                instanceID: "instance-1",
                name: "Studio",
                authRequired: true,
                scheme: "https"
            ),
            addedAt: Date(timeIntervalSince1970: 50)
        )
        instance.syncUpdatedAt = updatedAt
        return instance
    }

}

private final class FakeFleetSyncStore: FleetSyncStore, @unchecked Sendable {
    var profiles: [SyncedInstanceProfile]

    init(profiles: [SyncedInstanceProfile]) {
        self.profiles = profiles
    }

    func loadProfiles() throws -> [SyncedInstanceProfile] { profiles }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws { self.profiles = profiles }
}

private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
    struct Migration: Equatable {
        let instanceIDs: [UUID]
        let toICloud: Bool
    }

    private(set) var removedInstanceIDs: [UUID] = []
    private(set) var migrations: [Migration] = []

    func password(for instanceID: UUID) throws -> String? { nil }
    func setPassword(_ password: String, for instanceID: UUID) throws {}
    func removePassword(for instanceID: UUID) throws { removedInstanceIDs.append(instanceID) }
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {
        migrations.append(Migration(instanceIDs: instanceIDs, toICloud: toICloud))
    }
}
