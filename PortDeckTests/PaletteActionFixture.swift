import Foundation
@testable import PortDeck

/// Builds a `PaletteAction` the way the server sends one — through JSON, so the tests
/// exercise the same decoding path the manifest does.
enum PaletteActionFixture {
    static func make(
        id: String = "test_action",
        label: String? = nil,
        section: String = "Test",
        properties: String = "{}",
        required: [String] = [],
        destructive: Bool = false
    ) throws -> PaletteAction {
        let requiredData = try JSONSerialization.data(withJSONObject: required)
        let requiredJSON = String(data: requiredData, encoding: .utf8) ?? "[]"
        let json = """
        {
          "id": "\(id)",
          "label": "\(label ?? id)",
          "section": "\(section)",
          "description": "",
          "destructive": \(destructive),
          "parameters": { "type": "object", "properties": \(properties), "required": \(requiredJSON) }
        }
        """
        return try JSONDecoder().decode(PaletteAction.self, from: Data(json.utf8))
    }
}
