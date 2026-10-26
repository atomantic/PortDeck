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

    func testRejectionWithoutUsefulSummaryHasFallbackForBothDestinations() async {
        for destination in CaptureDestination.allCases {
            for result in [#"{"ok":false}"#, #"{"ok":false,"summary":"  "}"#] {
                let model = draft()
                let transport = CaptureTransport(status: 200, body: "{\"ok\":true,\"result\":\(result)}")
                await model.submit(to: instance, destination: destination, date: date,
                                   api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
                assertRetained(model)
                XCTAssertNil(model.acceptedCapture)
                XCTAssertEqual(model.message?.0, destination == .brain
                               ? "Could not capture to Brain." : "Could not add to the daily log.")
            }
        }
    }

    func testAcceptedPaletteResponsesWithoutSummaryUseDestinationFallback() async throws {
        for destination in CaptureDestination.allCases {
            for result in [#"{"ok":true}"#, "{}"] {
                let model = draft()
                let transport = CaptureTransport(status: 200, body: "{\"ok\":true,\"result\":\(result)}")
                await model.submit(to: instance, destination: destination, date: date,
                                   api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
                let summary = destination == .brain ? "Captured to Brain." : "Added to the daily log."
                XCTAssertEqual(model.message?.0, summary)
                XCTAssertEqual(model.message?.1, .success)
                XCTAssertEqual(model.acceptedCapture?.summary, summary)
                XCTAssertEqual(model.text, "")
                XCTAssertEqual(model.transcript, "")
                XCTAssertFalse(model.usedDictation)
                XCTAssertFalse(model.isSubmitting)
                try await assertRequest(transport, destination: destination)
            }
        }
    }

    func testEmptyDraftAndInvalidURLLeaveDraftAndExistingReceiptUnchanged() async {
        for invalidURL in [false, true] {
            let model = draft()
            await submit(model, body: #"{"ok":true,"result":{"summary":"Already saved"}}"#)
            let originalSelection = model.selection
            let originalProfileID = model.acceptedCapture?.profileID
            model.text = invalidURL ? "New draft" : " \n\t "
            model.transcript = "New transcript"
            model.usedDictation = true
            let originalText = model.text
            let profile = instance
            if invalidURL {
                profile.baseURLString = "http://["
                XCTAssertNil(profile.baseURL)
            }
            let transport = CaptureTransport(status: 200, body: "{}")
            await model.submit(to: profile, destination: .dailyLog, date: date.addingTimeInterval(86_400),
                               api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials(fails: true))

            let requestCount = await transport.requestCount
            XCTAssertEqual(requestCount, 0)
            XCTAssertEqual(model.text, originalText)
            XCTAssertEqual(model.transcript, "New transcript")
            XCTAssertTrue(model.usedDictation)
            XCTAssertEqual(model.selection, originalSelection)
            XCTAssertEqual(model.acceptedCapture?.profileID, originalProfileID)
            XCTAssertEqual(model.acceptedCapture?.summary, "Already saved")
            XCTAssertEqual(model.message?.0, "Already saved")
            XCTAssertEqual(model.message?.1, .success)
            XCTAssertFalse(model.isSubmitting)
        }
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

    func testSuspendedAcceptanceClearsUntouchedDraftAndPostsOriginalSnapshotExactlyOnce() async throws {
        for destination in CaptureDestination.allCases {
            for dictated in [false, true] {
                let model = draft()
                model.usedDictation = dictated
                let profile = instance
                let transport = gatedTransport(destination: destination, dictated: dictated)
                let api = PortOSAPIClient(transport: transport)
                let credentials = CaptureCredentials(expectedProfileID: profile.localID)
                let submission = Task {
                    await model.submit(to: profile, destination: destination, date: date,
                                       api: api, credentials: credentials)
                }
                await transport.waitUntilRequestStarts()
                XCTAssertTrue(model.isSubmitting)
                // A second send cannot create another request while the first owns submission.
                await model.submit(to: profile, destination: .brain, date: date,
                                   api: api, credentials: credentials)
                await transport.releaseRequest()
                await submission.value

                XCTAssertEqual(model.text, "")
                XCTAssertEqual(model.transcript, "")
                XCTAssertFalse(model.usedDictation)
                XCTAssertFalse(model.isSubmitting)
                XCTAssertEqual(model.acceptedCapture?.profileID, profile.localID)
                XCTAssertEqual(model.acceptedCapture?.destination, destination)
                XCTAssertEqual(model.acceptedCapture?.date, "2026-10-24")
                try await assertSnapshot(transport, destination: destination, dictated: dictated)
            }
        }
    }

    func testSameProfileTypingAndDictationPreserveNewDraftAfterAcceptance() async {
        for dictated in [false, true] {
            let model = draft()
            model.usedDictation = false
            let profile = instance
            let transport = gatedTransport()
            let submission = Task {
                await model.submit(to: profile, destination: .brain, date: date,
                                   api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
            }
            await transport.waitUntilRequestStarts()
            if dictated {
                model.receiveTranscript("A newly dictated draft")
                model.usedDictation = true
            } else {
                model.text = "A newly typed draft"
            }
            let newText = model.text
            let newTranscript = model.transcript
            await transport.releaseRequest()
            await submission.value

            XCTAssertEqual(model.text, newText)
            XCTAssertEqual(model.transcript, newTranscript)
            XCTAssertEqual(model.usedDictation, dictated)
            XCTAssertEqual(model.acceptedCapture?.summary, "Saved")
            XCTAssertEqual(model.message?.1, .success)
        }
    }

    func testEachChangedThenRestoredDraftFieldStillBelongsToNewRevision() async {
        let edits: [(CaptureComposerModel) -> Void] = [
            { $0.text = "Temporary edit"; $0.text = "  Remember this \n" },
            { $0.transcript = "Temporary transcript"; $0.transcript = "Remember this" },
            { $0.usedDictation = false; $0.usedDictation = true }
        ]
        for edit in edits {
            let model = draft()
            let transport = gatedTransport()
            let submission = Task {
                await model.submit(to: instance, destination: .brain, date: date,
                                   api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
            }
            await transport.waitUntilRequestStarts()
            edit(model)
            await transport.releaseRequest()
            await submission.value

            XCTAssertEqual(model.text, "  Remember this \n")
            XCTAssertEqual(model.transcript, "Remember this")
            XCTAssertTrue(model.usedDictation)
            XCTAssertEqual(model.message?.1, .success)
        }
    }

    func testProfileDestinationAndDateSwitchesPreserveDraftAndOriginalReceipt() async throws {
        for change in 0..<3 {
            for restoreSelection in [false, true] {
                let model = draft()
                let profile = instance
                let original = CaptureComposerModel.Selection(profileID: profile.localID, destination: .dailyLog, date: date)
                let transport = gatedTransport(destination: .dailyLog)
                let submission = Task {
                    await model.submit(to: profile, destination: .dailyLog, date: date,
                                       api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
                }
                await transport.waitUntilRequestStarts()
                model.selection = .init(
                    profileID: change == 0 ? UUID() : profile.localID,
                    destination: change == 1 ? .brain : .dailyLog,
                    date: change == 2 ? date.addingTimeInterval(86_400) : date
                )
                if restoreSelection { model.selection = original }
                model.text = "New target draft"
                await transport.releaseRequest()
                await submission.value

                XCTAssertEqual(model.text, "New target draft")
                XCTAssertEqual(model.transcript, "Remember this")
                XCTAssertTrue(model.usedDictation)
                XCTAssertEqual(model.acceptedCapture?.profileID, profile.localID)
                XCTAssertEqual(model.acceptedCapture?.profileName, "Capture")
                XCTAssertEqual(model.acceptedCapture?.destination, .dailyLog)
                XCTAssertEqual(model.acceptedCapture?.date, "2026-10-24")
                XCTAssertEqual(model.acceptedCapture?.attribution, "Capture · Daily Log for 2026-10-24")
                XCTAssertEqual(model.acceptedCapture?.summary, "Saved")
                try await assertSnapshot(transport, destination: .dailyLog, dictated: true)
                // Selection changes after completion also retain the accepted receipt.
                model.selection = .init(profileID: UUID(), destination: .brain, date: date)
                XCTAssertEqual(model.acceptedCapture?.attribution, "Capture · Daily Log for 2026-10-24")
            }
        }
    }

    func testSelectionChangeWithoutTextEditPreservesSubmittedDraftAsCurrentDraft() async {
        let model = draft()
        let profile = instance
        let transport = gatedTransport()
        let submission = Task {
            await model.submit(to: profile, destination: .brain, date: date,
                               api: PortOSAPIClient(transport: transport), credentials: CaptureCredentials())
        }
        await transport.waitUntilRequestStarts()
        let original = model.selection
        model.selection = .init(profileID: UUID(), destination: .dailyLog, date: date)
        model.selection = original
        await transport.releaseRequest()
        await submission.value

        XCTAssertEqual(model.text, "  Remember this \n")
        XCTAssertEqual(model.transcript, "Remember this")
        XCTAssertTrue(model.usedDictation)
    }

    private func gatedTransport(destination: CaptureDestination = .brain, dictated: Bool = true) -> CaptureTransport {
        let body = destination == .dailyLog && !dictated
            ? #"{"date":"2026-10-24","entry":"Remember this"}"#
            : #"{"ok":true,"result":{"ok":true,"summary":"Saved"}}"#
        return CaptureTransport(status: 200, body: body, suspended: true)
    }

    private func assertSnapshot(_ transport: CaptureTransport, destination: CaptureDestination, dictated: Bool) async throws {
        let count = await transport.requestCount
        XCTAssertEqual(count, 1)
        if destination == .dailyLog && !dictated {
            let request = await transport.request
            XCTAssertEqual(request?.url?.host, "capture.example")
            XCTAssertEqual(request?.url?.path, "/api/brain/daily-log/2026-10-24/append")
            XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Basic \(Data(":fake-password".utf8).base64EncodedString())")
            let body = try XCTUnwrap(request?.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["text"] as? String, "Remember this")
            XCTAssertEqual(json["source"] as? String, "text")
        } else {
            try await assertRequest(transport, destination: destination)
        }
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
    var expectedProfileID: UUID?
    func password(for instanceID: UUID) throws -> String? {
        if fails { throw CredentialStoreError.invalidData }
        return expectedProfileID == nil || expectedProfileID == instanceID ? "fake-password" : "wrong-profile"
    }
    func setPassword(_ password: String, for instanceID: UUID) throws {}
    func removePassword(for instanceID: UUID) throws {}
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {}
}

private actor CaptureTransport: HTTPTransport {
    let status: Int
    let body: String
    let suspended: Bool
    private(set) var request: URLRequest?
    private(set) var requestCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    init(status: Int, body: String, suspended: Bool = false) {
        self.status = status
        self.body = body
        self.suspended = suspended
    }

    func waitUntilRequestStarts() async {
        if request != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseRequest() {
        release?.resume()
        release = nil
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        requestCount += 1
        if suspended {
            await withCheckedContinuation { continuation in
                release = continuation
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
            }
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
