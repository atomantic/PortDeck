import Foundation
import PortDeckTailcat

struct TailcatAddressSummary: Decodable, Sendable {
    let publicKey: String
    let relays: [String]
}

protocol TailcatLocalTunnel: Sendable {
    var baseURL: URL { get }
    var token: String { get }
    func close()
}

protocol TailcatTunnelCreating: Sendable {
    func inspect(address: String) throws -> TailcatAddressSummary
    func publicKey(privateKey: String) throws -> String
    func open(connection: TailcatConnection, privateKey: String) throws -> any TailcatLocalTunnel
}

struct NativeTailcatFactory: TailcatTunnelCreating {
    static func newDeviceKey() -> String { TailcatbridgeNewDeviceKey() }

    func inspect(address: String) throws -> TailcatAddressSummary {
        var error: NSError?
        let json = TailcatbridgeInspectAddress(address, &error)
        if let error { throw error }
        guard let data = json.data(using: .utf8) else { throw TailcatError.invalidBridgeResponse }
        return try JSONDecoder().decode(TailcatAddressSummary.self, from: data)
    }

    func publicKey(privateKey: String) throws -> String {
        var error: NSError?
        let key = TailcatbridgePublicKey(privateKey, &error)
        if let error { throw error }
        return key
    }

    func open(connection: TailcatConnection, privateKey: String) throws -> any TailcatLocalTunnel {
        var error: NSError?
        let tunnel = TailcatbridgeNewTunnel(connection.address, privateKey, connection.origin, &error)
        if let error { throw error }
        guard let tunnel else { throw TailcatError.invalidBridgeResponse }
        return NativeTailcatTunnel(tunnel)
    }
}

private final class NativeTailcatTunnel: TailcatLocalTunnel, @unchecked Sendable {
    private let tunnel: TailcatbridgeTunnel
    let baseURL: URL
    let token: String

    init(_ tunnel: TailcatbridgeTunnel) {
        self.tunnel = tunnel
        baseURL = URL(string: "http://127.0.0.1:\(tunnel.port())")!
        token = tunnel.token()
    }

    func close() { tunnel.close() }
    deinit { close() }
}

struct TailcatLocalRoute: Sendable {
    let url: URL
    let token: String
}

/// Owns only app-scoped connections. Draft capabilities remain in memory until
/// health and instance-password validation succeed and the user saves the profile.
actor TailcatTunnelPool {
    static let shared = TailcatTunnelPool()
    nonisolated let store: any TailcatConnectionStoring
    private let factory: any TailcatTunnelCreating
    private var drafts: [UUID: TailcatConnection] = [:]
    private var tunnels: [UUID: (TailcatConnection, any TailcatLocalTunnel)] = [:]

    init(
        store: any TailcatConnectionStoring = KeychainTailcatConnectionStore(),
        factory: any TailcatTunnelCreating = NativeTailcatFactory()
    ) {
        self.store = store
        self.factory = factory
    }

    func publicKey() throws -> String { try factory.publicKey(privateKey: store.devicePrivateKey()) }

    func stage(_ connection: TailcatConnection, for profileID: UUID) throws -> TailcatAddressSummary {
        let summary = try factory.inspect(address: connection.address)
        guard let origin = URL(string: connection.origin), origin.port == 5565,
              HTTPOrigin(url: origin) != nil, origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil, origin.path.isEmpty || origin.path == "/" else {
            throw TailcatError.invalidEndpoint
        }
        disconnect(profileID)
        drafts[profileID] = connection
        return summary
    }

    func persistDraft(for profileID: UUID) throws {
        guard let connection = drafts[profileID] else { throw TailcatError.missingPairing }
        try store.setConnection(connection, for: profileID)
        drafts.removeValue(forKey: profileID)
    }

    func discardDraft(for profileID: UUID) {
        guard drafts.removeValue(forKey: profileID) != nil else { return }
        disconnect(profileID)
    }

    func forget(_ profileID: UUID) throws {
        disconnect(profileID)
        drafts.removeValue(forKey: profileID)
        try store.removeConnection(for: profileID)
    }

    nonisolated func removeSavedConnection(for profileID: UUID) throws {
        try store.removeConnection(for: profileID)
    }

    func disconnect(_ profileID: UUID) {
        tunnels.removeValue(forKey: profileID)?.1.close()
    }

    func disconnectAll() {
        for (_, tunnel) in tunnels.values { tunnel.close() }
        tunnels.removeAll()
    }

    func route(_ url: URL) throws -> TailcatLocalRoute {
        guard let profileID = TailcatEndpoint.profileID(for: url),
              let connection = try drafts[profileID] ?? store.connection(for: profileID) else {
            throw TailcatError.missingPairing
        }
        let tunnel: any TailcatLocalTunnel
        if let existing = tunnels[profileID], existing.0 == connection {
            tunnel = existing.1
        } else {
            disconnect(profileID)
            tunnel = try factory.open(connection: connection, privateKey: store.devicePrivateKey())
            tunnels[profileID] = (connection, tunnel)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw TailcatError.invalidEndpoint }
        components.scheme = tunnel.baseURL.scheme
        components.host = tunnel.baseURL.host
        components.port = tunnel.baseURL.port
        components.user = nil
        components.password = nil
        guard let destination = components.url else { throw TailcatError.invalidEndpoint }
        return TailcatLocalRoute(url: destination, token: tunnel.token)
    }
}

struct TailcatRoutingTransport: HTTPTransport {
    let pool: TailcatTunnelPool
    let direct: any HTTPTransport

    init(pool: TailcatTunnelPool = .shared, direct: any HTTPTransport = OriginBoundTransport()) {
        self.pool = pool
        self.direct = direct
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, TailcatEndpoint.isTailcat(url) else { return try await direct.data(for: request) }
        try Task.checkCancellation()
        let route = try await pool.route(url)
        try Task.checkCancellation()
        var localRequest = request
        localRequest.url = route.url
        localRequest.setValue(route.token, forHTTPHeaderField: "X-PortDeck-Tunnel")
        localRequest.cachePolicy = .reloadIgnoringLocalCacheData
        // Localhost cookies are not port-scoped and must not cross instances.
        localRequest.httpShouldHandleCookies = false
        return try await direct.data(for: localRequest)
    }
}
