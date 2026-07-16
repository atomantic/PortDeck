import SwiftUI
import SwiftData

struct MemoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router
    @Query(sort: \Memory.createdAt, order: .reverse) private var memories: [Memory]
    @State private var searchText = ""
    @State private var selectedFilter: MemoryType? = nil

    var filteredMemories: [Memory] {
        var result = memories
        if let filter = selectedFilter {
            result = result.filter { $0.type == filter }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        Group {
            if memories.isEmpty {
                EmptyStateView(
                    icon: "brain.head.profile",
                    title: "No Memories",
                    message: "Memories are automatically extracted from recorded sessions."
                )
            } else {
                VStack(spacing: 0) {
                    filterChips
                    List(filteredMemories) { memory in
                        Button {
                            if let session = memory.sourceSession {
                                router.navigate(to: SessionRoute.detail(session.persistentModelID), tab: .sessions)
                            }
                        } label: {
                            MemoryRowView(memory: memory)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search memories")
            }
        }
        .navigationTitle("Memories")
    }

    @ViewBuilder
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                ForEach(MemoryType.allCases) { type in
                    FilterChip(label: type.displayName, isSelected: selectedFilter == type) {
                        selectedFilter = type
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
