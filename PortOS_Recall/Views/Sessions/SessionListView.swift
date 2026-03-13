import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router
    @Query(sort: \Session.startTime, order: .reverse) private var sessions: [Session]
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: Session?

    var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                EmptyStateView(
                    icon: "waveform",
                    title: "No Sessions",
                    message: "Start recording to capture your first session.",
                    actionLabel: "Start Recording"
                ) {
                    router.navigate(to: SessionRoute.recording)
                }
            } else {
                List {
                    ForEach(filteredSessions) { session in
                        Button {
                            router.navigate(to: SessionRoute.detail(session.persistentModelID))
                        } label: {
                            SessionRowView(session: session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                sessionToDelete = session
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search sessions")
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.navigate(to: SessionRoute.recording)
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .foregroundStyle(.red)
                }
            }
        }
        .destructiveConfirmation(
            isPresented: $showDeleteConfirmation,
            title: "Delete Session",
            message: "This will permanently delete the recording, transcript, and all extracted memories."
        ) {
            if let session = sessionToDelete {
                modelContext.delete(session)
                try? modelContext.save()
            }
        }
    }
}
