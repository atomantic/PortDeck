import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \PortOSInstance.addedAt) private var instances: [PortOSInstance]

    @State private var destination = CaptureDestination.brain
    @State private var text = DemoMode.isEnabled ? DemoData.captureText : ""
    @State private var selectedDate = Date()
    @State private var dictation = DictationController()
    @State private var usedDictation = false
    @State private var isSubmitting = false
    @State private var message: (String, InlineMessage.Kind)?

    private enum CaptureDestination: String, CaseIterable, Identifiable {
        case brain = "Brain"
        case dailyLog = "Daily Log"
        var id: String { rawValue }
        var icon: String { self == .brain ? "brain.head.profile" : "book.pages" }
    }

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
                        if let message { InlineMessage(text: message.0, kind: message.1) }
                    }
                }
                .padding(16)
            }
            .background(Color.portCanvas)
            .navigationTitle("Capture")
            .onChange(of: dictation.transcript) { text = dictation.transcript }
            .onDisappear { dictation.stop() }
            .task {
                if appState.selectedInstanceID == nil, let first = instances.first { appState.select(first) }
            }
        }
    }

    private var captureComposer: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Destination", selection: $destination) {
                    ForEach(CaptureDestination.allCases) { destination in
                        Label(destination.rawValue, systemImage: destination.icon).tag(destination)
                    }
                }
                .pickerStyle(.segmented)

                if destination == .dailyLog {
                    DatePicker("Log date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 210)
                        .background(Color.portCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if text.isEmpty {
                        Text(destination == .brain
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
                            await dictation.toggle(initialText: text)
                            if dictation.isRecording { usedDictation = true }
                        }
                    } label: {
                        Label(dictation.isRecording ? "Stop" : "Dictate", systemImage: dictation.isRecording ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(dictation.isRecording ? .portOffline : .portAccent)

                    Button {
                        dictation.stop()
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Label("Send", systemImage: "arrow.up.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    @MainActor
    private func submit() async {
        guard let instance = selectedInstance, let baseURL = instance.baseURL else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        message = nil
        defer { isSubmitting = false }
        do {
            let password = try appState.credentials.password(for: instance.localID)
            switch destination {
            case .brain:
                let response = try await appState.api.invokeAction(
                    id: "brain_capture",
                    arguments: ["text": .string(trimmed)],
                    baseURL: baseURL,
                    password: password
                )
                message = (response.result.summary ?? "Captured to Brain.", .success)
            case .dailyLog:
                let date = Self.dateString(selectedDate)
                if usedDictation {
                    let response = try await appState.api.invokeAction(
                        id: "daily_log_append",
                        arguments: ["text": .string(trimmed), "date": .string(date)],
                        baseURL: baseURL,
                        password: password
                    )
                    message = (response.result.summary ?? "Added to the daily log.", .success)
                } else {
                    let response = try await appState.api.appendDailyLog(
                        text: trimmed,
                        date: date,
                        source: "text",
                        baseURL: baseURL,
                        password: password
                    )
                    message = ("Added to the daily log for \(response.date).", .success)
                }
            }
            text = ""
            dictation.transcript = ""
            usedDictation = false
        } catch {
            message = (error.localizedDescription, .error)
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
