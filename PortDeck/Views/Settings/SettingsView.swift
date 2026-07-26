import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var syncFailed = false
    @State private var showingOfflineDemo = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(LinearGradient(colors: [.portAccent, .portViolet], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PortOS").font(.title3.weight(.bold))
                            Text("PortDeck companion · \(version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Label("Direct over Tailscale", systemImage: "network.badge.shield.half.filled")
                    Label("Per-instance passwords in Keychain", systemImage: "key.fill")
                    Label("HTTP and HTTPS on port 5555", systemImage: "arrow.left.arrow.right")
                } header: {
                    Text("Connection model")
                } footer: {
                    Text("Passwordless PortOS installs use the tailnet trust boundary. Password-protected installs use HTTP Basic. Credentials stay in the local Keychain unless optional iCloud sync is enabled.")
                }

                Section {
                    Toggle("Sync fleet and passwords", isOn: Binding(
                        get: { appState.iCloudSyncEnabled },
                        set: { setICloudSyncEnabled($0) }
                    ))
                    .disabled(isSyncing)
                    if appState.iCloudSyncEnabled {
                        Button {
                            synchronizeNow()
                        } label: {
                            HStack {
                                Label("Sync now", systemImage: "arrow.triangle.2.circlepath.icloud")
                                Spacer()
                                if isSyncing { ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(isSyncing)
                    }
                    if let syncMessage {
                        InlineMessage(text: syncMessage, kind: syncFailed ? .error : .success)
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Optional. Fleet connection profiles and passwords use secure iCloud Keychain items for this app. SwiftData remains the local working copy. Turning sync off keeps device-only copies and leaves existing iCloud copies available to other opted-in devices.")
                }

                Section("Privacy") {
                    Label("No PortDeck-operated servers", systemImage: "server.rack")
                    Label("Current dictation sends text only", systemImage: "text.bubble")
                    Label("Optional audio may go directly to your PortOS", systemImage: "waveform.and.arrow.up")
                    Label("Optional encrypted iCloud sync", systemImage: "icloud.and.arrow.up")
                }

                Section {
                    Button {
                        showingOfflineDemo = true
                    } label: {
                        Label("Explore offline demo", systemImage: "sparkles")
                    }
                    .accessibilityHint("Opens a fully featured demo with no server, account, or password required")
                } header: {
                    Text("Try PortOS")
                } footer: {
                    Text("No PortOS server, account, or login is required. The demo has fictional fleet data and uses no network, Keychain, or iCloud access.")
                }

                Section("Project") {
                    Link(destination: URL(string: "https://github.com/atomantic/PortOS/issues/2678")!) {
                        Label("Companion API contract", systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "https://github.com/atomantic/PortDeck")!) {
                        Label("PortDeck on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .fullScreenCover(isPresented: $showingOfflineDemo) { OfflineDemoView() }
        }
    }

    private func setICloudSyncEnabled(_ enabled: Bool) {
        isSyncing = true
        syncMessage = nil
        defer { isSyncing = false }
        do {
            let result = try appState.setICloudSyncEnabled(enabled, modelContext: modelContext)
            syncFailed = false
            syncMessage = enabled
                ? "iCloud sync is on. \(result.description)"
                : "iCloud sync is off. Passwords remain in this device's Keychain."
        } catch {
            syncFailed = true
            syncMessage = error.localizedDescription
        }
    }

    private func synchronizeNow() {
        isSyncing = true
        syncMessage = nil
        defer { isSyncing = false }
        do {
            let result = try appState.synchronizeFleet(modelContext: modelContext)
            syncFailed = false
            syncMessage = result.description
        } catch {
            syncFailed = true
            syncMessage = error.localizedDescription
        }
    }
}
