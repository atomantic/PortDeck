import SwiftUI

/// Renders a palette action's payload: rows first, then long-form text, then leftover scalars.
struct ActionResultView: View {
    let display: ActionResultDisplay

    @State private var showsRawJSON = false

    var body: some View {
        VStack(spacing: 12) {
            if let summary = display.summary, !summary.isEmpty {
                InlineMessage(text: summary, kind: display.isFailure ? .error : .info)
            }

            if display.hasCollection && display.rows.isEmpty {
                PortPanel {
                    Text("PortOS returned no entries.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }

            ForEach(display.rows) { row in
                ResultRowCard(row: row)
            }

            ForEach(display.passages) { passage in
                PortPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(passage.label.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(passage.value)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
            }

            if !display.facts.isEmpty {
                PortPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(display.facts) { fact in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(fact.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(fact.value)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showsRawJSON) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(display.rawJSON)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
            } label: {
                Text("Raw response")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct ResultRowCard: View {
    let row: ActionResultDisplay.Row

    var body: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.portAccent)
                }
                Text(row.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !row.fields.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(row.fields) { field in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(field.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(field.value)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
