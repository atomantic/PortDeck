import XCTest
@testable import PortDeck

final class PortOSEndpointTests: XCTestCase {
    func testNormalizesMagicDNSHostWithContractPort() throws {
        let url = try PortOSEndpoint.normalize("studio.tail123.ts.net")
        XCTAssertEqual(url.absoluteString, "http://studio.tail123.ts.net:5555")
    }

    func testPreservesHTTPSAndExplicitPort() throws {
        let url = try PortOSEndpoint.normalize("https://studio.tail123.ts.net:8443/")
        XCTAssertEqual(url.absoluteString, "https://studio.tail123.ts.net:8443")
    }

    func testBuildsTailscaleIPAddressEndpoint() throws {
        let url = try PortOSEndpoint.make(scheme: "http", host: "100.101.102.103", port: 5555)
        XCTAssertEqual(url.absoluteString, "http://100.101.102.103:5555")
    }

    func testRejectsAPIPath() {
        XCTAssertThrowsError(try PortOSEndpoint.normalize("http://studio.tail123.ts.net:5555/api/system/health")) { error in
            XCTAssertEqual(error as? PortOSEndpointError, .containsPath)
        }
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try PortOSEndpoint.normalize("ftp://studio.tail123.ts.net")) { error in
            XCTAssertEqual(error as? PortOSEndpointError, .unsupportedScheme)
        }
    }
}
