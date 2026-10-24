import XCTest
import Network
@testable import PortDeck

final class PortOSAPIClientTests: XCTestCase {
    func testDiscoveryUsesPublicHealthWithoutAuthorization() async throws {
        let transport = MockTransport(statusCode: 200, body: """
        {
          "status": "ok",
          "hostname": "studio",
          "instanceId": "instance-1",
          "name": "Studio",
          "authRequired": true,
          "scheme": "https",
          "version": "1.2.3"
        }
        """)
        let client = PortOSAPIClient(transport: transport)
        let health = try await client.discover(baseURL: baseURL)

        XCTAssertEqual(health.name, "Studio")
        XCTAssertTrue(health.authRequired)
        let request = await transport.capturedRequest
        XCTAssertEqual(request?.url?.path, "/api/system/health")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testOlderHealthResponseFallsBackWithoutNewFields() async throws {
        let transport = MockTransport(statusCode: 200, body: """
        { "status": "ok", "hostname": "legacy-host", "version": "1.0.0" }
        """)
        let health = try await PortOSAPIClient(transport: transport).discover(baseURL: baseURL)
        XCTAssertEqual(health.name, "legacy-host")
        XCTAssertFalse(health.authRequired)
        XCTAssertFalse(health.authRequiredWasReported)
    }

    func testTopologySendsPasswordOnlyBasicCredential() async throws {
        let transport = MockTransport(statusCode: 200, body: "{ \"self\": null, \"peers\": [] }")
        let client = PortOSAPIClient(transport: transport)
        _ = try await client.topology(baseURL: baseURL, password: "secret")

        let request = await transport.capturedRequest
        let expected = Data(":secret".utf8).base64EncodedString()
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Basic \(expected)")
    }

    func testUnauthorizedResponseMapsToCredentialError() async {
        let transport = MockTransport(statusCode: 401, body: "{ \"error\": \"Unauthorized\" }")
        do {
            _ = try await PortOSAPIClient(transport: transport).topology(baseURL: baseURL, password: "wrong")
            XCTFail("Expected authentication error")
        } catch {
            XCTAssertEqual(error as? PortOSAPIError, .authenticationRequired)
        }
    }

    func testActionPostsPaletteEnvelope() async throws {
        let transport = MockTransport(statusCode: 200, body: """
        { "ok": true, "result": { "ok": true, "summary": "Captured" } }
        """)
        let response = try await PortOSAPIClient(transport: transport).invokeAction(
            id: "brain_capture",
            arguments: ["text": .string("Remember milk")],
            baseURL: baseURL,
            password: nil
        )
        XCTAssertEqual(response.result.summary, "Captured")
        let request = await transport.capturedRequest
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/api/palette/action/brain_capture")
        let body = try XCTUnwrap(request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let args = try XCTUnwrap(json["args"] as? [String: Any])
        XCTAssertEqual(args["text"] as? String, "Remember milk")
    }

    func testRemoteDesktopSessionUsesAuthenticatedInstanceEndpoint() async throws {
        let transport = MockTransport(statusCode: 201, body: """
        { "viewerPath": "/remote-desktop?token=example-token", "expiresAt": "2030-01-01T00:00:00Z" }
        """)
        let client = PortOSAPIClient(transport: transport)

        _ = try await client.createRemoteDesktopSession(baseURL: baseURL, password: "secret")

        let request = await transport.capturedRequest
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/api/remote-desktop/sessions")
        let expected = Data(":secret".utf8).base64EncodedString()
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Basic \(expected)")
    }

    func testAssignableInstancesUsesAuthenticatedSelectedHostAndEnvelope() async throws {
        let transport = MockTransport(statusCode: 200, body: """
        { "instances": [{ "instanceId": "runner-1", "name": "Studio", "isSelf": true }] }
        """)

        let response = try await PortOSAPIClient(transport: transport)
            .assignableInstances(baseURL: baseURL, password: "secret")

        XCTAssertEqual(response.instances, [AssignableInstance(instanceID: "runner-1", name: "Studio", isSelf: true)])
        let request = await transport.capturedRequest
        XCTAssertEqual(request?.url?.host, "studio.tail123.ts.net")
        XCTAssertEqual(request?.url?.path, "/api/instances/assignable")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Basic \(Data(":secret".utf8).base64EncodedString())")
    }

    func testCreateTaskTrimsAtCallerAndPropagatesExactServerTarget() async throws {
        let transport = MockTransport(statusCode: 200, body: #"{"id":"task-123","status":"pending"}"#)

        let task = try await PortOSAPIClient(transport: transport).createTask(
            description: "Ship the native composer",
            targetInstanceID: "server-runner-9",
            baseURL: baseURL,
            password: "secret"
        )

        XCTAssertEqual(task, CreatedTask(id: "task-123", status: "pending"))
        let request = await transport.capturedRequest
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/api/cos/tasks")
        let body = try XCTUnwrap(request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["description"] as? String, "Ship the native composer")
        XCTAssertEqual(json["type"] as? String, "user")
        XCTAssertEqual(json["targetInstanceId"] as? String, "server-runner-9")
    }

    func testCreateTaskOmitsTargetForAnyInstance() async throws {
        let transport = MockTransport(statusCode: 200, body: #"{"id":"task-124","status":"pending"}"#)

        _ = try await PortOSAPIClient(transport: transport).createTask(
            description: "Unpinned work",
            targetInstanceID: nil,
            baseURL: baseURL,
            password: nil
        )

        let request = await transport.capturedRequest
        let body = try XCTUnwrap(request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["targetInstanceId"])
    }

    func testCancellationIsNotConvertedToUnreachable() async {
        let client = PortOSAPIClient(transport: CancellationTransport())

        do {
            _ = try await client.discover(baseURL: baseURL)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private var baseURL: URL { URL(string: "https://studio.tail123.ts.net:5555")! }
}

private actor CancellationTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw CancellationError()
    }
}

private actor MockTransport: HTTPTransport {
    private let statusCode: Int
    private let body: Data
    private(set) var capturedRequest: URLRequest?

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = Data(body.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }
}


final class OriginBoundTransportTests: XCTestCase {
    func testOriginsNormalizeCaseAndDefaultPorts() throws {
        XCTAssertEqual(origin("HTTP://EXAMPLE.COM/path"), origin("http://example.com:80/other"))
        XCTAssertEqual(origin("https://EXAMPLE.com"), origin("https://example.com:443"))
        XCTAssertNotEqual(origin("http://example.com"), origin("https://example.com"))
        XCTAssertNotEqual(origin("http://example.com"), origin("http://example.com:81"))
        XCTAssertNotEqual(origin("http://example.com"), origin("http://other.example.com"))
        XCTAssertNil(origin("file:///private/data"))
    }

    func testCrossOrigin307And308NeverReachDestinationIncludingAfterAllowedHop() async throws {
        let target = try await LocalHTTPFixture.start { _ in .json(#"{"id":"wrong-instance","status":"pending"}"#) }
        defer { target.stop() }

        for status in [307, 308] {
            for changedOriginPart in ["host", "port", "scheme"] {
                for chained in [false, true] {
                    let source = try await LocalHTTPFixture.start { request in
                        if chained && request.path == "/api/cos/tasks" {
                            return .redirect(status, to: "/same-origin")
                        }
                        if request.path.hasPrefix("/receive") {
                            return .json(#"{"id":"wrong-instance","status":"pending"}"#)
                        }
                        let destination: String
                        switch changedOriginPart {
                        case "host": destination = "http://localhost:\(request.port)/receive?token=private-value"
                        case "scheme": destination = "https://127.0.0.1:\(request.port)/receive?token=private-value"
                        default: destination = "\(target.baseURL)/receive?token=private-value"
                        }
                        return .redirect(status, to: destination)
                    }
                    do {
                        for _ in 0..<2 { // A user retry must start at the configured origin again.
                            do {
                                _ = try await PortOSAPIClient().createTask(
                                    description: "private task body", targetInstanceID: nil,
                                    baseURL: source.baseURL, password: "private-password"
                                )
                                XCTFail("A redirected task must never report success")
                            } catch {
                                XCTAssertEqual(error as? PortOSAPIError, .redirectedOutsideInstance)
                                XCTAssertFalse(error.localizedDescription.contains("private-value"))
                                XCTAssertFalse(error.localizedDescription.contains("127.0.0.1"))
                            }
                        }
                        XCTAssertEqual(source.requests.count, chained ? 4 : 2)
                        XCTAssertEqual(source.connectionCount, chained ? 4 : 2)
                        XCTAssertEqual(target.requests.count, 0)
                    }
                    source.stop()
                }
            }
        }
    }

    func testSameOriginRelativeRedirectsRetainCredentialsAndPostBodies() async throws {
        for status in [307, 308] {
            let source = try await LocalHTTPFixture.start { request in
                request.path == "/api/cos/tasks"
                    ? .redirect(status, to: "/accepted")
                    : .json(#"{"id":"selected-instance","status":"pending"}"#)
            }
            defer { source.stop() }
            let result = try await PortOSAPIClient().createTask(
                description: "selected host task", targetInstanceID: "runner",
                baseURL: source.baseURL, password: "secret"
            )
            XCTAssertEqual(result.id, "selected-instance")
            let requests = source.requests
            XCTAssertEqual(requests.map(\.method), ["POST", "POST"])
            XCTAssertEqual(requests.map(\.path), ["/api/cos/tasks", "/accepted"])
            XCTAssertEqual(requests[0].body, requests[1].body)
            XCTAssertFalse(requests[0].body.isEmpty)
            XCTAssertEqual(requests.map { $0.headers["authorization"] }, Array(repeating: basicCredential, count: 2))
        }
    }

    func testSameOrigin303KeepsFoundationMethodSemantics() async throws {
        let source = try await LocalHTTPFixture.start { request in
            request.path == "/api/cos/tasks" ? .redirect(303, to: "/accepted")
                : .json(#"{"id":"selected-instance","status":"pending"}"#)
        }
        defer { source.stop() }
        _ = try await PortOSAPIClient().createTask(
            description: "private", targetInstanceID: nil, baseURL: source.baseURL, password: "secret"
        )
        XCTAssertEqual(source.requests.map(\.method), ["POST", "GET"])
        XCTAssertTrue(source.requests[1].body.isEmpty)
        XCTAssertEqual(source.requests[1].headers["authorization"], basicCredential)
    }

    func testDirectNativeDiscoveryTopologyCaptureAndTaskRemainUsable() async throws {
        let source = try await LocalHTTPFixture.start { request in
            switch request.path {
            case "/api/system/health": .json(#"{"status":"ok","hostname":"selected"}"#)
            case "/api/instances": .json(#"{"self":null,"peers":[]}"#)
            case "/api/brain/daily-log/2026-10-24/append": .json(#"{"date":"2026-10-24","entry":"captured"}"#)
            default: .json(#"{"id":"task","status":"pending"}"#)
            }
        }
        defer { source.stop() }
        let client = PortOSAPIClient()
        let health = try await client.discover(baseURL: source.baseURL)
        XCTAssertEqual(health.hostname, "selected")
        _ = try await client.topology(baseURL: source.baseURL, password: "secret")
        _ = try await client.appendDailyLog(text: "private note", date: "2026-10-24", source: "ios", baseURL: source.baseURL, password: "secret")
        _ = try await client.createTask(description: "work", targetInstanceID: nil, baseURL: source.baseURL, password: nil)
        XCTAssertEqual(source.requests.map(\.method), ["GET", "GET", "POST", "POST"])
        XCTAssertEqual(source.requests.map { $0.headers["authorization"] }, [nil, basicCredential, basicCredential, nil])
    }

    func testCancellationDoesNotDisableOriginBoundRetry() async throws {
        let received = expectation(description: "Initial request received")
        let target = try await LocalHTTPFixture.start { _ in .json(#"{"id":"wrong","status":"pending"}"#) }
        defer { target.stop() }
        let source = try await LocalHTTPFixture.start { request in
            if request.path == "/hang" {
                received.fulfill()
                return nil
            }
            return .redirect(307, to: target.baseURL.appendingPathComponent("receive").absoluteString)
        }
        defer { source.stop() }
        let transport = OriginBoundTransport()
        let task = Task {
            try await transport.data(for: URLRequest(url: source.baseURL.appendingPathComponent("hang")))
        }
        await fulfillment(of: [received], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        do {
            _ = try await PortOSAPIClient(transport: transport).createTask(
                description: "retry", targetInstanceID: nil, baseURL: source.baseURL, password: "secret"
            )
            XCTFail("Retry must still reject an out-of-origin hop")
        } catch {
            XCTAssertEqual(error as? PortOSAPIError, .redirectedOutsideInstance)
        }
        XCTAssertEqual(target.requests.count, 0)
        XCTAssertEqual(source.requests.count, 2)
    }

    func testFixtureDetectsBodyReplayWithUnrestrictedURLSession() async throws {
        // A positive control for the fixture: reverting the production default to
        // this transport would deliver the body and make the refusal tests fail.
        let target = try await LocalHTTPFixture.start { _ in .json(#"{"id":"wrong","status":"pending"}"#) }
        defer { target.stop() }
        let source = try await LocalHTTPFixture.start { _ in .redirect(307, to: target.baseURL.absoluteString) }
        defer { source.stop() }
        _ = try await PortOSAPIClient(transport: URLSession.shared).createTask(
            description: "replay control", targetInstanceID: nil, baseURL: source.baseURL, password: "secret"
        )
        XCTAssertEqual(target.requests.count, 1)
        XCTAssertEqual(target.requests.first?.method, "POST")
        XCTAssertEqual(target.requests.first?.body, source.requests.first?.body)
        XCTAssertFalse(target.requests[0].body.isEmpty)
    }

    private var basicCredential: String { "Basic \(Data(":secret".utf8).base64EncodedString())" }
    private func origin(_ value: String) -> HTTPOrigin? { HTTPOrigin(url: URL(string: value)!) }
}

/// A real TCP fixture: records accepted connections and complete HTTP requests,
/// including bodies. No URLProtocol stub bypasses URLSession's redirect machinery.
private final class LocalHTTPFixture: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
        let port: UInt16
    }

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: String

        static func json(_ body: String) -> Self {
            Self(status: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        static func redirect(_ status: Int, to location: String) -> Self {
            Self(status: status, headers: ["Location": location], body: "")
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "PortDeckTests.HTTPFixture")
    private let handler: @Sendable (Request) -> Response?
    private let lock = NSLock()
    private var recordedRequests: [Request] = []
    private var connections: [NWConnection] = []

    var requests: [Request] { lock.withLock { recordedRequests } }
    var connectionCount: Int { lock.withLock { connections.count } }
    var port: UInt16 { listener.port!.rawValue }
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private init(handler: @escaping @Sendable (Request) -> Response?) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.handler = handler
    }

    static func start(handler: @escaping @Sendable (Request) -> Response?) async throws -> LocalHTTPFixture {
        let fixture = try LocalHTTPFixture(handler: handler)
        fixture.listener.newConnectionHandler = { [weak fixture] connection in
            guard let fixture else { connection.cancel(); return }
            fixture.lock.withLock { fixture.connections.append(connection) }
            connection.start(queue: fixture.queue)
            fixture.receive(connection, bytes: Data())
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            fixture.listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    fixture.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    fixture.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            fixture.listener.start(queue: fixture.queue)
        }
        return fixture
    }

    func stop() {
        listener.cancel()
        let active = lock.withLock { connections }
        active.forEach { $0.cancel() }
    }

    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            var bytes = bytes
            if let chunk { bytes.append(chunk) }
            if let request = self.parse(bytes) {
                self.lock.withLock { self.recordedRequests.append(request) }
                guard let response = self.handler(request) else { return }
                var text = "HTTP/1.1 \(response.status) Fixture\r\nConnection: close\r\nContent-Length: \(response.body.utf8.count)\r\n"
                for (key, value) in response.headers { text += "\(key): \(value)\r\n" }
                text += "\r\n\(response.body)"
                connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if !complete && error == nil {
                self.receive(connection, bytes: bytes)
            } else {
                connection.cancel()
            }
        }
    }

    private func parse(_ data: Data) -> Request? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = Data(data[boundary.upperBound...])
        guard body.count >= length else { return nil }
        return Request(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(body.prefix(length)), port: port)
    }
}
