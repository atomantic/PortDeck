import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router
    @State private var recorder = AudioRecorder()
    @State private var sessionTitle = ""
    @State private var selectedContext: SessionContext = .conversation
    @State private var showConsentToast = false
    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 24) {
            if hasStarted {
                recordingActiveView
            } else {
                recordingSetupView
            }
        }
        .padding()
        .navigationTitle(hasStarted ? "Recording" : "New Recording")
        .navigationBarBackButtonHidden(hasStarted)
        .toast(isPresented: $showConsentToast, message: "Recording started. Ensure all participants consent.")
    }

    @ViewBuilder
    private var recordingSetupView: some View {
        Spacer()

        Image(systemName: "waveform.circle.fill")
            .font(.system(size: 80))
            .foregroundStyle(Color.recallRecording)

        TextField("Session Title (optional)", text: $sessionTitle)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)

        Picker("Context", selection: $selectedContext) {
            ForEach(SessionContext.allCases) { context in
                Label(context.displayName, systemImage: context.icon).tag(context)
            }
        }
        .pickerStyle(.menu)

        Text("Ensure all participants consent to being recorded.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        Button {
            startRecording()
        } label: {
            Label("Start Recording", systemImage: "record.circle")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.recallRecording)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal)

        Spacer()
    }

    @ViewBuilder
    private var recordingActiveView: some View {
        Spacer()

        RecordingIndicator()
            .padding()

        Text(recorder.elapsedTime.formattedDuration)
            .font(.system(size: 48, weight: .light, design: .monospaced))

        AudioLevelView(level: recorder.audioLevel)
            .padding(.horizontal)

        HStack(spacing: 32) {
            Button {
                if recorder.isPaused {
                    recorder.resumeRecording()
                } else {
                    recorder.pauseRecording()
                }
            } label: {
                Image(systemName: recorder.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }

            Button {
                stopRecording()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.recallRecording)
            }
        }

        Spacer()
    }

    private func startRecording() {
        Task {
            let granted = await recorder.requestMicrophonePermission()
            guard granted else {
                RecallLogger.error("Microphone permission denied")
                return
            }

            let sessionID = UUID().uuidString
            recorder.startRecording(sessionID: sessionID)
            hasStarted = true
            showConsentToast = true
        }
    }

    private func stopRecording() {
        guard let audioURL = recorder.stopRecording() else { return }

        let session = Session(
            title: sessionTitle.isEmpty ? "Session \(Date.now.formatted(date: .abbreviated, time: .shortened))" : sessionTitle,
            context: selectedContext,
            startTime: Date.now.addingTimeInterval(-recorder.elapsedTime),
            endTime: .now,
            audioPath: audioURL.path,
            durationSeconds: recorder.elapsedTime
        )
        modelContext.insert(session)
        try? modelContext.save()

        // Start processing pipeline
        Task {
            await ProcessingPipeline.process(session: session, context: modelContext)
        }

        // Schedule background processing as fallback
        BackgroundTaskManager.scheduleProcessing()

        router.popToRoot()
        router.navigate(to: SessionRoute.detail(session.persistentModelID))
    }

}
