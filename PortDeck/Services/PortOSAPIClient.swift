import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

enum PortOSAPIError: LocalizedError, Equatable {
    case authenticationRequired
    case invalidResponse
    case server(status: Int, message: String)
    case unreachable(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "PortOS rejected the password. Update the credential and try again."
        case .invalidResponse: "The host did not return a valid HTTP response."
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

    init(transport: any HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    func discover(baseURL: URL) async throws -> PortOSHealth {
        try await request(baseURL: baseURL, path: "/api/system/health")
    }

    func topology(baseURL: URL, password: String?) async throws -> PortOSTopology {
        try await request(baseURL: baseURL, path: "/api/instances", password: password)
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
private struct ServerErrorEnvelope: Decodable { let error: String?; let message: String? }
