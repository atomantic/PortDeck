import SwiftData
import XCTest
@testable import PortDeck

@MainActor
final class FleetRemovalTests: XCTestCase {
    func testSyncedRemovalPublishesBeforeCredentialAndSaveAndCannotReturn() throws {
        let fixture = try Fixture()
        try fixture.remove()

        XCTAssertEqual(fixture.events.values, ["cloud", "credential", "save"])
        XCTAssertTrue(try fixture.rows().isEmpty)
        XCTAssertTrue(try XCTUnwrap(fixture.cloud.profiles.first).isDeleted)
        XCTAssertNil(fixture.credentials.value)
        XCTAssertNil(fixture.state.selectedInstanceID)
        _ = try fixture.state.synchronizeFleet(modelContext: fixture.context)
        XCTAssertTrue(try fixture.rows().isEmpty)
    }

    func testTombstoneFailurePreservesRowSelectionAndCredentialThenRetryFinishes() throws {
        let fixture = try Fixture()
        fixture.cloud.failure = .cloud
        XCTAssertThrowsError(try fixture.remove()) { XCTAssertEqual($0 as? Failure, .cloud) }
        XCTAssertEqual(fixture.events.values, ["cloud"])
        XCTAssertEqual(try fixture.rows().map(\.localID), [fixture.instance.localID])
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertEqual(fixture.credentials.value, "fixture-password")
        XCTAssertFalse(try XCTUnwrap(fixture.cloud.profiles.first).isDeleted)

        fixture.cloud.failure = nil
        try fixture.remove()
        _ = try fixture.state.synchronizeFleet(modelContext: fixture.context)
        XCTAssertTrue(try fixture.rows().isEmpty)
    }

    func testCloudReadFailurePreventsAllLaterSideEffects() throws {
        let fixture = try Fixture()
        fixture.cloud.loadFailure = true
        XCTAssertThrowsError(try fixture.remove())
        XCTAssertTrue(fixture.events.values.isEmpty)
        XCTAssertEqual(try fixture.rows().count, 1)
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertEqual(fixture.credentials.value, "fixture-password")
    }

    func testCredentialFailureRetainsRowAndSelectionAndPublishedTombstoneCanBeRetried() throws {
        let fixture = try Fixture()
        fixture.credentials.failure = .credential
        XCTAssertThrowsError(try fixture.remove()) { XCTAssertEqual($0 as? Failure, .credential) }
        XCTAssertEqual(fixture.events.values, ["cloud", "credential"])
        XCTAssertEqual(try fixture.rows().count, 1)
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertTrue(try XCTUnwrap(fixture.cloud.profiles.first).isDeleted)

        fixture.credentials.failure = nil
        try fixture.remove()
        XCTAssertTrue(try fixture.rows().isEmpty)
        XCTAssertNil(fixture.state.selectedInstanceID)
    }

    func testDeletionSaveFailureRollsBackRowAndKeepsSelectionUntilRetry() throws {
        let fixture = try Fixture()
        fixture.events.failSave = true
        fixture.instance.localLabel = "Pending edit"
        XCTAssertThrowsError(try fixture.remove()) { XCTAssertEqual($0 as? Failure, .save) }
        XCTAssertEqual(fixture.events.values, ["cloud", "credential", "save"])
        XCTAssertEqual(try fixture.rows().map(\.localID), [fixture.instance.localID])
        XCTAssertEqual(fixture.instance.localLabel, "Pending edit")
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertFalse(fixture.instance.isDeleted)
        XCTAssertNil(fixture.credentials.value)

        fixture.events.failSave = false
        try fixture.remove()
        XCTAssertTrue(try fixture.rows().isEmpty)
        XCTAssertNil(fixture.state.selectedInstanceID)
    }

    func testLocalOnlyRemovalDoesNotReadOrWriteCloud() throws {
        let fixture = try Fixture(sync: false)
        fixture.cloud.loadFailure = true
        try fixture.remove()
        XCTAssertEqual(fixture.events.values, ["credential", "save"])
        XCTAssertFalse(try XCTUnwrap(fixture.cloud.profiles.first).isDeleted)
        XCTAssertTrue(try fixture.rows().isEmpty)
    }

    func testRemovalSelectsRemainingRowAndPreservesOtherSelection() throws {
        let fixture = try Fixture()
        let other = PortOSInstance(syncedProfile: SyncedInstanceProfile(instance: fixture.instance))
        other.localID = UUID()
        fixture.context.insert(other)
        try fixture.context.save()
        try fixture.remove()
        XCTAssertEqual(fixture.state.selectedInstanceID, other.localID)

        let unselected = PortOSInstance(syncedProfile: SyncedInstanceProfile(instance: other))
        unselected.localID = UUID()
        fixture.context.insert(unselected)
        try fixture.context.save()
        try fixture.state.removeFleetInstance(unselected, modelContext: fixture.context)
        XCTAssertEqual(fixture.state.selectedInstanceID, other.localID)
    }
}

private enum Failure: Error { case cloud, credential, save }
private final class Events {
    var values: [String] = []
    var failSave = false
}

@MainActor
private final class Fixture {
    let context: ModelContext
    let instance: PortOSInstance
    let events = Events()
    let cloud: RemovalCloudStore
    let credentials: RemovalCredentialStore
    let state: AppState
    let suiteName = "FleetRemovalTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init(sync: Bool = true) throws {
        let container = try ModelContainer(for: PortOSInstance.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        context.autosaveEnabled = false
        instance = PortOSInstance(baseURL: URL(string: "https://fixture.example")!, localLabel: "Fixture",
            health: PortOSHealth(status: "ok", version: "1", hostname: "fixture", instanceID: "fixture",
                                name: "Fixture", authRequired: true, scheme: "https"))
        context.insert(instance)
        try context.save()
        cloud = RemovalCloudStore(events: events, profiles: [SyncedInstanceProfile(instance: instance)])
        credentials = RemovalCredentialStore(events: events)
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(sync, forKey: AppState.iCloudSyncKey)
        let events = events
        state = AppState(credentials: credentials, fleetSyncStore: cloud, defaults: defaults,
            saveFleetRemoval: { context in
                events.values.append("save")
                if events.failSave { throw Failure.save }
                try context.save()
            })
        state.select(instance)
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }
    func rows() throws -> [PortOSInstance] { try context.fetch(FetchDescriptor<PortOSInstance>()) }
    func remove() throws { try state.removeFleetInstance(instance, modelContext: context) }
}

private final class RemovalCloudStore: FleetSyncStore, @unchecked Sendable {
    let events: Events
    var profiles: [SyncedInstanceProfile]
    var failure: Failure?
    var loadFailure = false
    init(events: Events, profiles: [SyncedInstanceProfile]) { self.events = events; self.profiles = profiles }
    func loadProfiles() throws -> [SyncedInstanceProfile] {
        if loadFailure { throw Failure.cloud }
        return profiles
    }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws {
        events.values.append("cloud")
        if let failure { throw failure }
        self.profiles = profiles
    }
}

private final class RemovalCredentialStore: CredentialStore, @unchecked Sendable {
    let events: Events
    var failure: Failure?
    var value: String? = "fixture-password"
    init(events: Events) { self.events = events }
    func password(for instanceID: UUID) throws -> String? { value }
    func setPassword(_ password: String, for instanceID: UUID) throws { value = password }
    func removePassword(for instanceID: UUID) throws {
        events.values.append("credential")
        if let failure { throw failure }
        value = nil
    }
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {}
}
