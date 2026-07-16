import SwiftData
import SwiftUI

struct InstanceDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var instance: PortOSInstance

    @State private var topology: PortOSTopology?
    @State private var isRefreshing = false
    @State private var busyPeerID: String?
    @State private var message: String?
    @State private var showingEdit = false
    @State private var showingAddPeer = false
    @State private var showingDeleteConfirmation = false
    @State private var peerToRemove: FederationPeer?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                identityHeader
                if let message { InlineMessage(text: message, kind: .error) }
                connectionPanel
                federationPanel
                managementPanel
            }
            .padding(16)
        }
        .background(Color.portCanvas)
        .navigationTitle(instance.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    if isRefreshing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh instance")
                Button { showingEdit = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Edit instance")
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditInstanceView(instance: instance) { Task { await refresh() } }
        }
        .sheet(isPresented: $showingAddPeer) {
            AddFederationPeerView(instance: instance) { Task { await refresh() } }
        }
        .confirmationDialog(
            "Remove \(instance.displayName)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from PortDeck", role: .destructive) { removeInstance() }
        } message: {
            Text(appState.iCloudSyncEnabled
                ? "This removes the connection and password from your synced PortDeck fleet. It does not change the PortOS server."
                : "This removes the local connection and its Keychain password. It does not change the PortOS server.")
        }
        .confirmationDialog(
            "Remove federation peer?",
            isPresented: Binding(
                get: { peerToRemove != nil },
                set: { if !$0 { peerToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let peer = peerToRemove {
                Button("Remove \(peer.name)", role: .destructive) {
                    Task { await remove(peer: peer) }
                }
            }
        } message: {
            Text("This changes the peer configuration on \(instance.displayName). It does not remove the other server from PortDeck.")
        }
        .task { await refresh() }
    }

    private var identityHeader: some View {
        PortPanel {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [.portAccent, .portViolet], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(instance.remoteName.isEmpty ? instance.displayName : instance.remoteName)
                        .font(.title3.weight(.bold))
                    InstanceStatusBadge(state: instance.connectionState)
                }
                Spacer()
                if appState.selectedInstanceID == instance.localID {
                    Image(systemName: "scope")
                        .foregroundStyle(Color.portAccent)
                        .accessibilityLabel("Active target")
                }
            }
        }
    }

    private var connectionPanel: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Connection", systemImage: "network")
                    .font(.headline)
                detailRow("Endpoint", instance.baseURLString, monospaced: true)
                detailRow("Host", instance.hostname.isEmpty ? "Unknown" : instance.hostname)
                detailRow("Version", instance.version.map { "v\($0)" } ?? "Unknown")
                detailRow("Authentication", instance.authRequired ? "HTTP Basic · Keychain" : "Tailnet trust")
                if let id = instance.instanceID { detailRow("Instance ID", id, monospaced: true) }
                if let date = instance.lastReachableAt {
                    detailRow("Last reached", date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private var federationPanel: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Federation", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Spacer()
                    Text("\(topology?.peers.count ?? 0) peers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { showingAddPeer = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Add federation peer")
                }
                if isRefreshing && topology == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 18)
                } else if let peers = topology?.peers, !peers.isEmpty {
                    ForEach(peers) { peer in
                        Divider()
                        PeerRow(
                            peer: peer,
                            isBusy: busyPeerID == peer.id,
                            onProbe: { Task { await run(.probe, peer: peer) } },
                            onSync: { Task { await run(.sync, peer: peer) } },
                            onConnect: { Task { await run(.connect, peer: peer) } },
                            onToggleEnabled: { Task { await setPeer(peer, enabled: !peer.enabled) } },
                            onToggleFullSync: { Task { await setPeer(peer, fullSync: !(peer.fullSync ?? false)) } },
                            onRemove: { peerToRemove = peer }
                        )
                    }
                } else {
                    Text("No federation peers are configured on this PortOS instance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private var managementPanel: some View {
        PortPanel {
            VStack(spacing: 10) {
                if appState.selectedInstanceID != instance.localID {
                    Button { appState.select(instance) } label: {
                        Label("Use for captures and actions", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button { showingEdit = true } label: {
                    Label("Edit connection", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Remove instance", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private enum PeerOperation { case probe, sync, connect }

    @MainActor
    private func refresh() async {
        guard !isRefreshing, let baseURL = instance.baseURL else { return }
        isRefreshing = true
        message = nil
        instance.connectionState = .checking
        defer { isRefreshing = false }
        do {
            let health = try await appState.api.discover(baseURL: baseURL)
            instance.apply(health: health)
            let password = try appState.credentials.password(for: instance.localID)
            if health.authRequired && (password?.isEmpty ?? true) { throw PortOSAPIError.authenticationRequired }
            topology = try await appState.api.topology(baseURL: baseURL, password: password)
            try modelContext.save()
        } catch {
            instance.markFailure(error)
            message = error.localizedDescription
        }
    }

    @MainActor
    private func run(_ operation: PeerOperation, peer: FederationPeer) async {
        guard let baseURL = instance.baseURL else { return }
        busyPeerID = peer.id
        message = nil
        defer { busyPeerID = nil }
        do {
            let password = try appState.credentials.password(for: instance.localID)
            switch operation {
            case .probe: _ = try await appState.api.probe(peerID: peer.id, baseURL: baseURL, password: password)
            case .sync: _ = try await appState.api.sync(peerID: peer.id, baseURL: baseURL, password: password)
            case .connect: _ = try await appState.api.connect(peerID: peer.id, baseURL: baseURL, password: password)
            }
            topology = try await appState.api.topology(baseURL: baseURL, password: password)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func setPeer(_ peer: FederationPeer, enabled: Bool? = nil, fullSync: Bool? = nil) async {
        guard let baseURL = instance.baseURL else { return }
        busyPeerID = peer.id
        message = nil
        defer { busyPeerID = nil }
        do {
            let password = try appState.credentials.password(for: instance.localID)
            _ = try await appState.api.updatePeer(
                peerID: peer.id,
                enabled: enabled,
                fullSync: fullSync,
                baseURL: baseURL,
                password: password
            )
            topology = try await appState.api.topology(baseURL: baseURL, password: password)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func remove(peer: FederationPeer) async {
        peerToRemove = nil
        guard let baseURL = instance.baseURL else { return }
        busyPeerID = peer.id
        message = nil
        defer { busyPeerID = nil }
        do {
            let password = try appState.credentials.password(for: instance.localID)
            _ = try await appState.api.removePeer(peerID: peer.id, baseURL: baseURL, password: password)
            topology = try await appState.api.topology(baseURL: baseURL, password: password)
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeInstance() {
        try? appState.recordFleetDeletion(instance)
        try? appState.credentials.removePassword(for: instance.localID)
        if appState.selectedInstanceID == instance.localID { appState.selectedInstanceID = nil }
        modelContext.delete(instance)
        try? modelContext.save()
        dismiss()
    }
}

private struct PeerRow: View {
    let peer: FederationPeer
    let isBusy: Bool
    let onProbe: () -> Void
    let onSync: () -> Void
    let onConnect: () -> Void
    let onToggleEnabled: () -> Void
    let onToggleFullSync: () -> Void
    let onRemove: () -> Void

    private var isOnline: Bool { peer.status == "online" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(peer.name).font(.subheadline.weight(.semibold))
                    Text(peer.host ?? peer.address)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(peer.status.capitalized, systemImage: isOnline ? "circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOnline ? Color.portOnline : Color.portOffline)
            }
            HStack {
                if peer.fullSync == true {
                    Label("Full mirror", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if peer.syncEnabled == true {
                    Text("Selective sync").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Probe", action: onProbe)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Sync", action: onSync)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isOnline)
                Menu {
                    Button(action: onConnect) { Label("Make mutual", systemImage: "link") }
                    Button(action: onToggleFullSync) {
                        Label(peer.fullSync == true ? "Disable full mirror" : "Enable full mirror", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(action: onToggleEnabled) {
                        Label(peer.enabled ? "Disable peer" : "Enable peer", systemImage: peer.enabled ? "pause.circle" : "play.circle")
                    }
                    Divider()
                    Button(role: .destructive, action: onRemove) { Label("Remove peer", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Manage \(peer.name)")
            }
            .disabled(isBusy)
            if isBusy { ProgressView().controlSize(.small) }
        }
    }
}
