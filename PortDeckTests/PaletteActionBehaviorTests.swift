import XCTest
@testable import PortDeck

final class PaletteActionBehaviorTests: XCTestCase {
    func testReadVerbWithoutRequiredParametersIsAReader() throws {
        let action = try PaletteActionFixture.make(
            id: "brain_list_recent",
            properties: #"{"limit":{"type":"integer","description":"How many entries."}}"#
        )
        XCTAssertTrue(action.isReader)
        XCTAssertEqual(action.pageSizeParameterName, "limit")
    }

    func testActionsWithoutARequiredParameterButAWriteVerbAreNotReaders() throws {
        // timer_set takes no required parameters and still creates a timer — opening
        // its page must not fire it.
        let action = try PaletteActionFixture.make(
            id: "timer_set",
            properties: #"{"minutes":{"type":"integer"}}"#
        )
        XCTAssertFalse(action.isReader)
    }

    func testActionsWithRequiredParametersAreNotReadersButStayPageable() throws {
        let action = try PaletteActionFixture.make(
            id: "brain_search",
            properties: #"{"query":{"type":"string"},"limit":{"type":"integer"}}"#,
            required: ["query"]
        )
        XCTAssertFalse(action.isReader, "a required query means there is nothing to fetch on open")
        XCTAssertTrue(action.isReadShaped, "re-running a search to widen it is safe")
        XCTAssertEqual(action.pageSizeParameterName, "limit")
    }

    func testWriteShapedActionsAreNeverPageable() throws {
        // Paging re-invokes the action, so a writer must never qualify.
        let action = try PaletteActionFixture.make(id: "timer_set", properties: #"{"limit":{"type":"integer"}}"#)
        XCTAssertFalse(action.isReadShaped)
    }

    func testDestructiveActionsAreNeverReaders() throws {
        let action = try PaletteActionFixture.make(id: "pm2_status", properties: "{}", destructive: true)
        XCTAssertFalse(action.isReader)
    }

    func testKnownPortOSReadersAreRecognized() throws {
        for id in ["goal_list", "pm2_status", "calendar_today", "calendar_next", "weather_now",
                   "daily_log_read", "feeds_digest", "time_now", "meatspace_summary_today",
                   "code_agent_status"] {
            let action = try PaletteActionFixture.make(id: id, properties: "{}")
            XCTAssertTrue(action.isReader, "\(id) should be a reader")
        }
    }

    func testKnownPortOSWritersAreNotReaders() throws {
        for id in ["brain_capture", "daily_log_append", "image_generate", "ui_ask",
                   "dispatch_code_agent", "workspace_switch", "meatspace_log_drink"] {
            let action = try PaletteActionFixture.make(id: id, properties: "{}")
            XCTAssertFalse(action.isReader, "\(id) should not auto-run")
        }
    }

    func testAWriteVerbBeatsAReadVerbInTheSameID() throws {
        // PortOS ships new actions without an app release, so ids that read half like a
        // query — "back it up now", "mark it read" — must not auto-invoke.
        for id in ["backup_now", "sync_now", "feeds_mark_read", "cache_clear_stats"] {
            let action = try PaletteActionFixture.make(id: id, properties: "{}")
            XCTAssertFalse(action.isReadShaped, "\(id) mutates and must stay a manual run")
        }
    }

    func testPageSizeParameterIgnoresNonNumericMatches() throws {
        let action = try PaletteActionFixture.make(id: "goal_list", properties: #"{"limit":{"type":"string"}}"#)
        XCTAssertNil(action.pageSizeParameterName)
    }

    func testOrderedParametersPutRequiredFirstThenAlphabetical() throws {
        let action = try PaletteActionFixture.make(
            id: "focus_start",
            properties: #"{"zebra":{"type":"string"},"alpha":{"type":"string"},"mode":{"type":"string"}}"#,
            required: ["mode"]
        )
        XCTAssertEqual(action.orderedParameters.map(\.name), ["mode", "alpha", "zebra"])
    }
}
