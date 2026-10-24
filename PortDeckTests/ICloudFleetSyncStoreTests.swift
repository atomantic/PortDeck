import Security
import SwiftData
import XCTest
@testable import PortDeck

@MainActor
final class ICloudFleetSyncStoreTests: XCTestCase {
    private let service = "ICloudFleetSyncStoreTests"

    func testSaveLoadPreservesExactConflictDatesWithinAMillisecond() throws {
        let keychain = InMemoryKeychainItemClient()
        let store = makeStore(keychain)
        let dates = [800_000_100.4001, 800_000_100.4002, 800_000_100.9001]
            .map(Date.init(timeIntervalSinceReferenceDate:))
        let profiles = dates.map { date in
            SyncedInstanceProfile(instance: makeInstance(updatedAt: date), deletedAt: date.addingTimeInterval(0.0001))
        } + [SyncedInstanceProfile(instance: makeInstance(updatedAt: dates[0]))]

        try store.saveProfiles(profiles)
        let loaded = try store.loadProfiles()

        XCTAssertEqual(loaded.count, profiles.count)
        for profile in profiles {
            let actual = try XCTUnwrap(loaded.first { $0.localID == profile.localID })
            XCTAssertEqual(actual.updatedAt, profile.updatedAt)
            XCTAssertEqual(actual.deletedAt, profile.deletedAt)
            let bytes = try XCTUnwrap(keychain.data(account: profile.localID.uuidString))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(json["updatedAtReferenceTime"] as? Double, profile.updatedAt.timeIntervalSinceReferenceDate)
            XCTAssertTrue(json["updatedAt"] is String)
            if profile.deletedAt == nil {
                XCTAssertNil(json["deletedAt"])
                XCTAssertNil(json["deletedAtReferenceTime"])
            }
        }
        XCTAssertNotEqual(loaded.first { $0.localID == profiles[0].localID }?.updatedAt,
                          loaded.first { $0.localID == profiles[1].localID }?.updatedAt)
    }

    func testPersistedNewerSameSecondEditWinsAcrossRepeatedSyncs() throws {
        let context = try makeContext()
        let local = makeInstance(updatedAt: Date(timeIntervalSince1970: 100.4), label: "Earlier local")
        context.insert(local)
        try context.save()
        let remote = makeInstance(localID: local.localID, updatedAt: Date(timeIntervalSince1970: 100.9), label: "Later remote")
        let store = makeStore(InMemoryKeychainItemClient())
        try store.saveProfiles([SyncedInstanceProfile(instance: remote)])
        let coordinator = FleetSyncCoordinator(store: store, credentials: TrackingCredentials())

        XCTAssertEqual(try coordinator.synchronize(modelContext: context), .init(imported: 0, updated: 1, deleted: 0))
        XCTAssertEqual(local.localLabel, "Later remote")
        XCTAssertEqual(local.syncUpdatedAt, remote.syncUpdatedAt)
        XCTAssertEqual(try coordinator.synchronize(modelContext: context), .noChanges)
        XCTAssertEqual(try store.loadProfiles().first?.localLabel, "Later remote")
        XCTAssertEqual(try store.loadProfiles().first?.updatedAt, remote.syncUpdatedAt)
    }

    func testPersistedNewerSameSecondTombstoneDeletesCredentialAndStaysDeleted() throws {
        let context = try makeContext()
        let local = makeInstance(updatedAt: Date(timeIntervalSince1970: 100.4))
        let localID = local.localID
        context.insert(local)
        try context.save()
        let deletedAt = Date(timeIntervalSince1970: 100.9)
        let store = makeStore(InMemoryKeychainItemClient())
        try store.saveProfiles([SyncedInstanceProfile(instance: local, deletedAt: deletedAt)])
        let credentials = TrackingCredentials()
        credentials.passwords[localID] = "secret"
        let coordinator = FleetSyncCoordinator(store: store, credentials: credentials)

        XCTAssertEqual(try coordinator.synchronize(modelContext: context), .init(imported: 0, updated: 0, deleted: 1))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PortOSInstance>()).isEmpty)
        XCTAssertNil(credentials.passwords[localID])
        XCTAssertEqual(credentials.removedInstanceIDs, [localID])
        XCTAssertEqual(try coordinator.synchronize(modelContext: context), .noChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PortOSInstance>()).isEmpty)
        XCTAssertEqual(try store.loadProfiles().first?.deletedAt, deletedAt)
        XCTAssertEqual(credentials.removedInstanceIDs, [localID])
    }

    func testOldPerProfileAndLegacyArrayFixturesLoadAndMigrate() throws {
        let keychain = InMemoryKeychainItemClient()
        let firstID = "00000000-0000-0000-0000-000000000001"
        let secondID = "00000000-0000-0000-0000-000000000002"
        let oldProfile = legacyJSON(id: firstID)
        let oldTombstone = legacyJSON(id: secondID, deletedAt: "\"2001-01-01T00:00:20Z\"")
        keychain.seed(service: service, account: firstID, data: Data(oldProfile.utf8))
        keychain.seed(service: service, account: "fleet-index-v1", data: Data("[\(oldProfile),\(oldTombstone)]".utf8))
        let store = makeStore(keychain)

        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.count, 2)
        let live = try XCTUnwrap(profiles.first { $0.localID.uuidString == firstID })
        let deleted = try XCTUnwrap(profiles.first { $0.localID.uuidString == secondID })
        XCTAssertEqual(live.updatedAt, Date(timeIntervalSinceReferenceDate: 10))
        XCTAssertNil(live.deletedAt)
        XCTAssertEqual(deleted.deletedAt, Date(timeIntervalSinceReferenceDate: 20))
        try store.saveProfiles(profiles)

        XCTAssertNil(keychain.data(account: "fleet-index-v1"))
        XCTAssertNotNil(keychain.data(account: firstID))
        XCTAssertNotNil(keychain.data(account: secondID))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: try store.loadProfiles().map { ($0.localID, $0) }),
                       Dictionary(uniqueKeysWithValues: profiles.map { ($0.localID, $0) }))
        for profile in profiles {
            let data = try XCTUnwrap(keychain.data(account: profile.localID.uuidString))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["updatedAtReferenceTime"] as? Double, 10)
        }
    }

    func testOldDecoderCanReadNewLiveAndDeletedRecords() throws {
        let keychain = InMemoryKeychainItemClient()
        let store = makeStore(keychain)
        let instance = makeInstance(updatedAt: Date(timeIntervalSinceReferenceDate: 10.9))
        let tombstoneInstance = makeInstance(updatedAt: Date(timeIntervalSinceReferenceDate: 11.9))
        let profiles = [SyncedInstanceProfile(instance: instance),
                        SyncedInstanceProfile(instance: tombstoneInstance, deletedAt: Date(timeIntervalSinceReferenceDate: 20.9))]
        try store.saveProfiles(profiles)
        let oldDecoder = JSONDecoder()
        oldDecoder.dateDecodingStrategy = .iso8601

        for profile in profiles {
            let data = try XCTUnwrap(keychain.data(account: profile.localID.uuidString))
            let old = try oldDecoder.decode(LegacyProfile.self, from: data)
            XCTAssertEqual(old.localID, profile.localID)
            XCTAssertEqual(old.baseURLString, profile.baseURLString)
            XCTAssertEqual(old.localLabel, profile.localLabel)
            XCTAssertEqual(old.instanceID, profile.instanceID)
            XCTAssertEqual(old.remoteName, profile.remoteName)
            XCTAssertEqual(old.hostname, profile.hostname)
            XCTAssertEqual(old.version, profile.version)
            XCTAssertEqual(old.authRequired, profile.authRequired)
            XCTAssertEqual(old.addedAt, profile.addedAt)
            XCTAssertEqual(old.updatedAt.timeIntervalSinceReferenceDate, floor(profile.updatedAt.timeIntervalSinceReferenceDate))
            XCTAssertEqual(old.deletedAt?.timeIntervalSinceReferenceDate, profile.deletedAt.map { floor($0.timeIntervalSinceReferenceDate) })
        }
    }

    private func makeStore(_ keychain: InMemoryKeychainItemClient) -> ICloudFleetSyncStore {
        ICloudFleetSyncStore(service: service, keychain: keychain)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: PortOSInstance.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeInstance(localID: UUID = UUID(), updatedAt: Date, label: String = "Studio") -> PortOSInstance {
        let instance = PortOSInstance(localID: localID, baseURL: URL(string: "https://studio.example.ts.net:5555")!,
                                     localLabel: label,
                                     health: PortOSHealth(status: "ok", version: "1.2.3", hostname: "studio",
                                                          instanceID: "instance-1", name: "Studio", authRequired: true, scheme: "https"),
                                     addedAt: Date(timeIntervalSinceReferenceDate: 0))
        instance.syncUpdatedAt = updatedAt
        return instance
    }

    private func legacyJSON(id: String, deletedAt: String = "null") -> String {
        """
        {"localID":"\(id)","baseURLString":"https://studio.example.ts.net:5555","localLabel":"Studio",
         "instanceID":"instance-1","remoteName":"Studio","hostname":"studio","version":"1.2.3",
         "authRequired":true,"addedAt":"2001-01-01T00:00:00Z","updatedAt":"2001-01-01T00:00:10Z","deletedAt":\(deletedAt)}
        """
    }
}

/// Frozen pre-precision schema: extra keys in new records must remain ignorable.
private struct LegacyProfile: Decodable {
    let localID: UUID
    let baseURLString: String
    let localLabel: String
    let instanceID: String?
    let remoteName: String
    let hostname: String
    let version: String?
    let authRequired: Bool
    let addedAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

private final class TrackingCredentials: CredentialStore, @unchecked Sendable {
    var passwords: [UUID: String] = [:]
    var removedInstanceIDs: [UUID] = []
    func password(for instanceID: UUID) throws -> String? { passwords[instanceID] }
    func setPassword(_ password: String, for instanceID: UUID) throws { passwords[instanceID] = password }
    func removePassword(for instanceID: UUID) throws {
        passwords.removeValue(forKey: instanceID)
        removedInstanceIDs.append(instanceID)
    }
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {}
}
