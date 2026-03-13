import XCTest
import SwiftData
@testable import PortOS_Recall

final class MemoryExtractorTests: XCTestCase {
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

    func testExtractMemoriesFromAnalysis() {
        let session = Session(title: "Test Session")
        context.insert(session)

        let analysis = SessionAnalysis(
            summary: "A productive meeting",
            bulletPoints: ["Discussed roadmap", "Reviewed budget"],
            actionItems: ["Update the docs", "Send follow-up email"],
            decisions: ["Approved the new design"],
            entities: ["Alice", "Bob"],
            topics: ["Design", "Budget"]
        )

        let memories = MemoryExtractor.extract(from: analysis, session: session, context: context)

        let actionItems = memories.filter { $0.type == .actionItem }
        XCTAssertEqual(actionItems.count, 2)

        let decisions = memories.filter { $0.type == .decision }
        XCTAssertEqual(decisions.count, 1)

        let people = memories.filter { $0.type == .person }
        XCTAssertEqual(people.count, 2)

        let topics = memories.filter { $0.type == .topic }
        XCTAssertEqual(topics.count, 2)

        let facts = memories.filter { $0.type == .fact }
        XCTAssertEqual(facts.count, 2)

        // All memories should reference the source session
        for memory in memories {
            XCTAssertEqual(memory.sourceSession?.title, "Test Session")
        }
    }

    func testExtractMemoriesConfidence() {
        let session = Session(title: "Confidence Test")
        context.insert(session)

        let analysis = SessionAnalysis(
            summary: "Test",
            bulletPoints: [],
            actionItems: ["Do something"],
            decisions: [],
            entities: ["PersonName"],
            topics: []
        )

        let memories = MemoryExtractor.extract(from: analysis, session: session, context: context)

        let actionItem = memories.first { $0.type == .actionItem }
        XCTAssertEqual(actionItem?.confidence, 0.5) // NLP fallback confidence

        let person = memories.first { $0.type == .person }
        XCTAssertEqual(person?.confidence, 0.7) // Entity confidence
    }

    func testExtractEmptyAnalysis() {
        let session = Session(title: "Empty")
        context.insert(session)

        let analysis = SessionAnalysis(
            summary: "",
            bulletPoints: [],
            actionItems: [],
            decisions: [],
            entities: [],
            topics: []
        )

        let memories = MemoryExtractor.extract(from: analysis, session: session, context: context)
        XCTAssertTrue(memories.isEmpty)
    }
}
