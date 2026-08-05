import XCTest
@testable import PortDeck

final class ActionResultDisplayTests: XCTestCase {
    func testBrainListRecentRendersEntriesInsteadOfOnlyTheSummary() throws {
        let display = try makeDisplay("""
        {
          "ok": true,
          "count": 2,
          "items": [
            { "date": "2026-07-16", "text": "Mirror the field kit before the demo." },
            { "date": "2026-07-15", "text": "Ask about the nightly backup window." }
          ],
          "summary": "Last 2 captures."
        }
        """)

        XCTAssertEqual(display.summary, "Last 2 captures.")
        XCTAssertFalse(display.isFailure)
        XCTAssertEqual(display.collectionLabel, "Items")
        XCTAssertEqual(display.rows.map(\.title), [
            "Mirror the field kit before the demo.",
            "Ask about the nightly backup window."
        ])
        // Date-only values are formatted in UTC so they never slide to the previous day.
        let subtitle = try XCTUnwrap(display.rows.first?.subtitle)
        XCTAssertNotEqual(subtitle, "2026-07-16", "the date should be humanized")
        XCTAssertTrue(subtitle.contains("16") && subtitle.contains("2026"), "unexpected date rendering: \(subtitle)")
        XCTAssertEqual(display.facts.map(\.label), ["Count"])
        XCTAssertEqual(display.facts.first?.value, "2")
    }

    func testCollectionPriorityPicksThePayloadListOverIncidentalArrays() throws {
        let display = try makeDisplay("""
        { "ok": true, "tags": ["a", "b"], "hits": [{ "title": "Match" }], "summary": "Found 1 match" }
        """)

        XCTAssertEqual(display.collectionLabel, "Hits")
        XCTAssertEqual(display.rows.map(\.title), ["Match"])
        XCTAssertTrue(display.facts.contains { $0.label == "Tags" })
    }

    func testAnEmptyKnownCollectionStillWinsOverAnIncidentalArray() throws {
        // "No entries" is the answer here — rendering `tags` as the list would hide it.
        let display = try makeDisplay(#"{ "ok": true, "items": [], "tags": ["inbox"], "summary": "Brain inbox is empty." }"#)
        XCTAssertEqual(display.collectionLabel, "Items")
        XCTAssertTrue(display.rows.isEmpty)
        XCTAssertTrue(display.hasCollection)
    }

    func testFieldsKeepDistinctIdentityWhenLabelsCollide() throws {
        let display = try makeDisplay(#"{ "ok": true, "userId": 1, "user_id": 2 }"#)
        XCTAssertEqual(display.facts.map(\.label), ["User id", "User id"])
        XCTAssertEqual(Set(display.facts.map(\.id)).count, 2)
    }

    func testEmptyCollectionIsDistinguishedFromANonListResult() throws {
        let empty = try makeDisplay(#"{ "ok": true, "items": [], "summary": "Brain inbox is empty." }"#)
        XCTAssertTrue(empty.hasCollection)
        XCTAssertTrue(empty.rows.isEmpty)

        let scalar = try makeDisplay(#"{ "ok": true, "temperature": 71, "summary": "71 and clear." }"#)
        XCTAssertFalse(scalar.hasCollection)
        XCTAssertEqual(scalar.facts.map(\.value), ["71"])
    }

    func testToolFailureInsideAnHTTP200EnvelopeIsReportedAsFailure() throws {
        let display = try makeDisplay(#"{ "ok": false, "summary": "Couldn't reach the weather service." }"#)
        XCTAssertTrue(display.isFailure)
    }

    func testTransportEnvelopeFailurePropagates() throws {
        let display = try makeDisplay(#"{ "ok": true, "summary": "Done." }"#, envelopeOK: false)
        XCTAssertTrue(display.isFailure)
    }

    func testLongFormStringsBecomePassagesRatherThanFacts() throws {
        let display = try makeDisplay("""
        { "ok": true, "date": "2026-07-16", "content": "Woke early. Shipped the sync fix.", "segments": 3,
          "summary": "Daily log for 2026-07-16 (3 segments)." }
        """)

        XCTAssertEqual(display.passages.map(\.label), ["Content"])
        XCTAssertEqual(display.passages.first?.value, "Woke early. Shipped the sync fix.")
        XCTAssertEqual(display.facts.map(\.label), ["Date", "Segments"])
    }

    func testTopLevelArrayResultsRenderAsRows() throws {
        let display = try makeDisplay(#"[{ "name": "portos-server" }, { "name": "portos-client" }]"#)
        XCTAssertEqual(display.collectionLabel, "Results")
        XCTAssertEqual(display.rows.map(\.title), ["portos-server", "portos-client"])
    }

    func testRowsKeepRemainingFieldsAndFormatValues() throws {
        let display = try makeDisplay("""
        { "ok": true, "goals": [{ "title": "Ship it", "progress": 72, "starred": true, "horizon": "quarter" }] }
        """)

        let row = try XCTUnwrap(display.rows.first)
        XCTAssertEqual(row.title, "Ship it")
        XCTAssertEqual(row.fields.map(\.label), ["Horizon", "Progress", "Starred"])
        XCTAssertEqual(row.fields.map(\.value), ["quarter", "72", "Yes"])
    }

    func testScalarCollectionElementsStillRender() throws {
        let display = try makeDisplay(#"{ "ok": true, "items": ["first", "second"] }"#)
        XCTAssertEqual(display.rows.map(\.title), ["first", "second"])
        XCTAssertTrue(display.rows.allSatisfy { $0.fields.isEmpty })
    }

    func testRawJSONIsAlwaysAvailable() throws {
        let display = try makeDisplay(#"{ "ok": true, "nested": { "a": 1 } }"#)
        XCTAssertTrue(display.rawJSON.contains("nested"))
    }

    private func makeDisplay(_ json: String, envelopeOK: Bool = true) throws -> ActionResultDisplay {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return ActionResultDisplay(result: value, envelopeOK: envelopeOK)
    }
}
