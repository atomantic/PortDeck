import Foundation
import SwiftData

@Model
final class Memory {
    var content: String = ""
    var confidence: Double = 0.5
    var timestampReference: Double = 0
    var typeRaw: String = MemoryType.fact.rawValue
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify)
    var sourceSession: Session? = nil

    var type: MemoryType {
        get { MemoryType(rawValue: typeRaw) ?? .fact }
        set { typeRaw = newValue.rawValue }
    }

    init(
        content: String = "",
        type: MemoryType = .fact,
        confidence: Double = 0.5,
        timestampReference: Double = 0,
        createdAt: Date = .now
    ) {
        self.content = content
        self.typeRaw = type.rawValue
        self.confidence = confidence
        self.timestampReference = timestampReference
        self.createdAt = createdAt
    }
}
