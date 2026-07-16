import SwiftUI

struct PortPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.portPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
    }
}

struct InstanceStatusBadge: View {
    let state: InstanceConnectionState

    private var presentation: (label: String, icon: String, color: Color) {
        switch state {
        case .unknown: ("Not checked", "circle.dotted", .secondary)
        case .checking: ("Checking", "arrow.triangle.2.circlepath", .portAccent)
        case .online: ("Online", "checkmark.circle.fill", .portOnline)
        case .needsPassword: ("Password needed", "lock.fill", .portWarning)
        case .offline: ("Offline", "exclamationmark.triangle.fill", .portOffline)
        }
    }

    var body: some View {
        Label(presentation.label, systemImage: presentation.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(presentation.color.opacity(0.12), in: Capsule())
    }
}

struct InlineMessage: View {
    enum Kind { case info, success, error }

    let text: String
    var kind: Kind = .info

    private var color: Color {
        switch kind {
        case .info: .portAccent
        case .success: .portOnline
        case .error: .portOffline
        }
    }

    private var icon: String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
