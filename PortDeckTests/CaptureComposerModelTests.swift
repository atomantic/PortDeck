import XCTest
@testable import PortDeck

@MainActor
final class CaptureComposerModelTests: XCTestCase {
    func testOuterRejectionsPreserveBrainAndDictatedDailyLogDrafts() async throws {
        for destination in CaptureDestination.allCases {
            try await assertRejected(destination: destination, body: #"{"ok":false,"result":{"ok":true,"summary":"Server refused capture"}}"#)
        }
    }

    func testToolRejectionsPreserveBrainAndDictatedDailyLogDrafts() async throws {
        for destination in CaptureDestination.allCases {
            try await assertRejected(destination: destination, body: #"{"ok":true,"result":{"ok":false,"summary":"Server refused capture"}}"#)
        }
    }

    func testRejectionWithoutSummaryHasUsefulFallback() async {
        let model = draft()
        await submit(model, body: #"{"ok":true,"result":{"ok":false,"summary":"  "}}"#)
        assertRetained(model)
        XCTAssertEqual(model.message?.0, "Could not capture to Brain.")
    }

    func testAcceptedAndLegacyPaletteResponsesClearDraftForBothDestinations() async throws {
        for destination in CaptureDestination.allCases {
            for result in [#"{"ok":true,"summary":"Saved"}"#, #"{"summary":"Saved"}"#] {
                let model = draft()
                let transport = CaptureTransport(status: 200, body: "{\"ok\":true,\"result\":\(result)}")
                await model.submit(to: instance, destination: destination, date: date,
                                   api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
                XCTAssertEqual(model.text, "")
                XCTAssertEqual(model.transcript, "")
                XCTAssertFalse(model.usedDictation)
                XCTAssertFalse(model.isSubmitting)
                XCTAssertEqual(model.message?.0, "Saved")
                XCTAssertEqual(model.message?.1, .success)
                try await assertRequest(transport, destination: destination)
            }
        }
    }

    func testHTTPAuthenticationAndDecodingFailuresRetainDraft() async {
        for response in [(503, #"{"error":"Unavailable"}"#), (401, #"{"error":"Unauthorized"}"#), (200, "not json")] {
            let model = draft()
            await submit(model, status: response.0, body: response.1)
            assertRetained(model)
            XCTAssertFalse(model.message?.0.isEmpty ?? true)
        }
    }

    func testCredentialFailureRetainsDraftWithoutRequest() async {
        let model = draft()
        let transport = CaptureTransport(status: 200, body: "{}")
        await model.submit(to: instance, destination: .brain, date: date,
                           api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials(fails: true))
        assertRetained(model)
        let request = await transport.request
        XCTAssertNil(request)
    }

    func testTypedDailyLogStillUsesDirectEndpointAndClearsOnSuccess() async throws {
        let model = draft()
        model.usedDictation = false
        let transport = CaptureTransport(status: 200, body: #"{"date":"2026-10-24","entry":"Remember this"}"#)
        await model.submit(to: instance, destination: .dailyLog, date: date,
                           api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.transcript, "")
        XCTAssertEqual(model.message?.1, .success)
        let request = await transport.request
        XCTAssertEqual(request?.url?.path, "/api/brain/daily-log/2026-10-24/append")
    }

    private func assertRejected(destination: CaptureDestination, body: String) async throws {
        let model = draft()
        let transport = CaptureTransport(status: 200, body: body)
        await model.submit(to: instance, destination: destination, date: date,
                           api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
        assertRetained(model)
        XCTAssertEqual(model.message?.0, "Server refused capture")
        try await assertRequest(transport, destination: destination)
    }

    private func assertRetained(_ model: CaptureComposerModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.text, "  Remember this \n", file: file, line: line)
        XCTAssertEqual(model.transcript, "Remember this", file: file, line: line)
        XCTAssertTrue(model.usedDictation, file: file, line: line)
        XCTAssertEqual(model.message?.1, .error, file: file, line: line)
        XCTAssertFalse(model.isSubmitting, file: file, line: line)
    }

    private func assertRequest(_ transport: CaptureTransport, destination: CaptureDestination) async throws {
        let request = await transport.request
        XCTAssertEqual(request?.url?.host, "capture.example")
        XCTAssertEqual(request?.url?.path, destination == .brain ? "/api/palette/action/brain_capture" : "/api/palette/action/daily_log_append")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Basic \(Data(":fake-password".utf8).base64EncodedString())")
        let body = try XCTUnwrap(request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let args = try XCTUnwrap(json["args"] as? [String: Any])
        XCTAssertEqual(args["text"] as? String, "Remember this")
        if destination == .dailyLog { XCTAssertEqual(args["date"] as? String, "2026-10-24") }
    }

    private func submit(_ model: CaptureComposerModel, status: Int = 200, body: String) async {
        await model.submit(to: instance, destination: .brain, date: date,
                           api: PortOSAPIClient(transport: CaptureTransport(status: status, body: body)), credentials: CaptureCredentials())
    }

    private func draft() -> CaptureComposerModel {
        let model = CaptureComposerModel()
        model.text = "  Remember this \n"
        model.transcript = "Remember this"
        model.usedDictation = true
        return model
    }

    private var date: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
    }
    private var instance: PortOSInstance {
        PortOSInstance(baseURL: URL(string: "https://capture.example:5555")!,
                       health: PortOSHealth(status: "ok", hostname: "capture", instanceID: "capture", name: "Capture", authRequired: true))
    }
}

private struct CaptureCredentials: CredentialStore {
    var fails = false
    func password(for instanceID: UUID) throws -> String? {
        if fails { throw CredentialStoreError.invalidData }
        return "fake-password"
    }
    func setPassword(_ password: String, for instanceID: UUID) throws {}
    func removePassword(for instanceID: UUID) throws {}
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {}
}

private actor CaptureTransport: HTTPTransport {
    let status: Int
    let body: String
    private(set) var request: URLRequest?
    init(status: Int, body: String) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
