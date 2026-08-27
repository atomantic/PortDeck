import XCTest
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
