import XCTest
@testable import PortDeck

final class PortOSInstanceTests: XCTestCase {
    func testRemoteNameIsDefaultDisplayName() throws {
        let instance = PortOSInstance(
            baseURL: try XCTUnwrap(URL(string: "http://studio.tail123.ts.net:5555")),
            health: health(name: "Studio")
        )
        XCTAssertEqual(instance.displayName, "Studio")
        XCTAssertEqual(instance.connectionState, .online)
    }

    func testLocalLabelOverridesRemoteName() throws {
        let instance = PortOSInstance(
            baseURL: try XCTUnwrap(URL(string: "http://studio.tail123.ts.net:5555")),
            localLabel: "Main PortOS",
            health: health(name: "Studio")
        )
        XCTAssertEqual(instance.displayName, "Main PortOS")
    }

    func testAuthenticationFailureBecomesPasswordState() throws {
        let instance = PortOSInstance(
            baseURL: try XCTUnwrap(URL(string: "http://studio.tail123.ts.net:5555")),
            health: health(name: "Studio")
        )
        instance.markFailure(PortOSAPIError.authenticationRequired)
        XCTAssertEqual(instance.connectionState, .needsPassword)
        XCTAssertNotNil(instance.lastError)
    }

    private func health(name: String) -> PortOSHealth {
        PortOSHealth(
            status: "ok",
            version: "1.2.3",
            hostname: "studio",
            instanceID: "instance-1",
            name: name,
            authRequired: false,
            scheme: "http"
        )
    }
}
