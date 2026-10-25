import Foundation
import Security

struct TailcatConnection: Codable, Equatable, Sendable {
    let address: String
    let origin: String
    var password: String = ""
}

/// Tailcat passwords share the device-only pairing item. The user's existing
/// fleet/password sync preference continues to apply to direct profiles.
struct TailcatAwareCredentialStore: CredentialStore {
    let direct: any CredentialStore
    let tailcat: any TailcatConnectionStoring

    init(
        direct: any CredentialStore = KeychainCredentialStore(),
        tailcat: any TailcatConnectionStoring = KeychainTailcatConnectionStore()
    ) {
        self.direct = direct
        self.tailcat = tailcat
    }

    func password(for instanceID: UUID) throws -> String? {
        if let connection = try tailcat.connection(for: instanceID) { return connection.password }
        return try direct.password(for: instanceID)
    }

    func setPassword(_ password: String, for instanceID: UUID) throws {
        if var connection = try tailcat.connection(for: instanceID) {
            connection.password = password
            try tailcat.setConnection(connection, for: instanceID)
        } else {
            try direct.setPassword(password, for: instanceID)
        }
    }

    func removePassword(for instanceID: UUID) throws {
        if var connection = try tailcat.connection(for: instanceID) {
            connection.password = ""
            try tailcat.setConnection(connection, for: instanceID)
        } else {
            try direct.removePassword(for: instanceID)
        }
    }

    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {
        let directIDs = try instanceIDs.filter { try tailcat.connection(for: $0) == nil }
        try direct.migratePasswords(for: directIDs, toICloud: toICloud)
    }
}

enum TailcatError: LocalizedError {
    case missingPairing
    case invalidEndpoint
    case passwordRequired
    case invalidBridgeResponse
    case pairingRestoreFailed

    var errorDescription: String? {
        switch self {
        case .missingPairing: "This device has no Tailcat pairing for that instance. Add it again using the full address copied privately from PortOS."
        case .invalidEndpoint: "Use the private PortOS ingress on port 5565. HTTPS also requires the server's certificate host name."
        case .passwordRequired: "Enable a PortOS instance password before connecting through the Tailcat prototype."
        case .invalidBridgeResponse: "The private Tailcat connection could not be opened."
        case .pairingRestoreFailed: "Removal could not be saved and this device's secure pairing could not be restored. Pair the instance again using the full address copied privately from PortOS."
        }
    }
}

/// This URL is a local routing identifier, never a network destination or secret.
/// Keeping the reserved suffix recognizable makes missing pairings fail closed.
enum TailcatEndpoint {
    static let suffix = ".tailcat.portdeck.invalid"

    static func make(profileID: UUID) -> URL {
        URL(string: "http://\(profileID.uuidString.lowercased())\(suffix):5565")!
    }

    static func isTailcat(_ url: URL) -> Bool {
        url.host?.lowercased().hasSuffix(suffix) == true
    }

    static func profileID(for url: URL) -> UUID? {
        guard isTailcat(url), let host = url.host,
              url.scheme == "http", url.port == 5565 else { return nil }
        return UUID(uuidString: String(host.dropLast(suffix.count)))
    }
}

protocol TailcatConnectionStoring: Sendable {
    func connection(for profileID: UUID) throws -> TailcatConnection?
    func setConnection(_ connection: TailcatConnection, for profileID: UUID) throws
    func removeConnection(for profileID: UUID) throws
    func devicePrivateKey() throws -> String
}

/// Deliberately separate from fleet/password iCloud sync. Every query explicitly
/// selects a non-synchronizable item; keys and capabilities never leave the device.
final class KeychainTailcatConnectionStore: TailcatConnectionStoring, @unchecked Sendable {
    private let keychain: any KeychainItemClient
    private let service: String
    private let makeIdentity: @Sendable () -> String
    private let identityLock = NSLock()

    init(
        service: String = "net.shadowpuppet.PortDeck.tailcat",
        keychain: any KeychainItemClient = SystemKeychainItemClient(),
        makeIdentity: @escaping @Sendable () -> String = { NativeTailcatFactory.newDeviceKey() }
    ) {
        self.service = service
        self.keychain = keychain
        self.makeIdentity = makeIdentity
    }

    func connection(for profileID: UUID) throws -> TailcatConnection? {
        guard let data = try read(account: profileID.uuidString) else { return nil }
        do { return try JSONDecoder().decode(TailcatConnection.self, from: data) }
        catch { throw CredentialStoreError.invalidData }
    }

    func setConnection(_ connection: TailcatConnection, for profileID: UUID) throws {
        try write(JSONEncoder().encode(connection), account: profileID.uuidString)
    }

    func removeConnection(for profileID: UUID) throws {
        let status = keychain.delete(query(account: profileID.uuidString))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }
    }

    func devicePrivateKey() throws -> String {
        try identityLock.withLock {
            if let data = try read(account: "device-identity") {
                guard let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw CredentialStoreError.invalidData }
                return key
            }
            // An inaccessible/corrupt identity is an error, never permission to
            // generate a different device identity and silently bypass approval.
            let key = makeIdentity()
            try write(Data(key.utf8), account: "device-identity")
            return key
        }
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    private func read(account: String) throws -> Data? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let result = keychain.copyMatching(q)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess else { throw CredentialStoreError.keychain(result.status) }
        guard let data = result.item as? Data else { throw CredentialStoreError.invalidData }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let q = query(account: account)
        let status = keychain.update(q, attributes: [kSecValueData as String: data])
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }
        var insert = q
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = keychain.add(insert)
        guard added == errSecSuccess else { throw CredentialStoreError.keychain(added) }
    }
}
