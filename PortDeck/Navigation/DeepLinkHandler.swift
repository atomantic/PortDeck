import Foundation

struct DeepLinkHandler {
    static func handle(url: URL, router: Router) {
        guard url.scheme == "portdeck" else { return }

        switch url.host {
        case "sessions":
            router.switchTab(.sessions)
            if let id = url.pathComponents.dropFirst().first {
                RecallLogger.info("Deep link to session: \(id)")
            }
        case "memories":
            router.switchTab(.memories)
        case "record":
            router.switchTab(.sessions)
            router.navigate(to: SessionRoute.recording)
        case "settings":
            router.switchTab(.settings)
        default:
            RecallLogger.warning("Unknown deep link: \(url)")
        }
    }
}
