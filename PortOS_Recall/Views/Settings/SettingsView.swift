import SwiftUI

struct SettingsView: View {
    @State private var audioRetention: AudioRetention = AppSettings.audioRetention

    var body: some View {
        List {
            Section {
                Picker("Audio Retention", selection: $audioRetention) {
                    ForEach(AudioRetention.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .onChange(of: audioRetention) { _, newValue in
                    AppSettings.audioRetention = newValue
                }

                Text(audioRetention.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Audio Storage")
            } footer: {
                Text("Audio recordings are encrypted on-device with AES-256 and never leave your device.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }

            Section {
                Text("All data is processed on-device. No audio, transcripts, or memories are sent to external servers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Settings")
    }
}
