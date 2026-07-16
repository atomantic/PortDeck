import SwiftData
import SwiftUI

struct EditInstanceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var instance: PortOSInstance
    let onSaved: () -> Void

    @State private var localLabel: String
    @State private var remoteName: String
    @State private var endpoint: String
    @State private var password = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(instance: PortOSInstance, onSaved: @escaping () -> Void) {
        self.instance = instance
        self.onSaved = onSaved
        _localLabel = State(initialValue: instance.localLabel)
        _remoteName = State(initialValue: instance.remoteName)
        _endpoint = State(initialValue: instance.baseURLString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Local label", text: $localLabel)
                    TextField("Endpoint", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("PortDeck")
                } footer: {
                    Text("The local label only changes this phone. The endpoint must be a Tailscale-reachable HTTP or HTTPS URL.")
                }

                Section {
                    TextField("Server display name", text: $remoteName)
                    if instance.authRequired {
                        SecureField("PortOS password", text: $password)
                            .textContentType(.password)
                    }
                } header: {
                    Text("PortOS server")
                } footer: {
                    Text("Changing the server display name updates /api/instances/self. Passwords use the local Keychain unless optional iCloud sync is enabled.")
                }

                if let errorMessage {
                    Section { InlineMessage(text: errorMessage, kind: .error) }
                }
            }
            .navigationTitle("Edit Instance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || endpoint.isEmpty || remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                password = (try? appState.credentials.password(for: instance.localID)) ?? ""
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let baseURL = try PortOSEndpoint.normalize(endpoint)
            if instance.authRequired && password.isEmpty { throw PortOSAPIError.authenticationRequired }
            let trimmedRemoteName = remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedRemoteName != instance.remoteName {
                let identity = try await appState.api.renameSelf(
                    name: trimmedRemoteName,
                    baseURL: baseURL,
                    password: password.isEmpty ? nil : password
                )
                instance.remoteName = identity.name ?? trimmedRemoteName
            }
            let health = try await appState.api.discover(baseURL: baseURL)
            if health.authRequired {
                _ = try await appState.api.topology(baseURL: baseURL, password: password)
                try appState.credentials.setPassword(password, for: instance.localID)
            } else {
                try appState.credentials.removePassword(for: instance.localID)
            }
            instance.baseURLString = baseURL.absoluteString
            instance.localLabel = localLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            instance.apply(health: health)
            instance.markSyncMetadataChanged()
            try modelContext.save()
            _ = try? appState.synchronizeFleet(modelContext: modelContext)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
