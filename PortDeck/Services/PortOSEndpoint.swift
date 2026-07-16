import Foundation

enum PortOSEndpointError: LocalizedError, Equatable {
    case empty
    case unsupportedScheme
    case missingHost
    case invalidPort
    case containsPath
    case malformed

    var errorDescription: String? {
        switch self {
        case .empty: "Enter a Tailscale host name or IP address."
        case .unsupportedScheme: "PortOS endpoints must use HTTP or HTTPS."
        case .missingHost: "The endpoint is missing a host name or IP address."
        case .invalidPort: "Use a port between 1 and 65535."
        case .containsPath: "Enter the server endpoint only, without an /api path."
        case .malformed: "That PortOS endpoint is not a valid URL."
        }
    }
}

enum PortOSEndpoint {
    static func make(scheme: String, host: String, port: Int = 5555) throws -> URL {
        guard (1...65_535).contains(port) else { throw PortOSEndpointError.invalidPort }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedHost = trimmedHost.contains(":") && !trimmedHost.hasPrefix("[")
            ? "[\(trimmedHost)]"
            : trimmedHost
        return try normalize("\(scheme)://\(formattedHost):\(port)")
    }

    static func normalize(_ rawValue: String, defaultScheme: String = "http", defaultPort: Int = 5555) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PortOSEndpointError.empty }
        guard (1...65_535).contains(defaultPort) else { throw PortOSEndpointError.invalidPort }

        let candidate = value.contains("://") ? value : "\(defaultScheme)://\(value)"
        guard var components = URLComponents(string: candidate) else { throw PortOSEndpointError.malformed }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw PortOSEndpointError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else { throw PortOSEndpointError.missingHost }
        guard components.path.isEmpty || components.path == "/" else { throw PortOSEndpointError.containsPath }
        if let port = components.port, !(1...65_535).contains(port) { throw PortOSEndpointError.invalidPort }

        components.scheme = scheme
        components.host = host.lowercased()
        components.port = components.port ?? defaultPort
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let url = components.url else { throw PortOSEndpointError.malformed }
        return url
    }
}
