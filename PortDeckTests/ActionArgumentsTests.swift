import XCTest
@testable import PortDeck

final class ActionArgumentsTests: XCTestCase {
    func testEmptyOptionalFieldsAreOmittedSoPortOSKeepsItsDefaults() throws {
        let action = try PaletteActionFixture.make(properties: #"{"limit":{"type":"integer"}}"#)
        let arguments = try ActionArgumentBuilder.build(action: action, state: ActionArgumentState())
        XCTAssertTrue(arguments.isEmpty)
    }

    func testMissingRequiredFieldFails() throws {
        let action = try PaletteActionFixture.make(properties: #"{"query":{"type":"string"}}"#, required: ["query"])
        XCTAssertThrowsError(try ActionArgumentBuilder.build(action: action, state: ActionArgumentState())) { error in
            XCTAssertEqual(error as? ActionArgumentError, .missingRequired("query"))
        }
    }

    func testTypedValuesAreEncodedFromText() throws {
        let action = try PaletteActionFixture.make(properties: """
        {"limit":{"type":"integer"},"weight":{"type":"number"},"note":{"type":"string"},"tags":{"type":"array"}}
        """)
        var state = ActionArgumentState()
        state.setValue("10", for: "limit")
        state.setValue("182.4", for: "weight")
        state.setValue(" trailing space ", for: "note")
        state.setValue(#"["a","b"]"#, for: "tags")

        let arguments = try ActionArgumentBuilder.build(action: action, state: state)
        XCTAssertEqual(arguments["limit"], .number(10))
        XCTAssertEqual(arguments["weight"], .number(182.4))
        XCTAssertEqual(arguments["note"], .string("trailing space"))
        XCTAssertEqual(arguments["tags"], .array([.string("a"), .string("b")]))
    }

    func testNonNumericInputIsRejected() throws {
        let action = try PaletteActionFixture.make(properties: #"{"limit":{"type":"integer"}}"#)
        var state = ActionArgumentState()
        state.setValue("five", for: "limit")
        XCTAssertThrowsError(try ActionArgumentBuilder.build(action: action, state: state)) { error in
            XCTAssertEqual(error as? ActionArgumentError, .notAWholeNumber("limit"))
        }
    }

    func testJSONShapeIsEnforced() throws {
        let action = try PaletteActionFixture.make(properties: #"{"payload":{"type":"object"}}"#)
        var state = ActionArgumentState()
        state.setValue(#"["not","an","object"]"#, for: "payload")
        XCTAssertThrowsError(try ActionArgumentBuilder.build(action: action, state: state)) { error in
            XCTAssertEqual(error as? ActionArgumentError, .notJSON(name: "payload", type: "object"))
        }
    }

    func testUntouchedOptionalBooleansStayOffTheWire() throws {
        let action = try PaletteActionFixture.make(properties: #"{"quiet":{"type":"boolean"}}"#)
        var state = ActionArgumentState()
        state.booleans["quiet"] = false
        XCTAssertTrue(try ActionArgumentBuilder.build(action: action, state: state).isEmpty)

        state.setBoolean(false, for: "quiet")
        XCTAssertEqual(try ActionArgumentBuilder.build(action: action, state: state)["quiet"], .bool(false))
    }

    func testHumanizedFieldNames() {
        XCTAssertEqual("startTime".humanizedFieldName, "Start time")
        XCTAssertEqual("start_time".humanizedFieldName, "Start time")
        XCTAssertEqual("text".humanizedFieldName, "Text")
        XCTAssertEqual("goalQuery".humanizedFieldName, "Goal query")
    }
}
