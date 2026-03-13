import Foundation
import CryptoKit
import Security

enum AudioEncryption {
    private static let keychainService = "net.shadowpuppet.PortOSRecall.audioKey"
    private static let keychainAccount = "deviceEncryptionKey"

    static func encrypt(fileAt url: URL) -> URL? {
        guard let key = getOrCreateKey(),
              let data = try? Data(contentsOf: url) else { return nil }

        guard let sealedBox = try? AES.GCM.seal(data, using: key) else { return nil }
        guard let combined = sealedBox.combined else { return nil }

        let encryptedURL = url.appendingPathExtension("encrypted")
        try? combined.write(to: encryptedURL)

        RecallLogger.info("Encrypted audio file: \(url.lastPathComponent)")
        return encryptedURL
    }

    static func decrypt(fileAt url: URL) -> Data? {
        guard let key = getOrCreateKey(),
              let data = try? Data(contentsOf: url) else { return nil }

        guard let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decryptedData = try? AES.GCM.open(sealedBox, using: key) else { return nil }

        RecallLogger.info("Decrypted audio file: \(url.lastPathComponent)")
        return decryptedData
    }

    // In-memory fallback when Keychain is unavailable (e.g., tests)
    private static var cachedKey: SymmetricKey?

    private static func getOrCreateKey() -> SymmetricKey? {
        if let existingKey = loadKeyFromKeychain() {
            cachedKey = existingKey
            return existingKey
        }
        if let cached = cachedKey {
            return cached
        }
        let newKey = SymmetricKey(size: .bits256)
        cachedKey = newKey
        saveKeyToKeychain(newKey)
        return newKey
    }

    private static func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
