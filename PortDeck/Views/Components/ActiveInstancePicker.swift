import SwiftUI

struct ActiveInstancePicker: View {
    @Environment(AppState.self) private var appState
    let instances: [PortOSInstance]

    private var selected: PortOSInstance? {
        instances.first { $0.localID == appState.selectedInstanceID } ?? instances.first
    }

    var body: some View {
        Menu {
            ForEach(instances) { instance in
                Button {
                    appState.select(instance)
                } label: {
                    if instance.localID == selected?.localID {
                        Label(instance.displayName, systemImage: "checkmark")
                    } else {
                        Text(instance.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Color.portAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Target instance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selected?.displayName ?? "Choose an instance")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.portPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Target instance")
        .accessibilityValue(selected?.displayName ?? "None")
    }
}
