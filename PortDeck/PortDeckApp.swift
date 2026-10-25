import SwiftData
import SwiftUI

@main
struct PortDeckApp: App {
    @UIApplicationDelegateAdaptor(PortDeckAppDelegate.self) private var appDelegate
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    @MainActor
    init() {
        #if DEBUG
        let isRemovalTest = FleetRemovalFixture.isEnabled
        #else
        let isRemovalTest = false
        #endif
        let isDemoMode = DemoMode.isEnabled || isRemovalTest
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: isDemoMode || ProcessInfo.processInfo.arguments.contains("-UseInMemoryStore")
        )
        do {
            let container = try ModelContainer(for: PortOSInstance.self, configurations: configuration)
            if isDemoMode { try DemoData.seed(modelContext: container.mainContext) }
            modelContainer = container

            #if DEBUG
            if isRemovalTest {
                _appState = State(initialValue: FleetRemovalFixture.makeState())
                return
            }
            #endif
            if isDemoMode {
                let suiteName = "net.shadowpuppet.PortDeck.demo"
                let defaults = UserDefaults(suiteName: suiteName) ?? .standard
                defaults.removePersistentDomain(forName: suiteName)
                let state = AppState(
                    api: PortOSAPIClient(transport: DemoHTTPTransport()),
                    credentials: DemoCredentialStore(),
                    fleetSyncStore: DemoFleetSyncStore(),
                    defaults: defaults,
                    isOfflineDemo: true
                )
                state.selectedInstanceID = DemoData.primaryInstanceID
                _appState = State(initialValue: state)
            } else {
                _appState = State(initialValue: AppState())
            }
        } catch {
            fatalError("Unable to create PortDeck data store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(appState)
                .onOpenURL { appState.handle(url: $0) }
                .onAppear { appDelegate.connect(to: appState) }
                .onChange(of: scenePhase) {
                    if scenePhase == .background && !appState.isOfflineDemo {
                        Task { await appState.tailcat.disconnectAll() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
