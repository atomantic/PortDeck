import SwiftUI

/// Builds input controls from a palette action's JSON parameter schema.
struct ActionParameterForm: View {
    let action: PaletteAction
    @Binding var state: ActionArgumentState
    /// Called whenever the user edits a field, so a paged reader can drop its "end of list" latch.
    var onEdit: () -> Void = {}

    /// Sorted once — the body re-evaluates on every keystroke.
    private let fields: [(name: String, parameter: ActionParameter)]

    init(action: PaletteAction, state: Binding<ActionArgumentState>, onEdit: @escaping () -> Void = {}) {
        self.action = action
        _state = state
        self.onEdit = onEdit
        fields = action.orderedParameters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(fields, id: \.name) { name, parameter in
                field(name: name, parameter: parameter)
            }
        }
    }

    @ViewBuilder
    private func field(name: String, parameter: ActionParameter) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(name.humanizedFieldName).font(.subheadline.weight(.semibold))
                if action.isRequired(name) {
                    Text("Required").font(.caption2.weight(.bold)).foregroundStyle(Color.portWarning)
                }
            }
            if parameter.type == "boolean" {
                Toggle("Enabled", isOn: Binding(
                    get: { state.boolean(for: name) },
                    set: { state.setBoolean($0, for: name); onEdit() }
                ))
                if !action.isRequired(name) && !state.includedBooleans.contains(name) {
                    Text("Leave untouched to use the server default.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if let allowedValues = parameter.allowedValues, !allowedValues.isEmpty {
                Picker(name, selection: valueBinding(name)) {
                    if !action.isRequired(name) {
                        Text("Server default").tag("")
                    }
                    ForEach(allowedValues, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            } else {
                TextField("Enter \(name)", text: valueBinding(name), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(parameter.type == "integer" || parameter.type == "number" ? .decimalPad : .default)
            }
            if let description = parameter.description {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func valueBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { state.value(for: name) },
            set: { state.setValue($0, for: name); onEdit() }
        )
    }
}
