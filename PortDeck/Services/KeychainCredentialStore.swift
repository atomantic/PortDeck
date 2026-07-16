import Foundation
import Security

protocol CredentialStore: Sendable {
    func password(for instanceID: UUID) throws -> String?
    func setPassword(_ password: String, for instanceID: UUID) throws
    func removePassword(for instanceID: UUID) throws
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain operation failed (\(status))."
        case .invalidData: "The saved secure data could not be read."
        }
    }
}

final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String
    private let iCloudEnabled: @Sendable () -> Bool

    init(
        service: String = "net.shadowpuppet.PortDeck.portos-password",
        iCloudEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: AppState.iCloudSyncKey)
        }
    ) {
        self.service = service
        self.iCloudEnabled = iCloudEnabled
    }

    func password(for instanceID: UUID) throws -> String? {
        if iCloudEnabled() {
            return try readPassword(for: instanceID, synchronizable: true)
                ?? readPassword(for: instanceID, synchronizable: false)
        }
        return try readPassword(for: instanceID, synchronizable: false)
            ?? readPassword(for: instanceID, synchronizable: true)
    }

    func setPassword(_ password: String, for instanceID: UUID) throws {
        if password.isEmpty {
            try removePassword(for: instanceID)
            return
        }
        let sync = iCloudEnabled()
        try writePassword(password, for: instanceID, synchronizable: sync)
        if sync { try deletePassword(for: instanceID, synchronizable: false) }
    }

    func removePassword(for instanceID: UUID) throws {
        try deletePassword(for: instanceID, synchronizable: false)
        if iCloudEnabled() { try deletePassword(for: instanceID, synchronizable: true) }
    }

    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {
        for instanceID in instanceIDs {
            let sourceIsICloud = !toICloud
            let password = try readPassword(for: instanceID, synchronizable: sourceIsICloud)
                ?? readPassword(for: instanceID, synchronizable: toICloud)
            guard let password else { continue }
            try writePassword(password, for: instanceID, synchronizable: toICloud)
            if toICloud { try deletePassword(for: instanceID, synchronizable: false) }
        }
    }

    private func readPassword(for instanceID: UUID, synchronizable: Bool) throws -> String? {
        var query = baseQuery(instanceID, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidData
        }
        return password
    }

    private func writePassword(_ password: String, for instanceID: UUID, synchronizable: Bool) throws {
        let data = Data(password.utf8)
        let query = baseQuery(instanceID, synchronizable: synchronizable)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw CredentialStoreError.keychain(updateStatus) }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
    }

    private func deletePassword(for instanceID: UUID, synchronizable: Bool) throws {
        let status = SecItemDelete(baseQuery(instanceID, synchronizable: synchronizable) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(_ instanceID: UUID, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: instanceID.uuidString,
            kSecAttrSynchronizable as String: synchronizable
        ]
    }
}
