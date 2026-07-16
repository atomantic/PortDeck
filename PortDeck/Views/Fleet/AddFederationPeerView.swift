import SwiftUI

struct AddFederationPeerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let instance: PortOSInstance
    let onAdded: () -> Void

    @State private var name = ""
    @State private var address = ""
    @State private var host = ""
    @State private var port = "5555"
    @State private var peerPassword = ""
    @State private var makeMutual = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Tailscale IPv4 address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("MagicDNS host (optional)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Peer endpoint")
                } footer: {
                    Text("PortOS currently requires the peer's Tailscale IPv4 address. Add its MagicDNS host when available so HTTPS certificate routing works.")
                }

                Section {
                    SecureField("Peer PortOS password (optional)", text: $peerPassword)
                        .textContentType(.password)
                    Toggle("Make connection mutual", isOn: $makeMutual)
                } header: {
                    Text("Federation")
                } footer: {
                    Text("The peer password is sent to \(instance.displayName) for its existing server-side federation credential store. It is not saved in PortDeck.")
                }

                if let errorMessage {
                    Section { InlineMessage(text: errorMessage, kind: .error) }
                }
            }
            .navigationTitle("Add Peer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await addPeer() } }
                        .disabled(isSaving || address.isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func addPeer() async {
        guard let baseURL = instance.baseURL else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            guard let portNumber = Int(port), (1...65_535).contains(portNumber) else {
                throw PortOSEndpointError.invalidPort
            }
            let currentPassword = try appState.credentials.password(for: instance.localID)
            let peer = try await appState.api.addPeer(
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: portNumber,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                peerPassword: peerPassword,
                baseURL: baseURL,
                password: currentPassword
            )
            if makeMutual {
                _ = try? await appState.api.connect(peerID: peer.id, baseURL: baseURL, password: currentPassword)
            }
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
