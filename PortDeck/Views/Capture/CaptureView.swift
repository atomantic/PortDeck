import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \PortOSInstance.addedAt) private var instances: [PortOSInstance]

    @State private var composer = CaptureComposerModel()
    @State private var dictation = DictationController()

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
                        captureComposer
                        if let error = dictation.errorMessage { InlineMessage(text: error, kind: .error) }
                        if let receipt = composer.acceptedCapture {
                            Text("Accepted by \(receipt.attribution)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let message = composer.message { InlineMessage(text: message.0, kind: message.1) }
                    }
                }
                .padding(16)
            }
            .background(Color.portCanvas)
            .navigationTitle("Capture")
            .onChange(of: dictation.transcript) {
                composer.receiveTranscript(dictation.transcript)
            }
            .onChange(of: captureSelection, initial: true) { _, selection in
                composer.selection = selection
            }
            .onDisappear { dictation.stop() }
            .task {
                if appState.selectedInstanceID == nil, let first = instances.first { appState.select(first) }
            }
        }
    }

    private var captureSelection: CaptureComposerModel.Selection {
        .init(profileID: selectedInstance?.localID,
              destination: appState.captureDestination,
              date: appState.dailyLogCaptureDate)
    }

    private var captureComposer: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Destination", selection: Binding(
                    get: { appState.captureDestination },
                    set: { appState.captureDestination = $0 }
                )) {
                    ForEach(CaptureDestination.allCases) { destination in
                        Label(destination.rawValue, systemImage: destination.icon).tag(destination)
                    }
                }
                .pickerStyle(.segmented)

                if appState.captureDestination == .dailyLog {
                    DatePicker("Log date", selection: Binding(
                        get: { appState.dailyLogCaptureDate },
                        set: { appState.dailyLogCaptureDate = $0 }
                    ), displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $composer.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 210)
                        .background(Color.portCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if composer.text.isEmpty {
                        Text(appState.captureDestination == .brain
                             ? "Capture a thought, idea, reminder, or note…"
                             : "What happened today?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await dictation.toggle(initialText: composer.text)
                            if dictation.isRecording { composer.usedDictation = true }
                        }
                    } label: {
                        Label(dictation.isRecording ? "Stop" : "Dictate", systemImage: dictation.isRecording ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(dictation.isRecording ? .portOffline : .portAccent)

                    Button {
                        dictation.stop()
                        Task {
                            guard let instance = selectedInstance else { return }
                            await composer.submit(
                                to: instance,
                                destination: appState.captureDestination,
                                date: appState.dailyLogCaptureDate,
                                api: appState.api,
                                credentials: appState.credentials
                            )
                        }
                    } label: {
                        HStack {
                            if composer.isSubmitting { ProgressView().tint(.white) }
                            Label("Send", systemImage: "arrow.up.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(composer.isSubmitting || composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Current dictation is transcribed on this device and sends text. A future opt-in mode may send audio directly to the selected PortOS instance for processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var noInstanceState: some View {
        PortPanel {
            VStack(spacing: 14) {
                Image(systemName: "server.rack").font(.largeTitle).foregroundStyle(Color.portAccent)
                Text("Add an instance first").font(.headline)
                Text("Capture needs a PortOS destination on your tailnet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open Fleet") { appState.selectedTab = .fleet }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}
