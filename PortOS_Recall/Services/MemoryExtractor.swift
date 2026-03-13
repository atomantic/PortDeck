import Foundation
import SwiftData

enum MemoryExtractor {
    static func extract(from analysis: SessionAnalysis, session: Session, context: ModelContext) -> [Memory] {
        RecallLogger.analysis("Extracting memories from analysis")

        let items: [(String, MemoryType, Double)] =
            analysis.actionItems.map { ($0, .actionItem, 0.5) } +
            analysis.decisions.map { ($0, .decision, 0.5) } +
            analysis.entities.map { ($0, .person, 0.7) } +
            analysis.topics.map { ($0, .topic, 0.5) } +
            analysis.bulletPoints.map { ($0, .fact, 0.5) }

        let memories = items.map { content, type, confidence in
            let memory = Memory(content: content, type: type, confidence: confidence)
            memory.sourceSession = session
            return memory
        }

        memories.forEach { context.insert($0) }

        RecallLogger.analysis("Extracted \(memories.count) memories")
        return memories
    }
}
