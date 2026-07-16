import Foundation
import Security

protocol FleetSyncStore: Sendable {
    func loadProfiles() throws -> [SyncedInstanceProfile]
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws
}

/// Stores one fleet profile per synchronizable Keychain item so edits to separate
/// instances on separate devices cannot overwrite the whole fleet as one blob.
final class ICloudFleetSyncStore: FleetSyncStore, @unchecked Sendable {
    private let service: String
    private let legacyIndexAccount = "fleet-index-v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "net.shadowpuppet.PortDeck.icloud-fleet") {
        self.service = service
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadProfiles() throws -> [SyncedInstanceProfile] {
        var query = serviceQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }

        let rawItems: [[String: Any]]
        if let matches = item as? [[String: Any]] {
            rawItems = matches
        } else if let match = item as? [String: Any] {
            rawItems = [match]
        } else {
            throw CredentialStoreError.invalidData
        }

        var profilesByID: [UUID: SyncedInstanceProfile] = [:]
        for rawItem in rawItems {
            guard let data = rawItem[kSecValueData as String] as? Data else {
                throw CredentialStoreError.invalidData
            }
            if let profile = try? decoder.decode(SyncedInstanceProfile.self, from: data) {
                merge(profile, into: &profilesByID)
                continue
            }
            // Migrate the short-lived fleet-index format used by early development builds.
            if let legacyProfiles = try? decoder.decode([SyncedInstanceProfile].self, from: data) {
                for profile in legacyProfiles { merge(profile, into: &profilesByID) }
                continue
            }
            throw CredentialStoreError.invalidData
        }
        return Array(profilesByID.values)
    }

    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws {
        for profile in profiles {
            try save(profile)
        }

        // Once every profile has its own item, the old all-fleet blob is redundant.
        let legacyDeleteStatus = SecItemDelete(profileQuery(account: legacyIndexAccount) as CFDictionary)
        guard legacyDeleteStatus == errSecSuccess || legacyDeleteStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(legacyDeleteStatus)
        }
    }

    private func save(_ profile: SyncedInstanceProfile) throws {
        let data = try encoder.encode(profile)
        let query = profileQuery(account: profile.localID.uuidString)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw CredentialStoreError.keychain(updateStatus) }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
    }

    private func merge(
        _ profile: SyncedInstanceProfile,
        into profilesByID: inout [UUID: SyncedInstanceProfile]
    ) {
        if let existing = profilesByID[profile.localID], existing.effectiveDate > profile.effectiveDate {
            return
        }
        profilesByID[profile.localID] = profile
    }

    private var serviceQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true
        ]
    }

    private func profileQuery(account: String) -> [String: Any] {
        var query = serviceQuery
        query[kSecAttrAccount as String] = account
        return query
    }
}
