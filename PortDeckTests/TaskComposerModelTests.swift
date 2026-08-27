import XCTest
@testable import PortDeck

@MainActor
final class TaskComposerModelTests: XCTestCase {
    func testProfileSwitchReloadsDistinctHostAndRetainsOnlyAdvertisedTarget() async throws {
        let transport = RoutingTaskTransport()
        let model = TaskComposerModel()
        let atlas = makeInstance(id: atlasID, host: "atlas.example", serverID: "atlas")
        let home = makeInstance(id: homeID, host: "home.example", serverID: "home")
        let field = makeInstance(id: fieldID, host: "field.example", serverID: "field")

        await model.load(for: atlas, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        model.selectedTargetID = "shared-runner"
        await model.load(for: home, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        XCTAssertEqual(model.selectedTargetID, "shared-runner")

        await model.load(for: field, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        XCTAssertNil(model.selectedTargetID)
        let hosts = await transport.hosts
        XCTAssertEqual(hosts, ["atlas.example", "home.example", "field.example"])
    }

    func testLookupFailureKeepsExplicitTargetAndBlocksUnpinnedFallback() async {
        let transport = RoutingTaskTransport(failingHost: "home.example")
        let model = TaskComposerModel()
        let atlas = makeInstance(id: atlasID, host: "atlas.example", serverID: "atlas")
        let home = makeInstance(id: homeID, host: "home.example", serverID: "home")

        await model.load(for: atlas, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        model.description = "Keep this form"
        model.selectedTargetID = "shared-runner"
        await model.load(for: home, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())

        XCTAssertEqual(model.description, "Keep this form")
        XCTAssertEqual(model.selectedTargetID, "shared-runner")
        XCTAssertEqual(model.selectedTargetName, "Shared")
        XCTAssertNotNil(model.lookupError)
        XCTAssertFalse(model.canSubmit)
    }

    func testLookupFailureStillAllowsAnUnpinnedTask() async {
        let transport = RoutingTaskTransport(failingHost: "home.example")
        let model = TaskComposerModel()
        let home = makeInstance(id: homeID, host: "home.example", serverID: "home")

        await model.load(for: home, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        model.description = "Queue without a runner pin"

        XCTAssertTrue(model.canSubmit)
        await model.submit(to: home, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())

        XCTAssertEqual(model.createdTask?.id, "created-1")
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 1)
        XCTAssertNil(posts.first?.target)
    }

    func testSubmitTrimsOncePostsToSelectedProfileAndClearsOnlyOnSuccess() async throws {
        let transport = RoutingTaskTransport()
        let model = TaskComposerModel()
        let atlas = makeInstance(id: atlasID, host: "atlas.example", serverID: "atlas")
        await model.load(for: atlas, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        model.description = "  Queue this work \n"
        model.selectedTargetID = "shared-runner"

        await model.submit(to: atlas, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())

        XCTAssertEqual(model.createdTask, CreatedTask(id: "created-1", status: "pending"))
        XCTAssertEqual(model.description, "")
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.host, "atlas.example")
        XCTAssertEqual(posts.first?.description, "Queue this work")
        XCTAssertEqual(posts.first?.target, "shared-runner")
    }

    func testSubmitErrorPreservesDescription() async {
        let transport = RoutingTaskTransport(failPosts: true)
        let model = TaskComposerModel()
        let atlas = makeInstance(id: atlasID, host: "atlas.example", serverID: "atlas")
        await model.load(for: atlas, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())
        model.description = "Do not lose me"

        await model.submit(to: atlas, api: PortOSAPIClient(transport: transport), credentials: TestCredentialStore())

        XCTAssertEqual(model.description, "Do not lose me")
        XCTAssertNotNil(model.submissionError)
        XCTAssertNil(model.createdTask)
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 1)
    }

    func testProfileSwitchDiscardsStaleSubmitResultWithoutClearingNewDraft() async throws {
        let transport = RoutingTaskTransport(postDelayNanoseconds: 100_000_000)
        let model = TaskComposerModel()
        let api = PortOSAPIClient(transport: transport)
        let atlas = makeInstance(id: atlasID, host: "atlas.example", serverID: "atlas")
        let home = makeInstance(id: homeID, host: "home.example", serverID: "home")
        await model.load(for: atlas, api: api, credentials: TestCredentialStore())
        model.description = "Old profile task"

        let submission = Task {
            await model.submit(to: atlas, api: api, credentials: TestCredentialStore())
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        model.description = "New profile draft"
        await model.load(for: home, api: api, credentials: TestCredentialStore())
        await submission.value

        XCTAssertEqual(model.description, "New profile draft")
        XCTAssertNil(model.createdTask)
        XCTAssertNil(model.submissionError)
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.host, "atlas.example")
    }

    func testTasksDeepLinkSelectsTasksTab() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let state = AppState(
            credentials: TestCredentialStore(),
            fleetSyncStore: DemoFleetSyncStore(),
            defaults: defaults
        )

        state.handle(url: URL(string: "portdeck://tasks")!)

        XCTAssertEqual(state.selectedTab, .tasks)
    }

    private let atlasID = UUID(uuidString: "A7100000-0000-4000-8000-000000000011")!
    private let homeID = UUID(uuidString: "A7100000-0000-4000-8000-000000000012")!
    private let fieldID = UUID(uuidString: "A7100000-0000-4000-8000-000000000013")!

    private func makeInstance(id: UUID, host: String, serverID: String) -> PortOSInstance {
        PortOSInstance(
            localID: id,
            baseURL: URL(string: "https://\(host):5555")!,
            health: PortOSHealth(
                status: "ok",
                hostname: host,
                instanceID: serverID,
                name: host,
                authRequired: true
            )
        )
    }
}

private final class TestCredentialStore: CredentialStore, @unchecked Sendable {
    func password(for instanceID: UUID) throws -> String? { "test-password" }
    func setPassword(_ password: String, for instanceID: UUID) throws {}
    func removePassword(for instanceID: UUID) throws {}
    func migratePasswords(for instanceIDs: [UUID], toICloud: Bool) throws {}
}

private actor RoutingTaskTransport: HTTPTransport {
    struct Post: Equatable {
        let host: String?
        let description: String?
        let target: String?
    }

    private(set) var hosts: [String] = []
    private(set) var posts: [Post] = []
    private let failingHost: String?
    private let failPosts: Bool
    private let postDelayNanoseconds: UInt64

    init(
        failingHost: String? = nil,
        failPosts: Bool = false,
        postDelayNanoseconds: UInt64 = 0
    ) {
        self.failingHost = failingHost
        self.failPosts = failPosts
        self.postDelayNanoseconds = postDelayNanoseconds
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let host = request.url?.host
        let path = request.url?.path
        var status = 200
        let body: String
        if path == "/api/instances/assignable" {
            hosts.append(host ?? "")
            if host == failingHost {
                status = 503
                body = #"{"message":"Runner registry unavailable"}"#
            } else if host == "field.example" {
                body = #"{"instances":[{"instanceId":"field","name":"Field","isSelf":true}]}"#
            } else {
                body = #"{"instances":[{"instanceId":"shared-runner","name":"Shared","isSelf":false},{"instanceId":"self","name":"Self","isSelf":true}]}"#
            }
        } else if path == "/api/cos/tasks" {
            if postDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: postDelayNanoseconds)
            }
            let json = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            posts.append(Post(
                host: host,
                description: json?["description"] as? String,
                target: json?["targetInstanceId"] as? String
            ))
            if failPosts {
                status = 409
                body = #"{"message":"Duplicate task"}"#
            } else {
                body = #"{"id":"created-1","status":"pending"}"#
            }
        } else {
            status = 404
            body = #"{"message":"Not found"}"#
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}
