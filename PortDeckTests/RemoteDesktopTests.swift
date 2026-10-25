import XCTest
@testable import PortDeck

final class RemoteDesktopTests: XCTestCase {
    func testTailcatViewerRequiresExplicitServerCapability() throws {
        let oldJSON = Data(#"{"supported":true,"configured":true,"available":true,"requiresPortOSAuth":false,"platform":"darwin","port":5900,"setupCommand":"npm run setup:remote-desktop"}"#.utf8)
        let old = try JSONDecoder().decode(RemoteDesktopStatus.self, from: oldJSON)
        XCTAssertTrue(old.canOpen(usingTailcat: false))
        XCTAssertFalse(old.canOpen(usingTailcat: true))
        var advertised = try JSONSerialization.jsonObject(with: oldJSON) as! [String: Any]
        advertised["tailcatIngressSupported"] = true
        let supported = try JSONDecoder().decode(RemoteDesktopStatus.self, from: JSONSerialization.data(withJSONObject: advertised))
        XCTAssertTrue(supported.canOpen(usingTailcat: true))
        advertised["available"] = false
        let unavailable = try JSONDecoder().decode(RemoteDesktopStatus.self, from: JSONSerialization.data(withJSONObject: advertised))
        XCTAssertFalse(unavailable.canOpen(usingTailcat: true))
    }

    func testViewerURLStaysOnConfiguredInstanceOrigin() throws {
        let session = RemoteDesktopSession(
            viewerPath: "/remote-desktop?token=example-token",
            expiresAt: "2030-01-01T00:00:00Z"
        )

        let url = try session.viewerURL(relativeTo: URL(string: "https://host-xxxx.example:5555")!)

        XCTAssertEqual(url.absoluteString, "https://host-xxxx.example:5555/remote-desktop?token=example-token")
    }

    func testViewerURLRejectsAnotherOrigin() {
        let session = RemoteDesktopSession(
            viewerPath: "https://attacker.example/remote-desktop?token=example-token",
            expiresAt: "2030-01-01T00:00:00Z"
        )

        XCTAssertThrowsError(try session.viewerURL(relativeTo: URL(string: "https://host-xxxx.example:5555")!))
    }
}
