import SwiftData
import XCTest
@testable import PortDeck

@MainActor
final class FleetModelStoreTests: XCTestCase {
    func testFirstLaunchCreatesMissingDirectoryAndReopensSavedFleet() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Library/Application Support/default.store")
        let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        let localID = UUID()
        try saveFleet(configuration: configuration, localID: localID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reopened = try FleetModelStore.makeContainer(configuration: configuration)
        let fleet = try reopened.mainContext.fetch(FetchDescriptor<PortOSInstance>())
        XCTAssertEqual(fleet.count, 1)
        XCTAssertEqual(fleet.first?.localID, localID)
        XCTAssertEqual(fleet.first?.localLabel, "Saved fleet")
    }

    func testDirectoryCreationFailurePropagatesWithoutReplacingExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let parent = root.appendingPathComponent("Application Support")
        let contents = Data("existing file".utf8)
        try contents.write(to: parent)
        let configuration = ModelConfiguration(
            url: parent.appendingPathComponent("default.store"), cloudKitDatabase: .none
        )

        XCTAssertThrowsError(try FleetModelStore.makeContainer(configuration: configuration))
        XCTAssertEqual(try Data(contentsOf: parent), contents)
    }

    func testInMemoryStoreDoesNotPersistInsertedFleet() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        try saveFleet(configuration: configuration, localID: UUID())
        let reopened = try FleetModelStore.makeContainer(configuration: configuration)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<PortOSInstance>()), 0)
    }

    private func saveFleet(configuration: ModelConfiguration, localID: UUID) throws {
        let container = try FleetModelStore.makeContainer(configuration: configuration)
        container.mainContext.insert(PortOSInstance(
            localID: localID,
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:5555")),
            localLabel: "Saved fleet",
            health: PortOSHealth(
                status: "ok", version: "1.0.0", hostname: "fixture", instanceID: "fixture",
                name: "Fixture", authRequired: false, scheme: "http"
            )
        ))
        try container.mainContext.save()
    }
}
