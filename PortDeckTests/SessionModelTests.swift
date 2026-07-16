import XCTest
import SwiftData
@testable import PortDeck

final class SessionModelTests: XCTestCase {
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

    func testSessionCreation() {
        let session = Session(title: "Test Meeting", context: .meeting)
        context.insert(session)
        try! context.save()

        let descriptor = FetchDescriptor<Session>()
        let sessions = try! context.fetch(descriptor)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.title, "Test Meeting")
    }

    func testSessionDefaults() {
        let session = Session()
        XCTAssertEqual(session.title, "")
        XCTAssertEqual(session.context, .conversation)
        XCTAssertFalse(session.isAnalyzed)
        XCTAssertFalse(session.isTranscribed)
        XCTAssertEqual(session.durationSeconds, 0)
        XCTAssertEqual(session.bulletPoints, "[]")
        XCTAssertEqual(session.actionItems, "[]")
    }

    func testSessionContextEnum() {
        let session = Session(context: .dnd)
        XCTAssertEqual(session.contextRaw, "dnd")
        XCTAssertEqual(session.context, .dnd)

        session.context = .meeting
        XCTAssertEqual(session.contextRaw, "meeting")
    }

    func testSessionBulletPointsEncoding() {
        let session = Session()
        session.decodedBulletPoints = ["Point 1", "Point 2", "Point 3"]

        let decoded = session.decodedBulletPoints
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0], "Point 1")
    }

    func testSessionActionItemsEncoding() {
        let session = Session()
        session.decodedActionItems = ["TODO: Review PR", "Follow up with team"]

        let decoded = session.decodedActionItems
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0], "TODO: Review PR")
    }

    func testSessionFormattedDuration() {
        let session = Session(durationSeconds: 125)
        XCTAssertEqual(session.formattedDuration, "2:05")

        let longSession = Session(durationSeconds: 3661)
        XCTAssertEqual(longSession.formattedDuration, "1:01:01")
    }

    func testSessionMemoryCascadeDelete() {
        let session = Session(title: "Cascade Test")
        context.insert(session)

        let memory = Memory(content: "Test memory", type: .fact)
        memory.sourceSession = session
        context.insert(memory)
        try! context.save()

        let memoryDescriptor = FetchDescriptor<Memory>()
        XCTAssertEqual(try! context.fetch(memoryDescriptor).count, 1)

        context.delete(session)
        try! context.save()

        XCTAssertEqual(try! context.fetch(memoryDescriptor).count, 0)
    }

    func testSessionParticipantRelationship() {
        let session = Session(title: "Team Meeting")
        let participant = Participant(name: "Alice")
        context.insert(session)
        context.insert(participant)
        session.participants = [participant]
        try! context.save()

        XCTAssertEqual(session.participants?.count, 1)
        XCTAssertEqual(session.participants?.first?.name, "Alice")
    }
}
