import SwiftData
import SwiftUI

struct ActionsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \PortOSInstance.addedAt) private var instances: [PortOSInstance]

    @State private var manifest: PaletteManifest?
    @State private var manifestInstanceID: UUID?
    @State private var currentLoadID: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var selectedInstance: PortOSInstance? {
        instances.first { $0.localID == appState.selectedInstanceID } ?? instances.first
    }

    private var visibleActions: [PaletteAction] {
        guard let actions = manifest?.actions else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return actions }
        return actions.filter {
            $0.label.localizedCaseInsensitiveContains(query) ||
            $0.section.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private var sections: [(String, [PaletteAction])] {
        Dictionary(grouping: visibleActions, by: \.section)
            .map { ($0.key, $0.value.sorted { $0.label < $1.label }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if instances.isEmpty {
                        noInstanceState
                    } else {
                        ActiveInstancePicker(instances: instances)
                        if let errorMessage { InlineMessage(text: errorMessage, kind: .error) }
                        if isLoading {
                            ProgressView("Loading live actions…").padding(.top, 60)
                        } else if manifest != nil,
                                  manifestInstanceID == selectedInstance?.localID {
                            ForEach(sections, id: \.0) { section, actions in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.uppercased())
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                    ForEach(actions) { action in
                                        NavigationLink {
                                            ActionDetailView(action: action, instance: selectedInstance!)
                                        } label: {
                                            ActionRow(action: action)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.portCanvas)
            .navigationTitle("Quick Actions")
            .searchable(text: $searchText, prompt: "Search actions")
            .toolbar {
                if !instances.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await loadManifest() } } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(isLoading)
                            .accessibilityLabel("Reload quick actions")
                    }
                }
            }
            .task(id: selectedInstance?.localID) {
                if appState.selectedInstanceID == nil, let first = instances.first { appState.select(first) }
                await loadManifest()
            }
        }
    }

    private var noInstanceState: some View {
        PortPanel {
            VStack(spacing: 14) {
                Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(Color.portViolet)
                Text("Actions follow your server").font(.headline)
                Text("Add a PortOS instance, then PortDeck will build this screen from its live palette manifest.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Fleet") { appState.selectedTab = .fleet }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @MainActor
    private func loadManifest() async {
        guard let instance = selectedInstance, let baseURL = instance.baseURL else {
            manifest = nil
            manifestInstanceID = nil
            return
        }
        let instanceID = instance.localID
        let loadID = UUID()
        currentLoadID = loadID
        manifest = nil
        manifestInstanceID = nil
        isLoading = true
        errorMessage = nil
        defer {
            if currentLoadID == loadID {
                isLoading = false
            }
        }
        do {
            let password = try appState.credentials.password(for: instanceID)
            let loadedManifest = try await appState.api.paletteManifest(baseURL: baseURL, password: password)
            try Task.checkCancellation()
            guard currentLoadID == loadID,
                  selectedInstance?.localID == instanceID else { return }
            manifest = loadedManifest
            manifestInstanceID = instanceID
        } catch is CancellationError {
            return
        } catch {
            guard currentLoadID == loadID,
                  selectedInstance?.localID == instanceID else { return }
            manifest = nil
            manifestInstanceID = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActionRow: View {
    let action: PaletteAction

    var body: some View {
        let presentation = action.presentation
        PortPanel {
            HStack(spacing: 12) {
                Image(systemName: presentation.icon)
                    .foregroundStyle(presentation.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(action.label).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if action.isReader {
                            Text("LIVE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.portAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.portAccent.opacity(0.12), in: Capsule())
                        }
                    }
                    if !action.description.isEmpty {
                        Text(action.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
    }
}
