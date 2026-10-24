import Foundation
import Security
@testable import PortDeck

/// Stores the actual attributes and bytes sent by the adapter; no real Keychain access.
final class InMemoryKeychainItemClient: KeychainItemClient, @unchecked Sendable {
    private var items: [[String: Any]] = []

    func seed(service: String, account: String, data: Data) {
        items.append([kSecClass as String: kSecClassGenericPassword,
                      kSecAttrService as String: service, kSecAttrAccount as String: account,
                      kSecAttrSynchronizable as String: true, kSecValueData as String: data])
    }

    func data(account: String) -> Data? {
        items.first { $0[kSecAttrAccount as String] as? String == account }?[kSecValueData as String] as? Data
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?) {
        let matchedItems = items.filter { matches($0, query: query) }
        guard !matchedItems.isEmpty else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, matchedItems)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        guard let index = items.firstIndex(where: { matches($0, query: query) }) else { return errSecItemNotFound }
        items[index].merge(attributes) { _, new in new }
        return errSecSuccess
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        guard !items.contains(where: { matches($0, query: attributes) }) else { return errSecDuplicateItem }
        items.append(attributes)
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        let previousCount = items.count
        items.removeAll { matches($0, query: query) }
        return items.count == previousCount ? errSecItemNotFound : errSecSuccess
    }

    private func matches(_ item: [String: Any], query: [String: Any]) -> Bool {
        [kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrSynchronizable].allSatisfy { key in
            guard let expected = query[key as String] as? NSObject else { return true }
            return (item[key as String] as? NSObject) == expected
        }
    }
}
