import SwiftUI
import UIKit

struct TailcatSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var publicKey: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Section {
            Label("Optional private fleet connections", systemImage: "lock.shield")
            Button {
                isLoading = true
                Task {
                    defer { isLoading = false }
                    do { publicKey = try await appState.tailcat.publicKey(); errorMessage = nil }
                    catch { errorMessage = error.localizedDescription }
                }
            } label: {
                HStack {
                    Text("Show this device's public key")
                    Spacer()
                    if isLoading { ProgressView() }
                }
            }
            .disabled(isLoading)
            if let publicKey {
                Text(publicKey).font(.caption.monospaced()).textSelection(.enabled)
                Button("Copy public key") { UIPasteboard.general.string = publicKey }
            }
            if let errorMessage { InlineMessage(text: errorMessage, kind: .error) }
        } header: {
            Text("Tailcat prototype")
        } footer: {
            Text("Add a Tailcat connection from Fleet → Add instance. Its secrets and password stay on this device, even when fleet sync is enabled. A server can use this public key to approve the phone. The copied server address selects its relay; configure your own relay on PortOS for private relay hosting.")
        }
    }
}
