import Security
import SwiftData
import XCTest
@testable import PortDeck

final class TailcatTransportTests: XCTestCase {
    func testNativeTailcatKeychainRoundTrip() throws {
        let service = "net.shadowpuppet.PortDeck.tailcat-native-test.\(UUID().uuidString)"
        let client = SystemKeychainItemClient()
        let scope: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false
        ]
        var probe = scope
        probe[kSecReturnData as String] = true
        probe[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = client.copyMatching(probe).status
        if status == errSecMissingEntitlement {
            throw XCTSkip("Native Tailcat Keychain coverage requires an ad hoc signed simulator host.")
        }
        XCTAssertEqual(status, errSecItemNotFound)
        defer { XCTAssertEqual(client.delete(scope), errSecSuccess) }
        let store = KeychainTailcatConnectionStore(service: service)
        let identity = try store.devicePrivateKey()
        XCTAssertTrue(identity == (try store.devicePrivateKey()))
        let id = UUID()
        let connection = TailcatConnection(address: "tcUNIT-placeholder", origin: "http://127.0.0.1:5565", password: "native-unit-password")
        try store.setConnection(connection, for: id)
        XCTAssertTrue(try store.connection(for: id) == connection)
        try store.removeConnection(for: id)
        XCTAssertNil(try store.connection(for: id))
        XCTAssertTrue(identity == (try store.devicePrivateKey()))
    }

    func testNativeIdentityRoundTripAndMalformedAddressAreLocal() throws {
        let factory = NativeTailcatFactory()
        let key = NativeTailcatFactory.newDeviceKey()
        let publicKey = try factory.publicKey(privateKey: key)
        XCTAssertTrue(publicKey.hasPrefix("nodekey:"))
        XCTAssertEqual(publicKey, try factory.publicKey(privateKey: key))
        XCTAssertThrowsError(try factory.inspect(address: "tcINVALID-test-secret")) { error in
            XCTAssertFalse(error.localizedDescription.contains("tcINVALID-test-secret"))
        }
    }

    func testSecretsAndIdentityAlwaysUseDeviceOnlyKeychain() throws {
        let keychain = InMemoryKeychainItemClient()
        let store = KeychainTailcatConnectionStore(service: "unit-tailcat", keychain: keychain, makeIdentity: { "unit-private-key" })
        let id = UUID()
        let connection = TailcatConnection(address: "tcUNIT-placeholder", origin: "http://127.0.0.1:5565", password: "unit-password")
        try store.setConnection(connection, for: id)
        XCTAssertEqual(try store.connection(for: id), connection)
        XCTAssertEqual(try store.devicePrivateKey(), "unit-private-key")
        XCTAssertEqual(try store.devicePrivateKey(), "unit-private-key")
        try store.removeConnection(for: id)
        XCTAssertNil(try store.connection(for: id))
        for call in keychain.calls {
            XCTAssertEqual(call.query[kSecAttrSynchronizable as String] as? Bool, false)
            if call.operation == .add {
                XCTAssertEqual(call.query[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            }
        }
        XCTAssertNotNil(keychain.data(account: "device-identity"))
    }

    func testInaccessibleIdentityIsNotRegenerated() throws {
        let keychain = InMemoryKeychainItemClient()
        keychain.failures = [.init(operation: .read, status: errSecInteractionNotAllowed)]
        let store = KeychainTailcatConnectionStore(keychain: keychain, makeIdentity: { XCTFail("regenerated an inaccessible identity"); return "invalid" })
        XCTAssertThrowsError(try store.devicePrivateKey())
        XCTAssertFalse(keychain.calls.contains { $0.operation == .add })
    }

    func testPasswordSyncNeverMigratesTailcatCredentials() throws {
        let keychain = InMemoryKeychainItemClient()
        let privateStore = KeychainTailcatConnectionStore(keychain: keychain)
        let direct = TailcatTestCredentialStore()
        let privateID = UUID(), directID = UUID()
        try privateStore.setConnection(TailcatConnection(address: "tcUNIT-placeholder", origin: "http://127.0.0.1:5565", password: "private-password"), for: privateID)
        let credentials = TailcatAwareCredentialStore(direct: direct, tailcat: privateStore)

        XCTAssertEqual(try credentials.password(for: privateID), "private-password")
        try credentials.setPassword("updated-private", for: privateID)
        try credentials.migratePasswords(for: [privateID, directID], toICloud: true)
        XCTAssertEqual(try privateStore.connection(for: privateID)?.password, "updated-private")
        XCTAssertEqual(direct.migratedIDs, [directID])
        XCTAssertTrue(direct.writtenIDs.isEmpty)
    }

    func testMissingPairingNeverFallsThroughToDNSOrDirectTransport() async throws {
        let pool = makePool().pool
        let direct = TailcatTestHTTPTransport()
        let transport = TailcatRoutingTransport(pool: pool, direct: direct)
        do {
            _ = try await transport.data(for: URLRequest(url: TailcatEndpoint.make(profileID: UUID())))
            XCTFail("missing pairing was routed")
        } catch { XCTAssertTrue(error is TailcatError) }
        XCTAssertNil(direct.lastRequest)
    }

    func testRoutingPreservesRequestAndUsesOnlyAuthenticatedLocalProxy() async throws {
        let (pool, _, tunnel) = makePool()
        let id = UUID()
        _ = try await pool.stage(testConnection, for: id)
        let direct = TailcatTestHTTPTransport()
        let transport = TailcatRoutingTransport(pool: pool, direct: direct)
        var url = TailcatEndpoint.make(profileID: id)
        url.append(path: "/api/palette/action/brain_capture")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("private capture".utf8)
        request.setValue("Basic instance-password", forHTTPHeaderField: "Authorization")
        _ = try await transport.data(for: request)
        let routed = try XCTUnwrap(direct.lastRequest)
        XCTAssertEqual(routed.url?.host, "127.0.0.1")
        XCTAssertEqual(routed.url?.port, 19443)
        XCTAssertEqual(routed.url?.path, request.url?.path)
        XCTAssertEqual(routed.httpBody, request.httpBody)
        XCTAssertEqual(routed.value(forHTTPHeaderField: "Authorization"), "Basic instance-password")
        XCTAssertEqual(routed.value(forHTTPHeaderField: "X-PortDeck-Tunnel"), tunnel.token)
        XCTAssertFalse(routed.httpShouldHandleCookies)
        XCTAssertFalse(routed.url!.absoluteString.contains(testConnection.address))
        await pool.discardDraft(for: id)
        XCTAssertEqual(tunnel.closeCount, 1)
    }

    func testDirectProfilesKeepTheirOriginalTransport() async throws {
        let direct = TailcatTestHTTPTransport()
        let transport = TailcatRoutingTransport(pool: makePool().pool, direct: direct)
        let request = URLRequest(url: URL(string: "https://unit.example.invalid:5555/api/system/health")!)
        _ = try await transport.data(for: request)
        XCTAssertEqual(direct.lastRequest?.url, request.url)
        XCTAssertNil(direct.lastRequest?.value(forHTTPHeaderField: "X-PortDeck-Tunnel"))
    }

    func testPersistedPairingSurvivesDisconnectAndForgetRemovesOnlyIt() async throws {
        let (pool, store, tunnel) = makePool()
        let id = UUID()
        _ = try await pool.stage(testConnection, for: id)
        XCTAssertNil(try store.connection(for: id))
        _ = try await pool.route(TailcatEndpoint.make(profileID: id))
        try await pool.persistDraft(for: id)
        await pool.discardDraft(for: id)
        XCTAssertEqual(tunnel.closeCount, 0)
        await pool.disconnectAll()
        XCTAssertEqual(tunnel.closeCount, 1)
        XCTAssertEqual(try store.connection(for: id), testConnection)
        try await pool.forget(id)
        XCTAssertNil(try store.connection(for: id))
        XCTAssertEqual(try store.devicePrivateKey(), "unit-private-key")
    }

    @MainActor
    func testFailedProfileRemovalRestoresPairingAndPasswordBeforeRetry() throws {
        let container = try ModelContainer(for: PortOSInstance.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.autosaveEnabled = false
        let (pool, store, _) = makePool()
        let id = UUID()
        try store.setConnection(testConnection, for: id)
        let instance = PortOSInstance(localID: id, baseURL: TailcatEndpoint.make(profileID: id), health:
            PortOSHealth(status: "ok", version: "1", hostname: "Unit", instanceID: "private-instance", name: "Unit", authRequired: true, scheme: "http"))
        context.insert(instance)
        try context.save()
        let suite = "TailcatRemovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var failSave = true
        let state = AppState(defaults: defaults, tailcat: pool, saveFleetRemoval: { context in
            if failSave { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        })
        state.select(instance)
        XCTAssertThrowsError(try state.removeFleetInstance(instance, modelContext: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PortOSInstance>()), 1)
        XCTAssertEqual(try store.connection(for: id), testConnection)
        XCTAssertEqual(try state.credentials.password(for: id), testConnection.password)
        XCTAssertEqual(state.selectedInstanceID, id)
        failSave = false
        try state.removeFleetInstance(instance, modelContext: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PortOSInstance>()), 0)
        XCTAssertNil(try store.connection(for: id))
        XCTAssertNil(state.selectedInstanceID)
    }

    @MainActor
    func testFleetSyncCannotExportOrOverwriteDeviceOwnedProfiles() throws {
        let container = try ModelContainer(for: PortOSInstance.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let id = UUID()
        let health = PortOSHealth(status: "ok", version: "1", hostname: "Unit", instanceID: "private-instance", name: "Unit", authRequired: true, scheme: "http")
        let local = PortOSInstance(localID: id, baseURL: TailcatEndpoint.make(profileID: id), health: health)
        context.insert(local)
        try context.save()
        let cloudReplacement = PortOSInstance(localID: id, baseURL: URL(string: "https://other.example.invalid:5555")!, health: health)
        cloudReplacement.syncUpdatedAt = .distantFuture
        let cloud = TailcatTestFleetStore(profiles: [SyncedInstanceProfile(instance: cloudReplacement)])
        let coordinator = FleetSyncCoordinator(store: cloud, credentials: TailcatTestCredentialStore())
        _ = try coordinator.synchronize(modelContext: context)
        XCTAssertTrue(local.usesTailcat)
        XCTAssertTrue(cloud.profiles.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PortOSInstance>()), 1)
    }

    private var testConnection: TailcatConnection {
        TailcatConnection(address: "tcUNIT-placeholder", origin: "http://127.0.0.1:5565", password: "unit-password")
    }

    private func makePool() -> (pool: TailcatTunnelPool, store: KeychainTailcatConnectionStore, tunnel: TailcatTestTunnel) {
        let store = KeychainTailcatConnectionStore(keychain: InMemoryKeychainItemClient(), makeIdentity: { "unit-private-key" })
        let tunnel = TailcatTestTunnel()
        return (TailcatTunnelPool(store: store, factory: TailcatTestFactory(tunnel: tunnel)), store, tunnel)
    }
}

private struct TailcatTestFactory: TailcatTunnelCreating {
    let tunnel: TailcatTestTunnel
    func inspect(address: String) throws -> TailcatAddressSummary { TailcatAddressSummary(publicKey: "unit-public-key", relays: ["relay.example.invalid"]) }
    func publicKey(privateKey: String) throws -> String { "unit-public-key" }
    func open(connection: TailcatConnection, privateKey: String) throws -> any TailcatLocalTunnel { tunnel }
}

private final class TailcatTestTunnel: TailcatLocalTunnel, @unchecked Sendable {
    let baseURL = URL(string: "http://127.0.0.1:19443")!
    let token = "unit-local-token"
    private let lock = NSLock()
    private var closes = 0
    var closeCount: Int { lock.withLock { closes } }
    func close() { lock.withLock { closes += 1 } }
}

private final class TailcatTestHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    var lastRequest: URLRequest? { lock.withLock { request } }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { self.request = request }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class TailcatTestCredentialStore: CredentialStore, @unchecked Sendable {
    var migratedIDs: [UUID] = []
    var writtenIDs: [UUID] = []
    func password(for instanceID: UUID) throws -> String? { nil }
    func setPassword(_ password: String, for instanceID: UUID) throws { writtenIDs.append(instanceID) }
    func removePassword(for instanceID: UUID) throws {}
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws { migratedIDs = instanceIDs }
}

private final class TailcatTestFleetStore: FleetSyncStore, @unchecked Sendable {
    var profiles: [SyncedInstanceProfile]
    init(profiles: [SyncedInstanceProfile]) { self.profiles = profiles }
    func loadProfiles() throws -> [SyncedInstanceProfile] { profiles }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws { self.profiles = profiles }
}
