import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// Every redirect is checked before URLSession can send the next request.
struct OriginBoundTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, let origin = HTTPOrigin(url: url) else {
            throw PortOSAPIError.invalidResponse
        }
        let delegate = OriginRedirectDelegate(origin: origin, authorization: request.value(forHTTPHeaderField: "Authorization"))
        do {
            let result = try await session.data(for: request, delegate: delegate)
            try Task.checkCancellation()
            if delegate.rejectedRedirect { throw PortOSAPIError.redirectedOutsideInstance }
            return result
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if delegate.rejectedRedirect { throw PortOSAPIError.redirectedOutsideInstance }
            throw error
        }
    }
}

struct HTTPOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "https" ? 443 : 80)
    }
}

private final class OriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: HTTPOrigin
    private let authorization: String?
    private let lock = NSLock()
    private var rejected = false

    var rejectedRedirect: Bool { lock.withLock { rejected } }

    init(origin: HTTPOrigin, authorization: String?) {
        self.origin = origin
        self.authorization = authorization
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, HTTPOrigin(url: url) == origin else {
            lock.withLock { rejected = true }
            completionHandler(nil)
            return
        }
        // Foundation owns redirect method/body semantics. Restore the original
        // credential only after the hop has passed the original-origin check.
        var request = request
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        completionHandler(request)
    }
}

enum PortOSAPIError: LocalizedError, Equatable {
    case authenticationRequired
    case invalidResponse
    case redirectedOutsideInstance
    case server(status: Int, message: String)
    case unreachable(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "PortOS rejected the password. Update the credential and try again."
        case .invalidResponse: "The host did not return a valid HTTP response."
        case .redirectedOutsideInstance: "This PortOS instance redirected to a different server. Update its configured endpoint before trying again."
        case .server(let status, let message): "PortOS returned HTTP \(status): \(message)"
        case .unreachable(let message): "Could not reach this PortOS instance: \(message)"
        case .decoding(let message): "PortOS returned data this app does not understand: \(message)"
        }
    }
}

struct PortOSAPIClient: Sendable {
    private let transport: any HTTPTransport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(transport: any HTTPTransport = OriginBoundTransport()) {
        self.transport = transport
    }

    func discover(baseURL: URL) async throws -> PortOSHealth {
        try await request(baseURL: baseURL, path: "/api/system/health")
    }

    func topology(baseURL: URL, password: String?) async throws -> PortOSTopology {
        try await request(baseURL: baseURL, path: "/api/instances", password: password)
    }

    func remoteDesktopStatus(baseURL: URL, password: String?) async throws -> RemoteDesktopStatus {
        try await request(baseURL: baseURL, path: "/api/remote-desktop/status", password: password)
    }

    func createRemoteDesktopSession(baseURL: URL, password: String?) async throws -> RemoteDesktopSession {
        try await request(
            baseURL: baseURL,
            path: "/api/remote-desktop/sessions",
            method: "POST",
            password: password,
            body: Data("{}".utf8)
        )
    }

    func paletteManifest(baseURL: URL, password: String?) async throws -> PaletteManifest {
        try await request(baseURL: baseURL, path: "/api/palette/manifest", password: password)
    }

    func invokeAction(
        id: String,
        arguments: [String: JSONValue],
        baseURL: URL,
        password: String?
    ) async throws -> PaletteActionResponse {
        let body = try encoder.encode(ActionRequest(args: arguments))
        return try await request(
            baseURL: baseURL,
            path: "/api/palette/action/\(id)",
            method: "POST",
            password: password,
            body: body
        )
    }

    func appendDailyLog(
        text: String,
        date: String,
        source: String,
        baseURL: URL,
        password: String?
    ) async throws -> DailyLogResponse {
        let body = try encoder.encode(DailyLogRequest(text: text, source: source))
        return try await request(
            baseURL: baseURL,
            path: "/api/brain/daily-log/\(date)/append",
            method: "POST",
            password: password,
            body: body
        )
    }

    func assignableInstances(baseURL: URL, password: String?) async throws -> AssignableInstancesResponse {
        try await request(baseURL: baseURL, path: "/api/instances/assignable", password: password)
    }

    func createTask(
        description: String,
        targetInstanceID: String?,
        baseURL: URL,
        password: String?
    ) async throws -> CreatedTask {
        let body = try encoder.encode(CreateTaskRequest(
            description: description,
            type: "user",
            targetInstanceID: targetInstanceID
        ))
        return try await request(
            baseURL: baseURL,
            path: "/api/cos/tasks",
            method: "POST",
            password: password,
            body: body
        )
    }

    func renameSelf(name: String, baseURL: URL, password: String?) async throws -> PortOSIdentity {
        let body = try encoder.encode(RenameRequest(name: name))
        return try await request(
            baseURL: baseURL,
            path: "/api/instances/self",
            method: "PUT",
            password: password,
            body: body
        )
    }

    func probe(peerID: String, baseURL: URL, password: String?) async throws -> FederationPeer {
        try await request(
            baseURL: baseURL,
            path: "/api/instances/peers/\(peerID)/probe",
            method: "POST",
            password: password,
            body: Data("{}".utf8)
        )
    }

    func addPeer(
        address: String,
        host: String?,
        port: Int,
        name: String?,
        peerPassword: String?,
        baseURL: URL,
        password: String?
    ) async throws -> FederationPeer {
        var payload: [String: JSONValue] = [
            "address": .string(address),
            "port": .number(Double(port))
        ]
        if let host, !host.isEmpty { payload["host"] = .string(host) }
        if let name, !name.isEmpty { payload["name"] = .string(name) }
        if let peerPassword, !peerPassword.isEmpty {
            payload["auth"] = .object(["username": .string(""), "password": .string(peerPassword)])
        }
        return try await request(
            baseURL: baseURL,
            path: "/api/instances/peers",
            method: "POST",
            password: password,
            body: try encoder.encode(JSONValue.object(payload))
        )
    }

    func updatePeer(
        peerID: String,
        enabled: Bool? = nil,
        fullSync: Bool? = nil,
        baseURL: URL,
        password: String?
    ) async throws -> FederationPeer {
        var payload: [String: JSONValue] = [:]
        if let enabled { payload["enabled"] = .bool(enabled) }
        if let fullSync { payload["fullSync"] = .bool(fullSync) }
        return try await request(
            baseURL: baseURL,
            path: "/api/instances/peers/\(peerID)",
            method: "PUT",
            password: password,
            body: try encoder.encode(JSONValue.object(payload))
        )
    }

    func connect(peerID: String, baseURL: URL, password: String?) async throws -> FederationPeer {
        try await request(
            baseURL: baseURL,
            path: "/api/instances/peers/\(peerID)/connect",
            method: "POST",
            password: password,
            body: Data("{}".utf8)
        )
    }

    func removePeer(peerID: String, baseURL: URL, password: String?) async throws -> JSONValue {
        try await request(
            baseURL: baseURL,
            path: "/api/instances/peers/\(peerID)",
            method: "DELETE",
            password: password
        )
    }

    func sync(peerID: String, baseURL: URL, password: String?) async throws -> JSONValue {
        try await request(
            baseURL: baseURL,
            path: "/api/instances/peers/\(peerID)/sync",
            method: "POST",
            password: password,
            body: Data("{}".utf8)
        )
    }

    private func request<Response: Decodable>(
        baseURL: URL,
        path: String,
        method: String = "GET",
        password: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        let url = try makeURL(baseURL: baseURL, path: path)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let password, !password.isEmpty {
            let credential = Data(":\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            if let error = error as? PortOSAPIError { throw error }
            throw PortOSAPIError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw PortOSAPIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw PortOSAPIError.authenticationRequired }
        guard (200...299).contains(http.statusCode) else {
            let envelope = try? decoder.decode(ServerErrorEnvelope.self, from: data)
            let message = envelope?.message ?? envelope?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw PortOSAPIError.server(status: http.statusCode, message: message)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PortOSAPIError.decoding(error.localizedDescription)
        }
    }

    private func makeURL(baseURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PortOSAPIError.invalidResponse
        }
        components.path = path
        guard let url = components.url else { throw PortOSAPIError.invalidResponse }
        return url
    }
}

private struct ActionRequest: Encodable { let args: [String: JSONValue] }
private struct DailyLogRequest: Encodable { let text: String; let source: String }
private struct RenameRequest: Encodable { let name: String }
private struct CreateTaskRequest: Encodable {
    let description: String
    let type: String
    let targetInstanceID: String?

    enum CodingKeys: String, CodingKey {
        case description, type
        case targetInstanceID = "targetInstanceId"
    }
}
private struct ServerErrorEnvelope: Decodable { let error: String?; let message: String? }
