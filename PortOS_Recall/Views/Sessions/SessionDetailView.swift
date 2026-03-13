import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router
    let sessionID: PersistentIdentifier
    @State private var selectedTab = 0
    @State private var showDeleteConfirmation = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isProcessing = false

    var body: some View {
        Group {
            if let session = modelContext.model(for: sessionID) as? Session {
                sessionContent(session)
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .toast(isPresented: $showToast, message: toastMessage)
    }

    @ViewBuilder
    private func sessionContent(_ session: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection(session)
                if !session.audioPath.isEmpty {
                    AudioPlaybackView(audioPath: session.audioPath)
                }
                segmentedContent(session)
            }
            .padding()
        }
        .navigationTitle(session.displayTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = session.summary
                    toastMessage = "Summary copied to clipboard"
                    showToast = true
                } label: {
                    Image(systemName: "doc.on.doc")
                }

                if !session.isAnalyzed {
                    Button {
                        reanalyze(session)
                    } label: {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isProcessing)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .destructiveConfirmation(
            isPresented: $showDeleteConfirmation,
            title: "Delete Session",
            message: "This will permanently delete the recording, transcript, and all extracted memories."
        ) {
            modelContext.delete(session)
            try? modelContext.save()
            router.popToRoot()
        }
    }

    @ViewBuilder
    private func headerSection(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(session.context.displayName, systemImage: session.context.icon)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.recallAccent.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                if session.isAnalyzed {
                    Label("Analyzed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.recallSuccess)
                }
            }

            Text(session.startTime.formatted(date: .long, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let endTime = session.endTime {
                Text("Duration: \(session.formattedDuration) (ended \(endTime.formatted(date: .omitted, time: .shortened)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func segmentedContent(_ session: Session) -> some View {
        Picker("Section", selection: $selectedTab) {
            Text("Summary").tag(0)
            Text("Transcript").tag(1)
            Text("Memories").tag(2)
        }
        .pickerStyle(.segmented)

        switch selectedTab {
        case 0: summarySection(session)
        case 1: transcriptSection(session)
        case 2: memoriesSection(session)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func summarySection(_ session: Session) -> some View {
        if session.isAnalyzed {
            VStack(alignment: .leading, spacing: 12) {
                if !session.summary.isEmpty {
                    Text(session.summary)
                        .font(.body)
                }

                if !session.decodedBulletPoints.isEmpty {
                    Text("Key Points")
                        .font(.headline)
                    ForEach(session.decodedBulletPoints, id: \.self) { point in
                        HStack(alignment: .top) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .padding(.top, 6)
                            Text(point)
                        }
                    }
                }

                if !session.decodedActionItems.isEmpty {
                    Text("Action Items")
                        .font(.headline)
                    ForEach(session.decodedActionItems, id: \.self) { item in
                        HStack(alignment: .top) {
                            Image(systemName: "square")
                                .font(.caption)
                                .padding(.top, 3)
                            Text(item)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("Not Yet Analyzed", systemImage: "brain", description: Text("Tap the refresh button to analyze this session."))
        }
    }

    @ViewBuilder
    private func transcriptSection(_ session: Session) -> some View {
        if session.isTranscribed {
            Text(session.transcript)
                .font(.body)
                .textSelection(.enabled)
        } else {
            ContentUnavailableView("No Transcript", systemImage: "text.badge.xmark", description: Text("Transcription has not been completed."))
        }
    }

    @ViewBuilder
    private func memoriesSection(_ session: Session) -> some View {
        if let memories = session.memories, !memories.isEmpty {
            ForEach(memories) { memory in
                MemoryRowView(memory: memory)
            }
        } else {
            ContentUnavailableView("No Memories", systemImage: "brain.head.profile", description: Text("No memories have been extracted yet."))
        }
    }

    private func reanalyze(_ session: Session) {
        isProcessing = true
        Task {
            await ProcessingPipeline.process(session: session, context: modelContext)
            isProcessing = false
            toastMessage = "Analysis complete"
            showToast = true
        }
    }
}
