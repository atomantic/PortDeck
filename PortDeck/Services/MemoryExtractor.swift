import Foundation
import SwiftData

enum MemoryExtractor {
    /// Minimum transcript length to warrant memory extraction
    private static let minimumTranscriptLength = 30

    static func extract(from analysis: SessionAnalysis, session: Session, context: ModelContext) -> [Memory] {
        RecallLogger.analysis("Extracting memories from analysis")

        let transcript = session.transcript
        guard transcript.count >= minimumTranscriptLength else {
            RecallLogger.analysis("Transcript too short for memory extraction (\(transcript.count) chars)")
            return []
        }

        var items: [(String, MemoryType, Double)] = []

        // Action items and decisions are always valuable
        items += analysis.actionItems.map { ($0, .actionItem, 0.5) }
        items += analysis.decisions.map { ($0, .decision, 0.5) }

        // Named entities (people, places, orgs) are valuable
        items += analysis.entities.map { ($0, .person, 0.7) }

        // Topics: store as a single consolidated fact, not individual memories
        if !analysis.topics.isEmpty {
            items.append(("Key topics: \(analysis.topics.joined(separator: ", "))", .topic, 0.5))
        }

        // Bullet points: only keep substantive ones (skip the "Key topics:" and "Participants/entities:" meta-bullets)
        let substantiveBullets = analysis.bulletPoints.filter { bullet in
            !bullet.hasPrefix("Key topics:") && !bullet.hasPrefix("Participants/entities mentioned:")
        }
        items += substantiveBullets.map { ($0, .fact, 0.5) }

        // Deduplicate: skip items whose content is contained in another item
        let deduped = deduplicate(items)

        let memories = deduped.map { content, type, confidence in
            let memory = Memory(content: content, type: type, confidence: confidence)
            memory.sourceSession = session
            return memory
        }

        memories.forEach { context.insert($0) }

        RecallLogger.analysis("Extracted \(memories.count) memories")
        return memories
    }

    private static func deduplicate(_ items: [(String, MemoryType, Double)]) -> [(String, MemoryType, Double)] {
        var result: [(String, MemoryType, Double)] = []
        let sortedByLength = items.sorted { $0.0.count > $1.0.count }

        for item in sortedByLength {
            let isDuplicate = result.contains { existing in
                existing.0.localizedCaseInsensitiveContains(item.0) && existing.0 != item.0
            }
            if !isDuplicate {
                result.append(item)
            }
        }

        return result
    }
}
