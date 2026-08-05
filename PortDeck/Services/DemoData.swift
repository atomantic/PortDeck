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

/// Invented records for the offline demo. Never sourced from a live PortOS instance.
enum DemoFixtures {
    struct BrainEntry: Sendable {
        let date: String
        let text: String
    }

    struct Goal: Sendable {
        let title: String
        let horizon: String
        let category: String
        let progress: Int
    }

    /// PortOS list tools return five entries when the caller does not pass a limit.
    static let defaultLimit = 5

    /// Values the demo pre-fills so App Store screenshots show a filled-in run form.
    static let parameterPrefills = ["minutes": "50"]

    /// Schema defaults plus the demo's own prefills, for the offline presentation build only.
    static func prefilledArguments(for action: PaletteAction) -> ActionArgumentState {
        var state = ActionArgumentState(defaultsFor: action)
        for (name, value) in parameterPrefills where action.parameters.properties[name] != nil {
            state.setValue(value, for: name)
        }
        return state
    }

    static let brainEntries: [BrainEntry] = [
        BrainEntry(date: "2026-07-16", text: "Federation rollout: mirror the field kit before the demo, not after."),
        BrainEntry(date: "2026-07-16", text: "Idea — surface peer drift as a single badge instead of three counters."),
        BrainEntry(date: "2026-07-15", text: "Ask the studio team whether the nightly backup window still fits."),
        BrainEntry(date: "2026-07-15", text: "Reading list: the essay on durable local-first sync worth revisiting."),
        BrainEntry(date: "2026-07-14", text: "Voice capture on the phone beats typing for anything under a sentence."),
        BrainEntry(date: "2026-07-14", text: "Draft a one-page brief on what the companion should never do offline."),
        BrainEntry(date: "2026-07-13", text: "Home lab fan noise correlates with the media transcode queue."),
        BrainEntry(date: "2026-07-13", text: "Rename the staging universe before anyone builds on top of it."),
        BrainEntry(date: "2026-07-12", text: "Weekly review works better on Friday afternoon than Monday morning."),
        BrainEntry(date: "2026-07-12", text: "Pack the field kit charger — third trip in a row it stayed home."),
        BrainEntry(date: "2026-07-11", text: "Sketch the dashboard widget that shows fleet health as one line."),
        BrainEntry(date: "2026-07-11", text: "Try a shorter daily log format: three bullets, no prose.")
    ]

    static let goals: [Goal] = [
        Goal(title: "Ship the companion app", horizon: "quarter", category: "Build", progress: 72),
        Goal(title: "Automate the nightly backup verification", horizon: "month", category: "Ops", progress: 40),
        Goal(title: "Write one essay a week", horizon: "year", category: "Craft", progress: 55),
        Goal(title: "Federate the field kit", horizon: "month", category: "Fleet", progress: 88),
        Goal(title: "Cut the studio power draw", horizon: "quarter", category: "Home", progress: 15),
        Goal(title: "Read twelve books", horizon: "year", category: "Craft", progress: 33)
    ]
}

struct DemoHTTPTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(for: .milliseconds(80))
        let (statusCode, body) = response(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }

    private func response(for request: URLRequest) -> (Int, String) {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        if method == "GET", path == "/api/system/health" { return (200, healthBody(for: request.url?.host)) }
        if method == "GET", path == "/api/instances" { return (200, topologyBody) }
        if method == "GET", path == "/api/palette/manifest" { return (200, Self.manifestBody) }
        if method == "PUT", path == "/api/instances/self" {
            return (200, #"{"instanceId":"portos-atlas","name":"Atlas Studio","defaultPeerFullSync":false}"#)
        }
        if method == "POST", path.hasPrefix("/api/palette/action/") {
            let id = String(path.dropFirst("/api/palette/action/".count))
            return (200, actionBody(id: id, limit: requestedLimit(from: request.httpBody)))
        }
        if method == "POST", path.hasPrefix("/api/brain/daily-log/"), path.hasSuffix("/append") {
            return (200, #"{"date":"2026-07-16","entry":{"ok":true,"summary":"Added to the daily log."}}"#)
        }
        if method == "DELETE", path.hasPrefix("/api/instances/peers/") {
            return (200, #"{"ok":true}"#)
        }
        if method == "POST", path.hasPrefix("/api/instances/peers/"), path.hasSuffix("/sync") {
            return (200, #"{"ok":true}"#)
        }
        if path == "/api/instances/peers", method == "POST" {
            return (200, peerBody)
        }
        if path.hasPrefix("/api/instances/peers/"), ["POST", "PUT"].contains(method) {
            return (200, peerBody)
        }
        return (404, #"{"error":"Unknown offline demo route"}"#)
    }

    /// Mirrors the PortOS list tools: default window of 5, widened by the `limit` argument.
    private func requestedLimit(from body: Data?) -> Int {
        guard let body,
              let payload = try? JSONDecoder().decode(JSONValue.self, from: body),
              let limit = payload.objectValue?["args"]?.objectValue?["limit"]?.numberValue else {
            return DemoFixtures.defaultLimit
        }
        return max(1, Int(limit))
    }

    private func actionBody(id: String, limit: Int) -> String {
        switch id {
        case "brain_list_recent":
            return listEnvelope(
                key: "items",
                rows: DemoFixtures.brainEntries.prefix(limit).map {
                    ["date": .string($0.date), "text": .string($0.text)]
                },
                summary: { "Last \($0) capture\($0 == 1 ? "" : "s")." }
            )
        case "goal_list":
            return listEnvelope(
                key: "goals",
                rows: DemoFixtures.goals.prefix(limit).map {
                    [
                        "title": .string($0.title),
                        "horizon": .string($0.horizon),
                        "category": .string($0.category),
                        "progress": .number(Double($0.progress))
                    ]
                },
                summary: { "\($0) active goal\($0 == 1 ? "" : "s")." }
            )
        default:
            return envelope(["summary": .string("Action completed on Atlas Studio.")])
        }
    }

    private func listEnvelope(key: String, rows: [[String: JSONValue]], summary: (Int) -> String) -> String {
        envelope([
            "count": .number(Double(rows.count)),
            key: .array(rows.map { .object($0) }),
            "summary": .string(summary(rows.count))
        ])
    }

    private func envelope(_ result: [String: JSONValue]) -> String {
        var payload = result
        payload["ok"] = .bool(true)
        return JSONValue.object(["ok": .bool(true), "result": .object(payload)]).compactJSON
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

    /// Encoded once — the shape is the same `PaletteManifest` the app decodes, so a rename in
    /// the wire models breaks the build instead of silently missing this fixture.
    private static let manifestBody: String = {
        let manifest = PaletteManifest(actions: [
            PaletteAction(
                id: "brain_list_recent",
                label: "Recent Brain entries",
                section: "Brain",
                description: "Read back the most recently captured Brain inbox entries.",
                destructive: false,
                parameters: ActionParameters(
                    type: "object",
                    properties: ["limit": ActionParameter(
                        type: "integer",
                        description: "How many entries to return (default 5).",
                        allowedValues: nil
                    )],
                    required: []
                )
            ),
            PaletteAction(
                id: "goal_list",
                label: "List goals",
                section: "Goals",
                description: "List active goals with their current progress.",
                destructive: false,
                parameters: ActionParameters(
                    type: "object",
                    properties: ["limit": ActionParameter(
                        type: "integer",
                        description: "How many goals to return (default 5).",
                        allowedValues: nil
                    )],
                    required: []
                )
            ),
            PaletteAction(
                id: "brain_capture",
                label: "Capture to Brain",
                section: "Capture",
                description: "Save a thought or note to the selected PortOS Brain.",
                destructive: false,
                parameters: ActionParameters(
                    type: "object",
                    properties: ["text": ActionParameter(
                        type: "string",
                        description: "The thought to remember.",
                        allowedValues: nil
                    )],
                    required: ["text"]
                )
            ),
            PaletteAction(
                id: "daily_log_append",
                label: "Append Daily Log",
                section: "Capture",
                description: "Add an entry to today's Daily Log.",
                destructive: false,
                parameters: ActionParameters(
                    type: "object",
                    properties: ["text": ActionParameter(
                        type: "string",
                        description: "What happened today?",
                        allowedValues: nil
                    )],
                    required: ["text"]
                )
            ),
            PaletteAction(
                id: "focus_start",
                label: "Start Focus Session",
                section: "Productivity",
                description: "Begin a timed focus session on the active PortOS instance.",
                destructive: false,
                parameters: ActionParameters(
                    type: "object",
                    properties: [
                        "minutes": ActionParameter(
                            type: "integer",
                            description: "Session length in minutes.",
                            allowedValues: nil
                        ),
                        "mode": ActionParameter(
                            type: "string",
                            description: "Choose the focus profile.",
                            allowedValues: ["Deep work", "Planning", "Review"]
                        )
                    ],
                    required: ["minutes", "mode"]
                )
            ),
            PaletteAction(
                id: "fleet_sync",
                label: "Sync Federation Now",
                section: "Fleet",
                description: "Ask this instance to synchronize enabled peers.",
                destructive: false,
                parameters: ActionParameters(type: "object", properties: [:], required: [])
            ),
            PaletteAction(
                id: "service_restart",
                label: "Restart PortOS",
                section: "System",
                description: "Restart services on the selected instance.",
                destructive: true,
                parameters: ActionParameters(type: "object", properties: [:], required: [])
            )
        ])
        let encoded = try? JSONEncoder().encode(manifest)
        return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? #"{"actions":[]}"#
    }()
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
