import SwiftUI
import SwiftData

struct MemoryRowView: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: memory.type.icon)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(memory.type.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("\(Int(memory.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(memory.content)
                .font(.subheadline)

            HStack {
                if let session = memory.sourceSession {
                    Text(session.displayTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
