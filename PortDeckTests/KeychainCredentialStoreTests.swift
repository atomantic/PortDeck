import Security
import SwiftData
import XCTest
@testable import PortDeck

final class KeychainCredentialStoreTests: XCTestCase {
    private let service = "KeychainCredentialStoreTests.\(UUID().uuidString)"

    func testDeviceOnlyInsertUpdateReadAndRemovalKeepProfilesAndServicesIsolated() throws {
        let client = InMemoryKeychainItemClient()
        let store = makeStore(client)
        let first = UUID(), second = UUID()
        client.seed(service: "unrelated", account: first.uuidString, data: Data("other service".utf8), synchronizable: false)

        try store.setPassword("first", for: first)
        try store.setPassword("second", for: second)
        try store.setPassword("updated", for: first)
        XCTAssertEqual(try store.password(for: first), "updated")
        XCTAssertEqual(try store.password(for: second), "second")
        for id in [first, second] {
            let item = try XCTUnwrap(client.attributes(service: service, account: id.uuidString, synchronizable: false))
            XCTAssertEqual(item[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            XCTAssertNil(client.attributes(service: service, account: id.uuidString, synchronizable: true))
        }
        for call in client.calls {
            XCTAssertEqual(call.query[kSecClass as String] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(call.query[kSecAttrService as String] as? String, service)
            XCTAssertNotNil(call.query[kSecAttrAccount as String])
            XCTAssertEqual(call.query[kSecAttrSynchronizable as String] as? Bool, false)
        }
        try store.removePassword(for: first)
        XCTAssertNil(try store.password(for: first))
        XCTAssertEqual(try store.password(for: second), "second")
        XCTAssertNotNil(client.attributes(service: "unrelated", account: first.uuidString, synchronizable: false))
        try store.setPassword("", for: second)
        XCTAssertNil(try store.password(for: second))
        XCTAssertNoThrow(try store.removePassword(for: first))
    }

    func testReadsPreferredNamespaceThenFallbackInBothModes() throws {
        for enabled in [false, true] {
            let client = InMemoryKeychainItemClient()
            let store = makeStore(client, enabled: enabled)
            let both = UUID(), fallback = UUID()
            seed(client, both, "local", sync: false)
            seed(client, both, "cloud", sync: true)
            seed(client, fallback, "fallback", sync: !enabled)
            XCTAssertEqual(try store.password(for: both), enabled ? "cloud" : "local")
            XCTAssertEqual(try store.password(for: fallback), "fallback")
            XCTAssertNil(try store.password(for: UUID()))
            let reads = client.calls.filter { $0.operation == .read }
            XCTAssertEqual(reads.map { $0.query[kSecAttrSynchronizable as String] as? Bool },
                           [enabled, enabled, !enabled, enabled, !enabled])
            for call in reads {
                XCTAssertEqual(call.query[kSecReturnData as String] as? Bool, true)
                XCTAssertEqual(call.query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
            }
        }
    }

    func testMalformedDataAndSecurityReadErrorsDoNotFallBackAsIfMissing() throws {
        let client = InMemoryKeychainItemClient()
        let store = makeStore(client)
        let id = UUID()
        client.seed(service: service, account: id.uuidString, data: Data([0xff]), synchronizable: false)
        seed(client, id, "cloud backup", sync: true)
        XCTAssertThrowsError(try store.password(for: id)) { error in
            guard case CredentialStoreError.invalidData = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(client.calls.count, 1)
        client.failures = [.init(operation: .read, status: errSecInteractionNotAllowed)]
        assertStatus(errSecInteractionNotAllowed) { _ = try store.password(for: id) }
        XCTAssertEqual(client.calls.count, 2)
        client.failures = [.init(operation: .read, status: errSecSuccess)] // A successful response without data is also invalid.
        XCTAssertThrowsError(try store.password(for: id)) { error in
            guard case CredentialStoreError.invalidData = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let fallback = UUID()
        seed(client, fallback, "cloud backup", sync: true)
        client.failures = [.init(operation: .read, status: errSecAuthFailed, synchronizable: true)]
        assertStatus(errSecAuthFailed) { _ = try store.password(for: fallback) }
    }

    func testOptInWritesDestinationBeforeDeletingSourceAndKeepsProfilesIsolated() throws {
        let client = InMemoryKeychainItemClient()
        let store = makeStore(client, enabled: true)
        let first = UUID(), second = UUID()
        seed(client, first, "first", sync: false)
        seed(client, second, "second", sync: false)
        try store.migratePasswords(for: [first, second, UUID()], toICloud: true)
        for (id, expected) in [(first, "first"), (second, "second")] {
            XCTAssertEqual(try store.password(for: id), expected)
            XCTAssertNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
            let cloud = try XCTUnwrap(client.attributes(service: service, account: id.uuidString, synchronizable: true))
            XCTAssertEqual(cloud[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
            let calls = client.calls.filter { $0.query[kSecAttrAccount as String] as? String == id.uuidString }
            XCTAssertEqual(calls.prefix(4).map(\.operation), [.read, .update, .add, .delete])
            XCTAssertEqual(calls.prefix(4).map { $0.query[kSecAttrSynchronizable as String] as? Bool }, [false, true, true, false])
        }
    }

    func testOptInAddOrUpdateFailurePreservesLastReadableSource() throws {
        for operation in [InMemoryKeychainItemClient.Operation.add, .update] {
            let client = InMemoryKeychainItemClient()
            let store = makeStore(client)
            let id = UUID()
            seed(client, id, "last copy", sync: false)
            client.failures = [.init(operation: operation, status: errSecAuthFailed)]
            assertStatus(errSecAuthFailed) { try store.migratePasswords(for: [id], toICloud: true) }
            XCTAssertEqual(try store.password(for: id), "last copy")
            XCTAssertNotNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
            XCTAssertFalse(client.calls.contains { $0.operation == .delete })
        }
    }

    func testOptInDeleteFailureLeavesBothCopiesReadableAndRetryRecovers() throws {
        let client = InMemoryKeychainItemClient()
        let store = makeStore(client)
        let id = UUID()
        seed(client, id, "last copy", sync: false)
        client.failures = [.init(operation: .delete, status: errSecInteractionNotAllowed)]
        assertStatus(errSecInteractionNotAllowed) { try store.migratePasswords(for: [id], toICloud: true) }
        XCTAssertEqual(try store.password(for: id), "last copy")
        XCTAssertEqual(try makeStore(client, enabled: true).password(for: id), "last copy")
        XCTAssertNotNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
        XCTAssertNotNil(client.attributes(service: service, account: id.uuidString, synchronizable: true))
        try store.migratePasswords(for: [id], toICloud: true)
        XCTAssertNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
        XCTAssertEqual(try store.password(for: id), "last copy")
    }

    func testOptOutCreatesUsableLocalCopyAndRetainsCloudCopy() throws {
        let client = InMemoryKeychainItemClient()
        let store = makeStore(client)
        let id = UUID()
        seed(client, id, "cloud password", sync: true)
        try store.migratePasswords(for: [id], toICloud: false)
        XCTAssertEqual(try store.password(for: id), "cloud password")
        XCTAssertNotNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
        XCTAssertNotNil(client.attributes(service: service, account: id.uuidString, synchronizable: true))
        XCTAssertFalse(client.calls.contains { $0.operation == .delete })
        try store.removePassword(for: id)
        XCTAssertNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
        XCTAssertEqual(try store.password(for: id), "cloud password") // Documented cloud retention also permits fallback.
    }

    func testSynchronizableSetUpdatesDestinationBeforeRemovingLocalAndRemovalClearsBoth() throws {
        let client = InMemoryKeychainItemClient()
        let store = makeStore(client, enabled: true)
        let id = UUID()
        seed(client, id, "local", sync: false)
        seed(client, id, "old cloud", sync: true)
        try store.setPassword("new cloud", for: id)
        XCTAssertEqual(client.calls.map(\.operation), [.update, .delete])
        XCTAssertEqual(try store.password(for: id), "new cloud")
        XCTAssertNil(client.attributes(service: service, account: id.uuidString, synchronizable: false))
        try store.removePassword(for: id)
        XCTAssertNil(try store.password(for: id))
        client.failures = [.init(operation: .delete, status: errSecAuthFailed)]
        assertStatus(errSecAuthFailed) { try store.removePassword(for: id) }
    }

    func testNativeDeviceOnlyRoundTripUsesUniqueServiceAndCleansUpItsOwnItems() throws {
        // Unsigned simulator hosts lack application-identifier. CI also runs this
        // test with ad hoc signing and rejects skipped native coverage.
        let probe = SystemKeychainItemClient().copyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: UUID().uuidString,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])
        if probe.status == errSecMissingEntitlement {
            throw XCTSkip("Native Keychain access requires simulator ad hoc signing: CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-")
        }
        XCTAssertEqual(probe.status, errSecItemNotFound)
        let store = KeychainCredentialStore(service: service, iCloudEnabled: { false })
        let first = UUID(), second = UUID()
        defer {
            XCTAssertNoThrow(try store.removePassword(for: first))
            XCTAssertNoThrow(try store.removePassword(for: second))
        }
        XCTAssertNil(try store.password(for: first))
        try store.setPassword("native first", for: first)
        try store.setPassword("native second", for: second)
        try store.setPassword("native updated", for: first)
        XCTAssertEqual(try store.password(for: first), "native updated")
        XCTAssertEqual(try store.password(for: second), "native second")
        try store.removePassword(for: first)
        XCTAssertNil(try store.password(for: first))
        XCTAssertEqual(try store.password(for: second), "native second")
    }

    private func makeStore(_ client: InMemoryKeychainItemClient, enabled: Bool = false) -> KeychainCredentialStore {
        KeychainCredentialStore(service: service, keychain: client, iCloudEnabled: { enabled })
    }

    private func seed(_ client: InMemoryKeychainItemClient, _ id: UUID, _ password: String, sync: Bool) {
        client.seed(service: service, account: id.uuidString, data: Data(password.utf8), synchronizable: sync)
    }

    private func assertStatus(_ status: OSStatus, file: StaticString = #filePath, line: UInt = #line,
                              _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case CredentialStoreError.keychain(let actual) = error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(actual, status, file: file, line: line)
        }
    }
}

@MainActor
final class CredentialSyncWorkflowTests: XCTestCase {
    func testOptInAndOutPersistPreferenceAndRetainReadablePasswords() throws {
        try withFixture { fixture in
            _ = try fixture.app.setICloudSyncEnabled(true, modelContext: fixture.context)
            fixture.assertPreference(true)
            fixture.assertPasswordCopies(local: false, cloud: true)
            XCTAssertEqual(fixture.fleet.profiles.map(\.localID), [fixture.id])

            _ = try fixture.app.setICloudSyncEnabled(false, modelContext: fixture.context)
            fixture.assertPreference(false)
            fixture.assertPasswordCopies(local: true, cloud: true)
        }
    }

    func testFailedOptInWriteAndDeletePreservePreferenceAndReadablePasswords() throws {
        for operation in [InMemoryKeychainItemClient.Operation.add, .delete] {
            try withFixture { fixture in
                fixture.client.failures = [.init(operation: operation, status: errSecAuthFailed)]
                XCTAssertThrowsError(try fixture.app.setICloudSyncEnabled(true, modelContext: fixture.context))
                fixture.assertPreference(false)
                fixture.assertPasswordCopies(local: true, cloud: operation == .delete)
                XCTAssertTrue(fixture.fleet.profiles.isEmpty)
                _ = try fixture.app.setICloudSyncEnabled(true, modelContext: fixture.context)
                fixture.assertPreference(true)
                fixture.assertPasswordCopies(local: false, cloud: true)
            }
        }
    }

    func testFleetLoadAndSaveFailureRollBackOptInPreferenceAfterMigration() throws {
        for failOnSave in [false, true] {
            try withFixture { fixture in
                fixture.fleet.failOnSave = failOnSave
                fixture.fleet.shouldFail = true
                XCTAssertThrowsError(try fixture.app.setICloudSyncEnabled(true, modelContext: fixture.context))
                fixture.assertPreference(false)
                fixture.assertPasswordCopies(local: false, cloud: true) // Local mode can still read the fallback.
                fixture.fleet.shouldFail = false
                _ = try fixture.app.setICloudSyncEnabled(true, modelContext: fixture.context)
                fixture.assertPreference(true)
                fixture.assertPasswordCopies(local: false, cloud: true)
            }
        }
    }

    func testFailedOptOutPreservesEnabledPreferenceAndCloudPassword() throws {
        try withFixture { fixture in
            _ = try fixture.app.setICloudSyncEnabled(true, modelContext: fixture.context)
            fixture.client.failures = [.init(operation: .add, status: errSecAuthFailed)]
            XCTAssertThrowsError(try fixture.app.setICloudSyncEnabled(false, modelContext: fixture.context))
            fixture.assertPreference(true)
            fixture.assertPasswordCopies(local: false, cloud: true)
            _ = try fixture.app.setICloudSyncEnabled(false, modelContext: fixture.context)
            fixture.assertPreference(false)
            fixture.assertPasswordCopies(local: true, cloud: true)
        }
    }

    private func withFixture(_ run: (CredentialWorkflowFixture) throws -> Void) throws {
        let suite = "CredentialSyncWorkflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try run(CredentialWorkflowFixture(defaults: defaults))
    }
}

@MainActor
private final class CredentialWorkflowFixture {
    let id = UUID()
    let service = "CredentialSyncWorkflowTests.\(UUID().uuidString)"
    let client = InMemoryKeychainItemClient()
    let fleet = CredentialWorkflowFleetStore()
    let defaults: UserDefaults
    let context: ModelContext
    let credentials: KeychainCredentialStore
    let app: AppState

    init(defaults: UserDefaults) throws {
        self.defaults = defaults
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PortOSInstance.self, configurations: configuration)
        context = ModelContext(container)
        let preference = CredentialSyncPreference(defaults: defaults)
        credentials = KeychainCredentialStore(service: service, keychain: client, iCloudEnabled: { preference.enabled })
        app = AppState(credentials: credentials, fleetSyncStore: fleet, defaults: defaults)
        context.insert(PortOSInstance(localID: id, baseURL: URL(string: "https://fixture.example:5555")!, localLabel: "Fixture",
                                      health: PortOSHealth(status: "ok", version: "1", hostname: "fixture",
                                                           instanceID: "fixture", name: "Fixture", authRequired: true, scheme: "https")))
        try context.save()
        try credentials.setPassword("fixture password", for: id)
    }

    func assertPreference(_ enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.iCloudSyncEnabled, enabled, file: file, line: line)
        XCTAssertEqual(defaults.bool(forKey: AppState.iCloudSyncKey), enabled, file: file, line: line)
    }

    func assertPasswordCopies(local: Bool, cloud: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(client.attributes(service: service, account: id.uuidString, synchronizable: false) != nil, local, file: file, line: line)
        XCTAssertEqual(client.attributes(service: service, account: id.uuidString, synchronizable: true) != nil, cloud, file: file, line: line)
        XCTAssertEqual(try credentials.password(for: id), "fixture password", file: file, line: line)
    }
}

private final class CredentialSyncPreference: @unchecked Sendable {
    let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    var enabled: Bool { defaults.bool(forKey: AppState.iCloudSyncKey) }
}

private final class CredentialWorkflowFleetStore: FleetSyncStore, @unchecked Sendable {
    var profiles: [SyncedInstanceProfile] = []
    var shouldFail = false
    var failOnSave = false
    struct Unavailable: Error {}
    func loadProfiles() throws -> [SyncedInstanceProfile] {
        if shouldFail && !failOnSave { throw Unavailable() }
        return profiles
    }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws {
        if shouldFail && failOnSave { throw Unavailable() }
        self.profiles = profiles
    }
}
