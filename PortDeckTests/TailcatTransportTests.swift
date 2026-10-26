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
    func testPairingRemovalFailurePreservesRowSelectionAndTunnelWithoutRestoration() async throws {
        let fixture = try TailcatRemovalFixture()
        _ = try await fixture.pool.route(XCTUnwrap(fixture.instance.baseURL))
        fixture.keychain.failures = [.init(operation: .delete, status: errSecInteractionNotAllowed)]
        let previousWrites = fixture.keychain.calls.filter { $0.operation == .update || $0.operation == .add }.count

        XCTAssertThrowsError(try fixture.remove()) { error in
            guard case CredentialStoreError.keychain(errSecInteractionNotAllowed) = error else {
                return XCTFail("Expected the original pairing-removal error, got \(error)")
            }
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PortOSInstance>()), 1)
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertEqual(try fixture.store.connection(for: fixture.instance.localID), fixture.connection)
        XCTAssertEqual(fixture.saveCount, 0)
        XCTAssertEqual(fixture.keychain.calls.filter { $0.operation == .update || $0.operation == .add }.count, previousWrites)
        await Task.yield()
        XCTAssertEqual(fixture.tunnel.closeCount, 0)

        try fixture.remove()
        await fulfillment(of: [fixture.disconnected], timeout: 2)
        XCTAssertEqual(fixture.saveCount, 1)
        XCTAssertEqual(fixture.tunnel.closeCount, 1)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<PortOSInstance>()).isEmpty)
        XCTAssertNil(fixture.state.selectedInstanceID)
        XCTAssertEqual(fixture.cloud.accessCount, 0)
    }

    @MainActor
    func testPairingRestorationFailureTakesPrecedenceAndRetainsRowSelectionAndTunnel() async throws {
        let fixture = try TailcatRemovalFixture()
        _ = try await fixture.pool.route(XCTUnwrap(fixture.instance.baseURL))
        fixture.failSave = true
        fixture.instance.localLabel = "Pending edit"
        fixture.keychain.failures = [.init(operation: .add, status: errSecInteractionNotAllowed)]

        XCTAssertThrowsError(try fixture.remove()) { error in
            guard case TailcatError.pairingRestoreFailed = error else {
                return XCTFail("Expected restoration error to replace save error, got \(error)")
            }
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PortOSInstance>()), 1)
        XCTAssertEqual(fixture.instance.localLabel, "Pending edit")
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertNil(try fixture.store.connection(for: fixture.instance.localID))
        XCTAssertEqual(fixture.saveCount, 1)
        await Task.yield()
        XCTAssertEqual(fixture.tunnel.closeCount, 0)
        XCTAssertEqual(fixture.cloud.accessCount, 0)
        await fixture.pool.disconnectAll()
    }

    @MainActor
    func testPairingSnapshotFailureDoesNotRemovePairingOrSaveDeletion() throws {
        let fixture = try TailcatRemovalFixture()
        fixture.keychain.failures = [.init(operation: .read, status: errSecInteractionNotAllowed)]
        XCTAssertThrowsError(try fixture.remove())
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PortOSInstance>()), 1)
        XCTAssertEqual(fixture.state.selectedInstanceID, fixture.instance.localID)
        XCTAssertEqual(try fixture.store.connection(for: fixture.instance.localID), fixture.connection)
        XCTAssertFalse(fixture.keychain.calls.contains { $0.operation == .delete })
        XCTAssertEqual(fixture.saveCount, 0)
        XCTAssertEqual(fixture.cloud.accessCount, 0)
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
    var onClose: (@Sendable () -> Void)?
    var closeCount: Int { lock.withLock { closes } }
    func close() {
        lock.withLock { closes += 1 }
        onClose?()
    }
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
    var accessCount = 0
    init(profiles: [SyncedInstanceProfile]) { self.profiles = profiles }
    func loadProfiles() throws -> [SyncedInstanceProfile] { accessCount += 1; return profiles }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws { accessCount += 1; self.profiles = profiles }
}

@MainActor
private final class TailcatRemovalFixture {
    let keychain = InMemoryKeychainItemClient()
    let store: KeychainTailcatConnectionStore
    let tunnel = TailcatTestTunnel()
    let pool: TailcatTunnelPool
    let context: ModelContext
    let instance: PortOSInstance
    let connection = TailcatConnection(address: "tcUNIT-placeholder", origin: "http://127.0.0.1:5565", password: "unit-password")
    let cloud = TailcatTestFleetStore(profiles: [])
    let disconnected = XCTestExpectation(description: "Tunnel disconnects after persisted deletion")
    let suite = "TailcatRemovalFixture.\(UUID().uuidString)"
    let defaults: UserDefaults
    var failSave = false
    var saveCount = 0
    lazy var state = AppState(fleetSyncStore: cloud, defaults: defaults, tailcat: pool, saveFleetRemoval: { [unowned self] context in
        saveCount += 1
        XCTAssertEqual(tunnel.closeCount, 0, "Persistence must precede disconnection")
        if failSave { throw CocoaError(.fileWriteUnknown) }
        try context.save()
    })

    init() throws {
        store = KeychainTailcatConnectionStore(keychain: keychain, makeIdentity: { "unit-private-key" })
        pool = TailcatTunnelPool(store: store, factory: TailcatTestFactory(tunnel: tunnel))
        let container = try ModelContainer(for: PortOSInstance.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        context.autosaveEnabled = false
        let id = UUID()
        instance = PortOSInstance(localID: id, baseURL: TailcatEndpoint.make(profileID: id), health:
            PortOSHealth(status: "ok", version: "1", hostname: "Unit", instanceID: "private-instance", name: "Unit", authRequired: true, scheme: "http"))
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: AppState.iCloudSyncKey)
        context.insert(instance)
        try context.save()
        try store.setConnection(connection, for: id)
        let disconnected = disconnected
        tunnel.onClose = { disconnected.fulfill() }
        state.select(instance)
    }

    deinit { defaults.removePersistentDomain(forName: suite) }
    func remove() throws { try state.removeFleetInstance(instance, modelContext: context) }
}
