import Foundation
import Security

/// Internal Security boundary shared by stores so tests can exercise their real
/// queries and serialization without accessing the device Keychain or iCloud.
protocol KeychainItemClient: Sendable {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainItemClient: KeychainItemClient {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
