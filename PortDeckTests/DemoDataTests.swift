import SwiftData
import XCTest
@testable import PortDeck

@MainActor
final class DemoDataTests: XCTestCase {
    func testDemoSeedIsDeterministicAndIdempotent() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PortOSInstance.self, configurations: configuration)

        try DemoData.seed(modelContext: container.mainContext)
        try DemoData.seed(modelContext: container.mainContext)

        let instances = try container.mainContext.fetch(FetchDescriptor<PortOSInstance>())
        XCTAssertEqual(instances.count, 3)
        XCTAssertEqual(instances.first(where: { $0.localID == DemoData.primaryInstanceID })?.displayName, "Atlas Studio")
        XCTAssertTrue(instances.allSatisfy { $0.connectionState == .online })
    }

    func testDemoTransportProvidesFleetAndActionResponses() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://atlas-studio.demo.ts.net:5555"))
        let client = PortOSAPIClient(transport: DemoHTTPTransport())

        let topology = try await client.topology(baseURL: baseURL, password: nil)
        let manifest = try await client.paletteManifest(baseURL: baseURL, password: nil)

        XCTAssertEqual(topology.peers.count, 2)
        XCTAssertEqual(topology.selfIdentity?.name, "Atlas Studio")
        XCTAssertTrue(manifest.actions.contains(where: { $0.id == "focus_start" }))
        XCTAssertTrue(manifest.actions.contains(where: { $0.destructive == true }))
    }
}
