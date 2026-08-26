import Foundation

struct RemoteDesktopStatus: Decodable, Equatable, Sendable {
    let supported: Bool
    let configured: Bool
    let available: Bool
    let requiresPortOSAuth: Bool
    let platform: String
    let port: Int
    let setupCommand: String
}
struct RemoteDesktopSession: Decodable, Equatable, Sendable {
    let viewerPath: String
    let expiresAt: String

    func viewerURL(relativeTo baseURL: URL) throws -> URL {
        guard
            viewerPath.hasPrefix("/"),
            let viewer = URLComponents(string: viewerPath),
            viewer.host == nil,
            viewer.user == nil,
            viewer.password == nil,
            viewer.path == "/remote-desktop",
            var destination = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else {
            throw PortOSAPIError.invalidResponse
        }
        destination.path = viewer.path
        destination.queryItems = viewer.queryItems
        destination.fragment = nil
        guard let url = destination.url else { throw PortOSAPIError.invalidResponse }
        return url
    }
}
