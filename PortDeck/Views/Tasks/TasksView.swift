import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \PortOSInstance.addedAt) private var instances: [PortOSInstance]
    @State private var composer = TaskComposerModel()

    private var selectedInstance: PortOSInstance? {
        instances.first { $0.localID == appState.selectedInstanceID } ?? instances.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if instances.isEmpty {
                        noInstanceState
                    } else {
                        ActiveInstancePicker(instances: instances)
                        composerPanel
                    }
                }
                .padding(16)
            }
            .background(Color.portCanvas)
            .navigationTitle("Tasks")
            .task(id: selectedInstance?.localID) {
                guard let selectedInstance else { return }
                if appState.selectedInstanceID == nil { appState.select(selectedInstance) }
                await composer.load(for: selectedInstance, api: appState.api, credentials: appState.credentials)
            }
        }
    }

    private var composerPanel: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Queue CoS work").font(.headline)
                    Text("Send one user task to this PortOS profile. PortOS queues it for an eligible agent.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $composer.description)
                        .accessibilityLabel("Task description")
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 180)
                        .background(Color.portCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if composer.description.isEmpty {
                        Text("Describe the task to queue…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }

                if composer.isLoading {
                    HStack { ProgressView(); Text("Loading available runners…") }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if composer.assignableInstances.count > 1 {
                    Picker("Run on", selection: $composer.selectedTargetID) {
                        Text("Any instance").tag(String?.none)
                        ForEach(composer.assignableInstances) { runner in
                            Text(runner.isSelf ? "\(runner.name) (this instance)" : runner.name)
                                .tag(Optional(runner.instanceID))
                        }
                    }
                    .pickerStyle(.menu)
                } else if let runner = composer.assignableInstances.first {
                    LabeledContent(
                        "Run on",
                        value: composer.selectedTargetID == nil
                            ? "Any instance"
                            : (runner.isSelf ? "\(runner.name) (this instance)" : runner.name)
                    )
                    Text("Only \(runner.name) is currently assignable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lookupError = composer.lookupError {
                    if let targetName = composer.selectedTargetName {
                        InlineMessage(
                            text: "Pinned runner \(targetName) could not be verified for this profile. The task will not be sent unpinned.",
                            kind: .info
                        )
                    }
                    InlineMessage(text: "Could not load runners: \(lookupError)", kind: .error)
                    Button("Retry runner lookup") {
                        guard let selectedInstance else { return }
                        Task { await composer.load(for: selectedInstance, api: appState.api, credentials: appState.credentials) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(composer.isSubmitting)
                }

                if let submissionError = composer.submissionError {
                    InlineMessage(text: submissionError, kind: .error)
                }
                if let task = composer.createdTask {
                    InlineMessage(text: "Queued task \(task.id) · \(task.status)", kind: .success)
                }

                Button {
                    guard let selectedInstance else { return }
                    Task { await composer.submit(to: selectedInstance, api: appState.api, credentials: appState.credentials) }
                } label: {
                    HStack {
                        if composer.isSubmitting { ProgressView().tint(.white) }
                        Label("Queue task", systemImage: "paperplane.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!composer.canSubmit)
            }
        }
    }

    private var noInstanceState: some View {
        PortPanel {
            VStack(spacing: 14) {
                Image(systemName: "server.rack").font(.largeTitle).foregroundStyle(Color.portAccent)
                Text("Add an instance first").font(.headline)
                Text("Tasks need one explicit PortOS destination on your tailnet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open Fleet") { appState.selectedTab = .fleet }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}
