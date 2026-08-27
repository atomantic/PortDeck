import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var syncFailed = false
    @State private var showingOfflineDemo = false
    @State private var reminderMessage: String?
    @State private var reminderFailed = false
    @State private var isUpdatingReminder = false
    @State private var reminderRescheduleTask: Task<Void, Never>?

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

                if !appState.isOfflineDemo {
                    Section {
                        Toggle("Daily Log reminder", isOn: Binding(
                            get: { appState.dailyLogReminderEnabled },
                            set: { updateDailyLogReminderEnabled($0) }
                        ))
                        .disabled(isUpdatingReminder)

                        if appState.dailyLogReminderEnabled {
                            DatePicker(
                                "Reminder time",
                                selection: Binding(
                                    get: { appState.dailyLogReminderTime },
                                    set: { updateDailyLogReminderTime($0) }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                        }

                        if let reminderMessage {
                            InlineMessage(text: reminderMessage, kind: reminderFailed ? .error : .success)
                        }

                        if appState.dailyLogReminderAuthorization == .denied {
                            Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                                Label("Open notification settings", systemImage: "gear")
                            }
                        }
                    } header: {
                        Text("Daily Log")
                    } footer: {
                        Text("PortOS can remind you at the same time every day. Tapping the alert opens Capture with Daily Log selected.")
                    }
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

                if appState.isOfflineDemo {
                    Section("iCloud") {
                        Label("Unavailable in offline demo", systemImage: "icloud.slash")
                            .foregroundStyle(.secondary)
                    }
                } else {
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
                }

                Section("Privacy") {
                    Label("No PortDeck-operated servers", systemImage: "server.rack")
                    Label("Current dictation sends text only", systemImage: "text.bubble")
                    Label("Speech recognition runs on device", systemImage: "waveform")
                    Label("Optional encrypted iCloud sync", systemImage: "icloud.and.arrow.up")
                }

                if !appState.isOfflineDemo {
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
            .task { await appState.refreshDailyLogReminderAuthorization() }
            .onDisappear { reminderRescheduleTask?.cancel() }
        }
    }

    private func updateDailyLogReminderEnabled(_ enabled: Bool) {
        isUpdatingReminder = true
        reminderMessage = nil
        Task {
            defer { isUpdatingReminder = false }
            do {
                try await appState.setDailyLogReminderEnabled(enabled)
                reminderFailed = false
                reminderMessage = enabled
                    ? "Daily reminder set for \(appState.dailyLogReminderTime.formatted(date: .omitted, time: .shortened))."
                    : "Daily reminder turned off."
            } catch {
                reminderFailed = true
                reminderMessage = error.localizedDescription
            }
        }
    }

    private func updateDailyLogReminderTime(_ time: Date) {
        appState.setDailyLogReminderTime(time)
        reminderMessage = nil
        reminderRescheduleTask?.cancel()
        reminderRescheduleTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                try await appState.rescheduleDailyLogReminder()
                reminderFailed = false
                reminderMessage = "Daily reminder moved to \(appState.dailyLogReminderTime.formatted(date: .omitted, time: .shortened))."
            } catch is CancellationError {
                return
            } catch {
                reminderFailed = true
                reminderMessage = error.localizedDescription
                await appState.refreshDailyLogReminderAuthorization()
            }
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
