import XCTest
import SwiftData
@testable import PortOS_Recall

final class MemoryModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Session.self, Memory.self, Participant.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    func testMemoryCreation() {
        let memory = Memory(content: "Project deadline is March 15", type: .fact, confidence: 0.8)
        context.insert(memory)
        try! context.save()

        let descriptor = FetchDescriptor<Memory>()
        let memories = try! context.fetch(descriptor)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.content, "Project deadline is March 15")
        XCTAssertEqual(memories.first?.confidence, 0.8)
    }

    func testMemoryDefaults() {
        let memory = Memory()
        XCTAssertEqual(memory.content, "")
        XCTAssertEqual(memory.type, .fact)
        XCTAssertEqual(memory.confidence, 0.5)
        XCTAssertEqual(memory.timestampReference, 0)
    }

    func testMemoryTypeEnum() {
        let memory = Memory(type: .actionItem)
        XCTAssertEqual(memory.typeRaw, "actionItem")
        XCTAssertEqual(memory.type, .actionItem)

        memory.type = .decision
        XCTAssertEqual(memory.typeRaw, "decision")
    }

    func testMemoryTypeEnumRoundTripping() {
        for memoryType in MemoryType.allCases {
            let memory = Memory(type: memoryType)
            XCTAssertEqual(memory.type, memoryType)
            XCTAssertEqual(memory.typeRaw, memoryType.rawValue)
        }
    }

    func testSessionContextEnumRoundTripping() {
        for sessionContext in SessionContext.allCases {
            let session = Session(context: sessionContext)
            XCTAssertEqual(session.context, sessionContext)
            XCTAssertEqual(session.contextRaw, sessionContext.rawValue)
        }
    }

    func testMemorySourceSessionRelationship() {
        let session = Session(title: "Source Session")
        let memory = Memory(content: "Test", type: .fact)
        context.insert(session)
        context.insert(memory)
        memory.sourceSession = session
        try! context.save()

        XCTAssertEqual(memory.sourceSession?.title, "Source Session")
    }
}
