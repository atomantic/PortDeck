import SwiftUI

struct ActionFormView: View {
    @Environment(AppState.self) private var appState
    let action: PaletteAction
    let instance: PortOSInstance

    @State private var values: [String: String] = [:]
    @State private var booleans: [String: Bool] = [:]
    @State private var includedBooleans: Set<String> = []
    @State private var isRunning = false
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var showingDestructiveConfirmation = false

    private var fields: [(String, ActionParameter)] {
        action.parameters.properties.sorted { lhs, rhs in
            let leftRequired = action.parameters.required?.contains(lhs.key) == true
            let rightRequired = action.parameters.required?.contains(rhs.key) == true
            if leftRequired != rightRequired { return leftRequired }
            return lhs.key < rhs.key
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PortPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(action.section, systemImage: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.portViolet)
                        Text(action.label).font(.title2.weight(.bold))
                        if !action.description.isEmpty {
                            Text(action.description).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                if fields.isEmpty {
                    InlineMessage(text: "This action does not need any input.")
                } else {
                    PortPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(fields, id: \.0) { name, parameter in
                                actionField(name: name, parameter: parameter)
                            }
                        }
                    }
                }

                if let resultMessage {
                    InlineMessage(text: resultMessage, kind: resultIsError ? .error : .success)
                }

                Button {
                    if action.destructive == true { showingDestructiveConfirmation = true }
                    else { Task { await runAction() } }
                } label: {
                    HStack {
                        if isRunning { ProgressView().tint(.white) }
                        Label("Run on \(instance.displayName)", systemImage: "play.fill")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(action.destructive == true ? .portOffline : .portAccent)
                .disabled(isRunning)
            }
            .padding(16)
        }
        .background(Color.portCanvas)
        .navigationTitle(action.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Run destructive action?", isPresented: $showingDestructiveConfirmation, titleVisibility: .visible) {
            Button("Run \(action.label)", role: .destructive) { Task { await runAction() } }
        } message: {
            Text("PortOS marks this action as destructive. It will run immediately on \(instance.displayName).")
        }
        .onAppear {
            for (name, parameter) in fields {
                if DemoMode.isEnabled, name == "minutes" {
                    values[name] = "50"
                }
                if action.parameters.required?.contains(name) == true,
                   let first = parameter.allowedValues?.first {
                    values[name] = first
                }
                if parameter.type == "boolean" { booleans[name] = false }
            }
        }
    }

    @ViewBuilder
    private func actionField(name: String, parameter: ActionParameter) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(name.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline.weight(.semibold))
                if action.parameters.required?.contains(name) == true {
                    Text("Required").font(.caption2.weight(.bold)).foregroundStyle(Color.portWarning)
                }
            }
            if parameter.type == "boolean" {
                Toggle("Enabled", isOn: Binding(
                    get: { booleans[name] ?? false },
                    set: {
                        booleans[name] = $0
                        includedBooleans.insert(name)
                    }
                ))
                if action.parameters.required?.contains(name) != true && !includedBooleans.contains(name) {
                    Text("Leave untouched to use the server default.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if let allowedValues = parameter.allowedValues, !allowedValues.isEmpty {
                Picker(name, selection: valueBinding(name)) {
                    if action.parameters.required?.contains(name) != true {
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

    private func valueBinding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    @MainActor
    private func runAction() async {
        guard let baseURL = instance.baseURL else { return }
        isRunning = true
        resultMessage = nil
        resultIsError = false
        defer { isRunning = false }
        do {
            var arguments: [String: JSONValue] = [:]
            for (name, parameter) in fields {
                if parameter.type == "boolean" {
                    if action.parameters.required?.contains(name) == true || includedBooleans.contains(name) {
                        arguments[name] = .bool(booleans[name] ?? false)
                    }
                    continue
                }
                let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if value.isEmpty {
                    if action.parameters.required?.contains(name) == true {
                        throw PortOSAPIError.server(status: 400, message: "\(name) is required.")
                    }
                    continue
                }
                switch parameter.type {
                case "integer":
                    guard let parsed = Int(value) else { throw PortOSAPIError.server(status: 400, message: "\(name) must be a whole number.") }
                    arguments[name] = .number(Double(parsed))
                case "number":
                    guard let parsed = Double(value) else { throw PortOSAPIError.server(status: 400, message: "\(name) must be a number.") }
                    arguments[name] = .number(parsed)
                case "object", "array":
                    guard let data = value.data(using: .utf8),
                          let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                        throw PortOSAPIError.server(status: 400, message: "\(name) must be valid JSON.")
                    }
                    if parameter.type == "object", case .object = parsed {
                        arguments[name] = parsed
                    } else if parameter.type == "array", case .array = parsed {
                        arguments[name] = parsed
                    } else {
                        throw PortOSAPIError.server(status: 400, message: "\(name) must be a JSON \(parameter.type ?? "value").")
                    }
                default: arguments[name] = .string(value)
                }
            }
            let password = try appState.credentials.password(for: instance.localID)
            let response = try await appState.api.invokeAction(
                id: action.id,
                arguments: arguments,
                baseURL: baseURL,
                password: password
            )
            resultMessage = response.result.summary ?? response.result.prettyPrinted
        } catch {
            resultMessage = error.localizedDescription
            resultIsError = true
        }
    }
}
