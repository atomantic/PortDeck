import Foundation
import SwiftData

struct PreviewSampleData {
    @MainActor
    static var previewContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Session.self, Memory.self, Participant.self,
            configurations: config
        )
        populate(container: container)
        return container
    }()

    @MainActor
    static func populate(container: ModelContainer) {
        let context = container.mainContext

        // MARK: - Participants

        let alice = Participant(name: "Alice Chen", notes: "Product lead, prefers async updates")
        let bob = Participant(name: "Bob Martinez", notes: "Engineering manager")
        let carol = Participant(name: "Carol Nguyen", notes: "Designer, owns the mobile redesign")
        let dave = Participant(name: "Dave the Barbarian", notes: "Half-orc fighter, chaotic good")
        let elara = Participant(name: "Elara Moonwhisper", notes: "Elf wizard, keeper of the scroll")

        [alice, bob, carol, dave, elara].forEach { context.insert($0) }

        // MARK: - Session 1: Meeting

        let meetingStart = Calendar.current.date(byAdding: .hour, value: -3, to: .now)!
        let meetingEnd = Calendar.current.date(byAdding: .minute, value: 45, to: meetingStart)!

        let meetingSession = Session(
            title: "Q2 Roadmap Review",
            context: .meeting,
            startTime: meetingStart,
            endTime: meetingEnd,
            transcript: "Alice: Let's kick off the Q2 review. Bob, where are we on the API migration?",
            summary: "Reviewed Q2 priorities. API migration on track for April. Mobile redesign pushed to May pending Carol's wireframes. Agreed to weekly syncs.",
            bulletPoints: "[\"API migration targeting April launch\",\"Mobile redesign shifted to May\",\"Weekly sync meetings starting next Monday\"]",
            actionItems: "[\"Bob: Share migration timeline by Friday\",\"Carol: Deliver wireframes by April 1\",\"Alice: Send updated roadmap to stakeholders\"]",
            isAnalyzed: true,
            isTranscribed: true,
            durationSeconds: 2700
        )
        context.insert(meetingSession)
        meetingSession.participants = [alice, bob, carol]

        let meetingMemory1 = Memory(content: "API migration targeting April launch", type: .decision, confidence: 0.95, timestampReference: 120)
        meetingMemory1.sourceSession = meetingSession
        let meetingMemory2 = Memory(content: "Bob owns the migration timeline", type: .actionItem, confidence: 0.9, timestampReference: 340)
        meetingMemory2.sourceSession = meetingSession
        let meetingMemory3 = Memory(content: "Carol is leading the mobile redesign", type: .person, confidence: 0.85, timestampReference: 600)
        meetingMemory3.sourceSession = meetingSession
        [meetingMemory1, meetingMemory2, meetingMemory3].forEach { context.insert($0) }

        // MARK: - Session 2: D&D

        let dndStart = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let dndEnd = Calendar.current.date(byAdding: .hour, value: 3, to: dndStart)!

        let dndSession = Session(
            title: "Curse of Strahd - Session 14",
            context: .dnd,
            startTime: dndStart,
            endTime: dndEnd,
            transcript: "DM: You enter the crumbling chapel. Dave, roll perception.",
            summary: "The party explored the chapel beneath Castle Ravenloft. Dave found a hidden passage behind the altar. Elara deciphered the rune ward protecting the Sunsword.",
            bulletPoints: "[\"Hidden passage discovered behind the altar\",\"Rune ward on the Sunsword deciphered by Elara\",\"Three specters defeated in combat\"]",
            actionItems: "[\"Dave: Update character sheet with +1 inspiration\",\"Elara: Prepare identify spell for next session\"]",
            isAnalyzed: true,
            isTranscribed: true,
            durationSeconds: 10800
        )
        context.insert(dndSession)
        dndSession.participants = [dave, elara]

        let dndMemory1 = Memory(content: "Hidden passage found behind the chapel altar", type: .fact, confidence: 1.0, timestampReference: 1800)
        dndMemory1.sourceSession = dndSession
        let dndMemory2 = Memory(content: "Elara deciphered the Sunsword rune ward", type: .decision, confidence: 0.9, timestampReference: 4200)
        dndMemory2.sourceSession = dndSession
        [dndMemory1, dndMemory2].forEach { context.insert($0) }

        // MARK: - Session 3: Conversation

        let convoStart = Calendar.current.date(byAdding: .hour, value: -1, to: .now)!
        let convoEnd = Calendar.current.date(byAdding: .minute, value: 20, to: convoStart)!

        let convoSession = Session(
            title: "Catch-up with Bob",
            context: .conversation,
            startTime: convoStart,
            endTime: convoEnd,
            transcript: "Bob mentioned he's thinking about switching to the platform team after Q2.",
            summary: "Informal chat with Bob. He's considering a move to the platform team.",
            bulletPoints: "[\"Bob considering platform team move after Q2\"]",
            actionItems: "[\"Follow up with Bob about platform team interest in April\"]",
            isAnalyzed: true,
            isTranscribed: true,
            durationSeconds: 1200
        )
        context.insert(convoSession)
        convoSession.participants = [bob]

        let convoMemory1 = Memory(content: "Bob is considering moving to the platform team after Q2", type: .fact, confidence: 0.75, timestampReference: 300)
        convoMemory1.sourceSession = convoSession
        context.insert(convoMemory1)

        try? context.save()
    }
}
