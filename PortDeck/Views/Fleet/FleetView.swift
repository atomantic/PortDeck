import SwiftData
import SwiftUI

struct FleetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PortOSInstance.addedAt) private var instances: [PortOSInstance]

    @State private var showingAddInstance = false
    @State private var isRefreshing = false
    @State private var refreshError: String?

    private var orderedInstances: [PortOSInstance] {
        instances.sorted {
            if $0.localID == appState.selectedInstanceID { return true }
            if $1.localID == appState.selectedInstanceID { return false }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var onlineCount: Int { instances.filter { $0.connectionState == .online }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    fleetHeader

                    if let refreshError {
                        InlineMessage(text: refreshError, kind: .error)
                    }

                    if instances.isEmpty {
                        emptyState
                    } else {
                        ForEach(orderedInstances) { instance in
                            HStack(spacing: 8) {
                                NavigationLink {
                                    InstanceDetailView(instance: instance)
                                } label: {
                                    InstanceCard(
                                        instance: instance,
                                        isActive: instance.localID == appState.selectedInstanceID
                                    )
                                }
                                .buttonStyle(.plain)

                                if instance.localID != appState.selectedInstanceID {
                                    Button {
                                        appState.select(instance)
                                    } label: {
                                        Image(systemName: "scope")
                                            .font(.headline)
                                            .frame(width: 42, height: 42)
                                            .background(Color.portPanel, in: Circle())
                                    }
                                    .accessibilityLabel("Use \(instance.displayName) for captures")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.portCanvas)
            .navigationTitle("PortOS Fleet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isRefreshing { ProgressView().controlSize(.small) }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !instances.isEmpty {
                        Button { Task { await refreshAll() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                        .accessibilityLabel("Refresh fleet")
                    }
                    Button { showingAddInstance = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add PortOS instance")
                }
            }
            .sheet(isPresented: $showingAddInstance) { AddInstanceView() }
            .refreshable { await refreshAll() }
            .task {
                if appState.iCloudSyncEnabled {
                    do { _ = try appState.synchronizeFleet(modelContext: modelContext) }
                    catch { refreshError = "iCloud fleet sync failed: \(error.localizedDescription)" }
                }
                if appState.selectedInstanceID == nil, let first = instances.first { appState.select(first) }
                if !instances.isEmpty { await refreshAll() }
            }
        }
    }

    private var fleetHeader: some View {
        PortPanel {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.portAccent, .portViolet], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Your tailnet, one deck")
                        .font(.headline)
                    Text(instances.isEmpty
                         ? "Connect your first PortOS host to begin."
                         : "\(onlineCount) of \(instances.count) instances online")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        PortPanel {
            VStack(spacing: 18) {
                Image(systemName: "server.rack")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.portAccent)
                VStack(spacing: 7) {
                    Text("Connect PortOS")
                        .font(.title3.weight(.bold))
                    Text("Use the MagicDNS name or Tailscale IP of a PortOS host. PortDeck discovers its identity before asking for credentials.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Add an instance") { showingAddInstance = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    @MainActor
    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        for instance in instances {
            guard let baseURL = instance.baseURL else { continue }
            instance.connectionState = .checking
            do {
                let health = try await appState.api.discover(baseURL: baseURL)
                instance.apply(health: health)
                let password = try appState.credentials.password(for: instance.localID)
                if health.authRequiredWasReported && health.authRequired && (password?.isEmpty ?? true) {
                    instance.connectionState = .needsPassword
                    continue
                }
                do {
                    _ = try await appState.api.topology(baseURL: baseURL, password: password)
                } catch PortOSAPIError.authenticationRequired {
                    instance.authRequired = true
                    if password?.isEmpty ?? true {
                        instance.connectionState = .needsPassword
                        continue
                    }
                    throw PortOSAPIError.authenticationRequired
                }
            } catch {
                instance.markFailure(error)
            }
        }
        do { try modelContext.save() }
        catch { refreshError = "Fleet status could not be saved: \(error.localizedDescription)" }
    }
}

private struct InstanceCard: View {
    let instance: PortOSInstance
    let isActive: Bool

    var body: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(instance.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if isActive {
                                Text("ACTIVE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.portAccent)
                            }
                        }
                        Text(instance.baseURL?.host ?? instance.baseURLString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                HStack {
                    InstanceStatusBadge(state: instance.connectionState)
                    Spacer()
                    if let version = instance.version {
                        Text("v\(version)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: instance.authRequired ? "lock.fill" : "lock.open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
