import Foundation
import SwiftData

enum DemoMode {
    static let launchArgument = "-demo-data"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
}

@MainActor
enum DemoData {
    static let primaryInstanceID = UUID(uuidString: "A7100000-0000-4000-8000-000000000001")!
    static let captureText = "Capture the federation rollout notes and turn them into tomorrow's priorities."

    static func seed(modelContext: ModelContext) throws {
        guard try modelContext.fetch(FetchDescriptor<PortOSInstance>()).isEmpty else { return }

        let definitions: [(UUID, String, String, String, String)] = [
            (primaryInstanceID, "Atlas Studio", "atlas-studio", "portos-atlas", "100.77.10.4"),
            (UUID(uuidString: "A7100000-0000-4000-8000-000000000002")!, "Home Lab", "home-lab", "portos-home", "100.81.22.9"),
            (UUID(uuidString: "A7100000-0000-4000-8000-000000000003")!, "Field Kit", "field-kit", "portos-field", "100.92.44.12")
        ]

        for (localID, label, hostname, instanceID, _) in definitions {
            let instance = PortOSInstance(
                localID: localID,
                baseURL: URL(string: "https://\(hostname).demo.ts.net:5555")!,
                localLabel: label,
                health: PortOSHealth(
                    status: "ok",
                    version: "1.8.0",
                    hostname: hostname,
                    instanceID: instanceID,
                    name: label,
                    authRequired: false,
                    scheme: "https"
                )
            )
            modelContext.insert(instance)
        }
        try modelContext.save()
    }
}

struct DemoHTTPTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(for: .milliseconds(80))
        let body = responseBody(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }

    private func responseBody(for request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        if path == "/api/system/health" { return healthBody(for: request.url?.host) }
        if path == "/api/instances" { return topologyBody }
        if path == "/api/palette/manifest" { return manifestBody }
        if path == "/api/instances/self" {
            return #"{"instanceId":"portos-atlas","name":"Atlas Studio","defaultPeerFullSync":false}"#
        }
        if path.hasPrefix("/api/palette/action/") {
            return #"{"ok":true,"result":{"ok":true,"summary":"Action completed on Atlas Studio."}}"#
        }
        if path.hasPrefix("/api/brain/daily-log/") {
            return #"{"date":"2026-07-16","entry":{"ok":true,"summary":"Added to the daily log."}}"#
        }
        if path.hasSuffix("/sync") || request.httpMethod == "DELETE" {
            return #"{"ok":true}"#
        }
        return peerBody
    }

    private func healthBody(for host: String?) -> String {
        switch host {
        case "home-lab.demo.ts.net":
            return #"{"status":"ok","version":"1.8.0","hostname":"home-lab","instanceId":"portos-home","name":"Home Lab","authRequired":false,"scheme":"https"}"#
        case "field-kit.demo.ts.net":
            return #"{"status":"ok","version":"1.8.0","hostname":"field-kit","instanceId":"portos-field","name":"Field Kit","authRequired":false,"scheme":"https"}"#
        default:
            return #"{"status":"ok","version":"1.8.0","hostname":"atlas-studio","instanceId":"portos-atlas","name":"Atlas Studio","authRequired":false,"scheme":"https"}"#
        }
    }

    private var topologyBody: String {
        #"{"self":{"instanceId":"portos-atlas","name":"Atlas Studio","defaultPeerFullSync":false},"peers":[{"id":"home-peer","instanceId":"portos-home","name":"Home Lab","address":"100.81.22.9","host":"home-lab.demo.ts.net","port":5555,"status":"online","enabled":true,"syncEnabled":true,"fullSync":true,"lastSeen":"2026-07-16T19:41:00Z","authRequired":false},{"id":"field-peer","instanceId":"portos-field","name":"Field Kit","address":"100.92.44.12","host":"field-kit.demo.ts.net","port":5555,"status":"online","enabled":true,"syncEnabled":true,"fullSync":false,"lastSeen":"2026-07-16T19:40:00Z","authRequired":false}]}"#
    }

    private var peerBody: String {
        #"{"id":"home-peer","instanceId":"portos-home","name":"Home Lab","address":"100.81.22.9","host":"home-lab.demo.ts.net","port":5555,"status":"online","enabled":true,"syncEnabled":true,"fullSync":true,"lastSeen":"2026-07-16T19:41:00Z","authRequired":false}"#
    }

    private var manifestBody: String {
        #"{"actions":[{"id":"brain_capture","label":"Capture to Brain","section":"Capture","description":"Save a thought or note to the selected PortOS Brain.","destructive":false,"parameters":{"type":"object","properties":{"text":{"type":"string","description":"The thought to remember."}},"required":["text"]}},{"id":"daily_log_append","label":"Append Daily Log","section":"Capture","description":"Add an entry to today's Daily Log.","destructive":false,"parameters":{"type":"object","properties":{"text":{"type":"string","description":"What happened today?"}},"required":["text"]}},{"id":"focus_start","label":"Start Focus Session","section":"Productivity","description":"Begin a timed focus session on the active PortOS instance.","destructive":false,"parameters":{"type":"object","properties":{"minutes":{"type":"integer","description":"Session length in minutes."},"mode":{"type":"string","description":"Choose the focus profile.","enum":["Deep work","Planning","Review"]}},"required":["minutes","mode"]}},{"id":"fleet_sync","label":"Sync Federation Now","section":"Fleet","description":"Ask this instance to synchronize enabled peers.","destructive":false,"parameters":{"type":"object","properties":{},"required":[]}},{"id":"service_restart","label":"Restart PortOS","section":"System","description":"Restart services on the selected instance.","destructive":true,"parameters":{"type":"object","properties":{},"required":[]}}]}"#
    }
}

final class DemoCredentialStore: CredentialStore, @unchecked Sendable {
    func password(for instanceID: UUID) throws -> String? { nil }
    func setPassword(_ password: String, for instanceID: UUID) throws {}
    func removePassword(for instanceID: UUID) throws {}
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {}
}

final class DemoFleetSyncStore: FleetSyncStore, @unchecked Sendable {
    func loadProfiles() throws -> [SyncedInstanceProfile] { [] }
    func saveProfiles(_ profiles: [SyncedInstanceProfile]) throws {}
}
