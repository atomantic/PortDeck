import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            Color.portCanvas.ignoresSafeArea()
            TabView(selection: $appState.selectedTab) {
                FleetView()
                    .tabItem { Label("Fleet", systemImage: "point.3.connected.trianglepath.dotted") }
                    .tag(AppTab.fleet)

                CaptureView()
                    .tabItem { Label("Capture", systemImage: "waveform.and.mic") }
                    .tag(AppTab.capture)

                ActionsView()
                    .tabItem { Label("Actions", systemImage: "square.grid.2x2") }
                    .tag(AppTab.actions)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .tint(.portAccent)
            .background(Color.portCanvas.ignoresSafeArea())
            .toolbarBackground(Color.portCanvas, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }
}
