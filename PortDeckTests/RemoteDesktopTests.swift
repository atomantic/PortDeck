import XCTest
@testable import PortDeck

final class RemoteDesktopTests: XCTestCase {
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
