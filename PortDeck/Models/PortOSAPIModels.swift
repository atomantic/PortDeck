import Foundation

struct PortOSHealth: Decodable, Equatable, Sendable {
    let status: String
    let timestamp: String?
    let uptime: Double?
    let version: String?
    let hostname: String
    let instanceID: String?
    let name: String
    let authRequired: Bool
    let authRequiredWasReported: Bool
    let scheme: String?

    enum CodingKeys: String, CodingKey {
        case status, timestamp, uptime, version, hostname, name, authRequired, scheme
        case instanceID = "instanceId"
    }

    init(
        status: String,
        timestamp: String? = nil,
        uptime: Double? = nil,
        version: String? = nil,
        hostname: String,
        instanceID: String? = nil,
        name: String,
        authRequired: Bool,
        authRequiredWasReported: Bool = true,
        scheme: String? = nil
    ) {
        self.status = status
        self.timestamp = timestamp
        self.uptime = uptime
        self.version = version
        self.hostname = hostname
        self.instanceID = instanceID
        self.name = name
        self.authRequired = authRequired
        self.authRequiredWasReported = authRequiredWasReported
        self.scheme = scheme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        uptime = try container.decodeIfPresent(Double.self, forKey: .uptime)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        hostname = try container.decode(String.self, forKey: .hostname)
        instanceID = try container.decodeIfPresent(String.self, forKey: .instanceID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? hostname
        authRequiredWasReported = container.contains(.authRequired)
        authRequired = try container.decodeIfPresent(Bool.self, forKey: .authRequired) ?? false
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
    }
}

struct PortOSIdentity: Codable, Equatable, Sendable {
    let instanceID: String?
    let name: String?
    let defaultPeerFullSync: Bool?

    enum CodingKeys: String, CodingKey {
        case name, defaultPeerFullSync
        case instanceID = "instanceId"
    }
}

struct PortOSTopology: Decodable, Sendable {
    let selfIdentity: PortOSIdentity?
    let peers: [FederationPeer]

    enum CodingKeys: String, CodingKey {
        case selfIdentity = "self"
        case peers
    }
}

struct FederationPeer: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let instanceID: String?
    let name: String
    let address: String
    let host: String?
    let port: Int
    let status: String
    let enabled: Bool
    let syncEnabled: Bool?
    let fullSync: Bool?
    let lastSeen: String?
    let authRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, address, host, port, status, enabled, syncEnabled, fullSync, lastSeen, authRequired
        case instanceID = "instanceId"
    }
}

struct PaletteManifest: Codable, Sendable {
    let actions: [PaletteAction]
}

struct PaletteAction: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let section: String
    let description: String
    let destructive: Bool?
    let parameters: ActionParameters
}

struct ActionParameters: Codable, Equatable, Sendable {
    let type: String?
    let properties: [String: ActionParameter]
    let required: [String]?
}

struct ActionParameter: Codable, Equatable, Sendable {
    let type: String?
    let description: String?
    let allowedValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description
        case allowedValues = "enum"
    }
}

struct PaletteActionResponse: Decodable, Sendable {
    let ok: Bool
    let result: JSONValue
}

struct DailyLogResponse: Decodable, Sendable {
    let date: String
    let entry: JSONValue
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// `false` for containers, so callers can decide between an inline value and a nested render.
    var isScalar: Bool {
        switch self {
        case .object, .array: false
        default: true
        }
    }

    var summary: String? { objectValue?["summary"]?.stringValue }

    /// PortOS tools report failure as `ok: false` inside an HTTP 200 envelope.
    var okFlag: Bool? { objectValue?["ok"]?.boolValue }

    var prettyPrinted: String { encoded(with: .pretty) }

    var compactJSON: String { encoded(with: .compact) }

    private func encoded(with encoder: JSONEncoder) -> String {
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else { return String(describing: self) }
        return string
    }
}

private extension JSONEncoder {
    static let pretty = make(pretty: true)
    static let compact = make(pretty: false)

    private static func make(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
