import SwiftData
import SwiftUI

struct AddInstanceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var instances: [PortOSInstance]

    @State private var scheme = "http"
    @State private var host = ""
    @State private var port = "5555"
    @State private var localLabel = ""
    @State private var password = ""
    @State private var requiresPassword = false
    @State private var health: PortOSHealth?
    @State private var discoveredURL: URL?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case host, label, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PortPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Tailnet endpoint", systemImage: "network")
                                .font(.headline)
                            Picker("Scheme", selection: $scheme) {
                                Text("HTTP").tag("http")
                                Text("HTTPS").tag("https")
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                TextField("portos-host.tailnet.ts.net", text: $host)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .focused($focusedField, equals: .host)
                                Divider()
                                TextField("5555", text: $port)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 64)
                            }
                            .padding(12)
                            .background(Color.portCanvas, in: RoundedRectangle(cornerRadius: 12))

                            Text("PortOS traffic goes directly to this host over Tailscale. Optional iCloud sync covers only fleet profiles and passwords.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PortPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Label", systemImage: "tag")
                                .font(.headline)
                            TextField("Optional local label", text: $localLabel)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .label)
                            Text("Leave blank to use the name reported by PortOS.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let health {
                        PortPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(health.name, systemImage: "checkmark.circle.fill")
                                        .font(.headline)
                                        .foregroundStyle(Color.portOnline)
                                    Spacer()
                                    if let version = health.version { Text("v\(version)").font(.caption.monospaced()) }
                                }
                                LabeledContent("Host", value: health.hostname)
                                LabeledContent("Authentication", value: requiresPassword ? "Password required" : "Tailnet trust")
                                if requiresPassword {
                                    SecureField("PortOS password", text: $password)
                                        .textContentType(.password)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedField, equals: .password)
                                }
                            }
                        }
                    }

                    if let errorMessage { InlineMessage(text: errorMessage, kind: .error) }

                    Button {
                        Task { health == nil ? await discover() : await addInstance() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView().tint(.white) }
                            Text(health == nil ? "Discover PortOS" : "Add to fleet")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isWorking || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .background(Color.portCanvas)
            .navigationTitle("Add Instance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .interactiveDismissDisabled(isWorking)
            .onAppear { focusedField = .host }
            .onChange(of: scheme) { health = nil; discoveredURL = nil }
            .onChange(of: host) { health = nil; discoveredURL = nil }
            .onChange(of: port) { health = nil; discoveredURL = nil }
        }
    }

    @MainActor
    private func discover() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            guard let portNumber = Int(port) else { throw PortOSEndpointError.invalidPort }
            let url = try PortOSEndpoint.make(scheme: scheme, host: host, port: portNumber)
            let health = try await appState.api.discover(baseURL: url)
            guard health.status == "ok" else {
                throw PortOSAPIError.server(status: 200, message: "The health response was not healthy.")
            }
            self.health = health
            requiresPassword = health.authRequired
            discoveredURL = url
            if requiresPassword { focusedField = .password }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addInstance() async {
        guard let health, let discoveredURL else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if requiresPassword && password.isEmpty { throw PortOSAPIError.authenticationRequired }
            do {
                _ = try await appState.api.topology(
                    baseURL: discoveredURL,
                    password: requiresPassword ? password : nil
                )
            } catch PortOSAPIError.authenticationRequired {
                requiresPassword = true
                focusedField = .password
                throw PortOSAPIError.authenticationRequired
            }
            let duplicate = instances.contains {
                $0.baseURLString == discoveredURL.absoluteString ||
                (health.instanceID != nil && $0.instanceID == health.instanceID)
            }
            guard !duplicate else {
                throw PortOSAPIError.server(status: 409, message: "This PortOS instance is already in your fleet.")
            }

            let instance = PortOSInstance(baseURL: discoveredURL, localLabel: localLabel, health: health)
            instance.authRequired = requiresPassword
            if requiresPassword { try appState.credentials.setPassword(password, for: instance.localID) }
            modelContext.insert(instance)
            try modelContext.save()
            _ = try? appState.synchronizeFleet(modelContext: modelContext)
            appState.select(instance)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
