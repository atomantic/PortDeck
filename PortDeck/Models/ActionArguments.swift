import Foundation

/// Raw form input for a palette action, kept as text until it is validated into JSON.
struct ActionArgumentState: Equatable, Sendable {
    var values: [String: String] = [:]
    var booleans: [String: Bool] = [:]
    /// Booleans the user actually touched — untouched optional toggles stay off the wire
    /// so PortOS applies its own default.
    var includedBooleans: Set<String> = []

    init() {}

    /// Seeds the form from the action's schema: a required enum needs a selection before the
    /// user can submit, and every toggle starts off (untouched, so still omitted).
    init(defaultsFor action: PaletteAction) {
        for (name, parameter) in action.orderedParameters {
            if action.isRequired(name), let first = parameter.allowedValues?.first {
                values[name] = first
            }
            if parameter.type == "boolean" { booleans[name] = false }
        }
    }

    mutating func setValue(_ value: String, for name: String) {
        values[name] = value
    }

    mutating func setBoolean(_ value: Bool, for name: String) {
        booleans[name] = value
        includedBooleans.insert(name)
    }

    func value(for name: String) -> String { values[name] ?? "" }

    func boolean(for name: String) -> Bool { booleans[name] ?? false }

    func integer(for name: String) -> Int? { Int(value(for: name).trimmingCharacters(in: .whitespaces)) }
}

enum ActionArgumentError: LocalizedError, Equatable {
    case missingRequired(String)
    case notAWholeNumber(String)
    case notANumber(String)
    case notJSON(name: String, type: String)

    var errorDescription: String? {
        switch self {
        case .missingRequired(let name): "\(name.humanizedFieldName) is required."
        case .notAWholeNumber(let name): "\(name.humanizedFieldName) must be a whole number."
        case .notANumber(let name): "\(name.humanizedFieldName) must be a number."
        case .notJSON(let name, let type): "\(name.humanizedFieldName) must be a JSON \(type)."
        }
    }
}

enum ActionArgumentBuilder {
    /// Validates form state against the action's parameter schema and produces the request body.
    ///
    /// Empty optional fields are omitted rather than sent blank, so PortOS keeps its defaults.
    static func build(action: PaletteAction, state: ActionArgumentState) throws -> [String: JSONValue] {
        var arguments: [String: JSONValue] = [:]
        for (name, parameter) in action.orderedParameters {
            if parameter.type == "boolean" {
                if action.isRequired(name) || state.includedBooleans.contains(name) {
                    arguments[name] = .bool(state.boolean(for: name))
                }
                continue
            }
            let value = state.value(for: name).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                if action.isRequired(name) { throw ActionArgumentError.missingRequired(name) }
                continue
            }
            arguments[name] = try encode(value: value, name: name, type: parameter.type)
        }
        return arguments
    }

    private static func encode(value: String, name: String, type: String?) throws -> JSONValue {
        switch type {
        case "integer":
            guard let parsed = Int(value) else { throw ActionArgumentError.notAWholeNumber(name) }
            return .number(Double(parsed))
        case "number":
            guard let parsed = Double(value) else { throw ActionArgumentError.notANumber(name) }
            return .number(parsed)
        case "object", "array":
            guard let data = value.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(JSONValue.self, from: data),
                  type == "object" ? parsed.objectValue != nil : parsed.arrayValue != nil else {
                throw ActionArgumentError.notJSON(name: name, type: type ?? "value")
            }
            return parsed
        default:
            return .string(value)
        }
    }
}
