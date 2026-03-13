import SwiftUI
import SwiftData

@main
struct PortOS_RecallApp: App {
    @State private var router = Router()

    private var modelContainer: ModelContainer = {
        let isSeedMode = ProcessInfo.processInfo.arguments.contains("-SeedSampleData")
        let config = isSeedMode
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration()
        let container = try! ModelContainer(
            for: Session.self, Memory.self, Participant.self,
            configurations: config
        )
        if isSeedMode {
            PreviewSampleData.populate(container: container)
        }
        return container
    }()

    init() {
        BackgroundTaskManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .onOpenURL { url in
                    DeepLinkHandler.handle(url: url, router: router)
                }
        }
        .modelContainer(modelContainer)
    }
}

struct ContentView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.sessionsPath) {
                SessionListView()
                    .withRouteDestinations()
            }
            .tabItem { Label("Sessions", systemImage: "waveform") }
            .tag(Router.AppTab.sessions)

            NavigationStack(path: $router.memoriesPath) {
                MemoryListView()
                    .withRouteDestinations()
            }
            .tabItem { Label("Memories", systemImage: "brain.head.profile") }
            .tag(Router.AppTab.memories)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(Router.AppTab.settings)
        }
        .tint(.recallPrimary)
    }
}

private extension View {
    func withRouteDestinations() -> some View {
        self
            .navigationDestination(for: SessionRoute.self) { route in
                switch route {
                case .list: SessionListView()
                case .detail(let id): SessionDetailView(sessionID: id)
                case .recording: RecordingView()
                }
            }
            .navigationDestination(for: MemoryRoute.self) { route in
                switch route {
                case .list: MemoryListView()
                case .detail(let id): Text("Memory Detail: \(id.hashValue)")
                }
            }
    }
}
