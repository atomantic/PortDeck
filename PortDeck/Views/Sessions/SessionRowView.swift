import SwiftUI
import SwiftData

struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.displayTitle)
                    .font(.headline)
                Spacer()
                Text(session.context.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack {
                Image(systemName: session.context.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.isAnalyzed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.recallSuccess)
                } else if session.isTranscribed {
                    Image(systemName: "text.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.recallWarning)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
