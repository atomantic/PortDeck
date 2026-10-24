import Foundation
import Security
@testable import PortDeck

/// Stores the actual attributes and bytes sent by the adapter; no real Keychain access.
final class InMemoryKeychainItemClient: KeychainItemClient, @unchecked Sendable {
    enum Operation { case read, update, add, delete }
    struct Call {
        let operation: Operation
        let query: [String: Any]
    }
    struct Failure {
        let operation: Operation
        let status: OSStatus
        var synchronizable: Bool? = nil
    }

    private var items: [[String: Any]] = []
    private(set) var calls: [Call] = []
    var failures: [Failure] = []

    func seed(service: String, account: String, data: Data, synchronizable: Bool = true) {
        items.append([kSecClass as String: kSecClassGenericPassword,
                      kSecAttrService as String: service, kSecAttrAccount as String: account,
                      kSecAttrSynchronizable as String: synchronizable, kSecValueData as String: data])
    }

    func attributes(service: String, account: String, synchronizable: Bool) -> [String: Any]? {
        items.first { matches($0, query: [kSecAttrService as String: service,
                                         kSecAttrAccount as String: account,
                                         kSecAttrSynchronizable as String: synchronizable]) }
    }

    func data(account: String) -> Data? {
        items.first { $0[kSecAttrAccount as String] as? String == account }?[kSecValueData as String] as? Data
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?) {
        if let status = record(.read, query) { return (status, nil) }
        let matchedItems = items.filter { matches($0, query: query) }
        guard !matchedItems.isEmpty else { return (errSecItemNotFound, nil) }
        if query[kSecReturnAttributes as String] as? Bool != true {
            return (errSecSuccess, matchedItems[0][kSecValueData as String])
        }
        if query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String {
            return (errSecSuccess, matchedItems[0])
        }
        return (errSecSuccess, matchedItems)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        if let status = record(.update, query) { return status }
        guard let index = items.firstIndex(where: { matches($0, query: query) }) else { return errSecItemNotFound }
        items[index].merge(attributes) { _, new in new }
        return errSecSuccess
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        if let status = record(.add, attributes) { return status }
        guard !items.contains(where: { matches($0, query: attributes) }) else { return errSecDuplicateItem }
        items.append(attributes)
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if let status = record(.delete, query) { return status }
        let previousCount = items.count
        items.removeAll { matches($0, query: query) }
        return items.count == previousCount ? errSecItemNotFound : errSecSuccess
    }

    private func record(_ operation: Operation, _ query: [String: Any]) -> OSStatus? {
        calls.append(Call(operation: operation, query: query))
        guard let index = failures.firstIndex(where: {
            $0.operation == operation && ($0.synchronizable == nil
                || $0.synchronizable == query[kSecAttrSynchronizable as String] as? Bool)
        }) else { return nil }
        return failures.remove(at: index).status
    }

    private func matches(_ item: [String: Any], query: [String: Any]) -> Bool {
        [kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrSynchronizable].allSatisfy { key in
            guard let expected = query[key as String] as? NSObject else { return true }
            return (item[key as String] as? NSObject) == expected
        }
    }
}
