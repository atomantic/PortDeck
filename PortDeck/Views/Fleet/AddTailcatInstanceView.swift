import SwiftData
import SwiftUI

struct AddTailcatInstanceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var instances: [PortOSInstance]
    let onAdded: () -> Void

    @State private var profileID = UUID()
    @State private var address = ""
    @State private var password = ""
    @State private var localLabel = ""
    @State private var usesHTTPS = false
    @State private var certificateHost = ""
    @State private var summary: TailcatAddressSummary?
    @State private var verifiedHealth: PortOSHealth?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    private enum Field { case address, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Full Tailcat address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .accessibilityIdentifier("tailcat-address")
                        .focused($focusedField, equals: .address)
                        .submitLabel(.done)
                    SecureField("PortOS instance password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                    TextField("Optional local label", text: $localLabel)
                } header: {
                    Text("Private connection")
                } footer: {
                    Text("Copy the full address privately from PortOS → Instances → Tailcat serve. This prototype requires an instance password. The address, password, and device identity stay in this device's Keychain.")
                }

                Section {
                    Toggle("Remote PortOS uses HTTPS", isOn: $usesHTTPS)
                    if usesHTTPS {
                        TextField("Certificate host name", text: $certificateHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                } footer: {
                    Text(usesHTTPS
                         ? "Use the DNS name on the server's trusted certificate. HTTPS is verified inside the encrypted tunnel."
                         : "WireGuard encrypts the connection to the dedicated PortOS ingress on port 5565.")
                }

                if let summary {
                    Section("Server identity") {
                        Text(summary.publicKey).font(.caption.monospaced()).textSelection(.enabled)
                        ForEach(summary.relays, id: \.self) { relay in
                            LabeledContent("Relay", value: relay)
                        }
                    }
                }
                if let health = verifiedHealth {
                    Section {
                        Label(health.name, systemImage: "checkmark.shield.fill")
                            .foregroundStyle(Color.portOnline)
                        Text("This address pins the server's WireGuard identity. Add it only if it came from an instance you trust.")
                            .font(.caption)
                    }
                }
                if let errorMessage {
                    Section { InlineMessage(text: errorMessage, kind: .error) }
                }
                Section {
                    Button {
                        Task { verifiedHealth == nil ? await verify() : await save() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text(verifiedHealth == nil ? "Verify private connection" : "Add to fleet")
                        }
                    }
                    .disabled(address.isEmpty || password.isEmpty || (usesHTTPS && certificateHost.isEmpty))
                } footer: {
                    Text("Experimental. This prototype relies on the secret address and your PortOS password. Removing this profile does not revoke access on the server. Tailscale remains available for other profiles.")
                }
            }
            .disabled(isWorking)
            .onSubmit { focusedField = nil }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tailcat Instance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
            .onChange(of: address) { invalidateVerification() }
            .onChange(of: password) { invalidateVerification() }
            .onChange(of: usesHTTPS) { invalidateVerification() }
            .onChange(of: certificateHost) { invalidateVerification() }
            .onDisappear {
                let pool = appState.tailcat
                let id = profileID
                Task { await pool.discardDraft(for: id) }
            }
        }
    }

    private func invalidateVerification() {
        verifiedHealth = nil
        summary = nil
        errorMessage = nil
    }

    @MainActor
    private func verify() async {
        isWorking = true
        verifiedHealth = nil
        errorMessage = nil
        defer { isWorking = false }
        do {
            let origin = try PortOSEndpoint.make(
                scheme: usesHTTPS ? "https" : "http",
                host: usesHTTPS ? certificateHost : "127.0.0.1",
                port: 5565
            )
            summary = try await appState.tailcat.stage(
                TailcatConnection(address: address.trimmingCharacters(in: .whitespacesAndNewlines), origin: origin.absoluteString, password: password),
                for: profileID
            )
            let baseURL = TailcatEndpoint.make(profileID: profileID)
            let health = try await appState.api.discover(baseURL: baseURL)
            guard health.status == "ok" else { throw PortOSAPIError.invalidResponse }
            guard health.authRequired else { throw TailcatError.passwordRequired }
            _ = try await appState.api.topology(baseURL: baseURL, password: password)
            guard !instances.contains(where: { health.instanceID != nil && $0.instanceID == health.instanceID }) else {
                throw PortOSAPIError.server(status: 409, message: "This instance is already in your fleet. Remove its existing profile before pairing it through Tailcat.")
            }
            verifiedHealth = health
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard let health = verifiedHealth else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await appState.tailcat.persistDraft(for: profileID)
            let instance = PortOSInstance(localID: profileID, baseURL: TailcatEndpoint.make(profileID: profileID), localLabel: localLabel, health: health)
            // Isolate rollback to this insertion, preserving earlier pending edits.
            try modelContext.save()
            modelContext.insert(instance)
            do { try modelContext.save() }
            catch { modelContext.rollback(); throw error }
            appState.select(instance)
            dismiss()
            onAdded()
        } catch {
            let original = error.localizedDescription
            do { try await appState.tailcat.forget(profileID) }
            catch { errorMessage = "\(original) The saved private connection could not be removed: \(error.localizedDescription)"; return }
            verifiedHealth = nil
            errorMessage = original
        }
    }
}
