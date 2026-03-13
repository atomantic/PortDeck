import XCTest
@testable import PortOS_Recall

final class AudioEncryptionTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_audio_\(UUID().uuidString).m4a")

        // Create test data
        let originalData = Data("This is test audio data for encryption testing".utf8)
        try originalData.write(to: testFile)

        defer { try? FileManager.default.removeItem(at: testFile) }

        // Encrypt
        guard let encryptedURL = AudioEncryption.encrypt(fileAt: testFile) else {
            XCTFail("Encryption returned nil")
            return
        }

        defer { try? FileManager.default.removeItem(at: encryptedURL) }

        // Verify encrypted file exists and differs from original
        let encryptedData = try Data(contentsOf: encryptedURL)
        XCTAssertNotEqual(encryptedData, originalData)

        // Decrypt
        guard let decryptedData = AudioEncryption.decrypt(fileAt: encryptedURL) else {
            XCTFail("Decryption returned nil")
            return
        }

        // Verify round-trip
        XCTAssertEqual(decryptedData, originalData)
    }

    func testEncryptNonexistentFile() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/audio.m4a")
        let result = AudioEncryption.encrypt(fileAt: fakeURL)
        XCTAssertNil(result)
    }

    func testDecryptInvalidData() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("invalid_\(UUID().uuidString).encrypted")

        let invalidData = Data("not encrypted data".utf8)
        try invalidData.write(to: testFile)

        defer { try? FileManager.default.removeItem(at: testFile) }

        let result = AudioEncryption.decrypt(fileAt: testFile)
        XCTAssertNil(result)
    }
}
