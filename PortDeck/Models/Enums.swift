import Foundation

enum SessionContext: String, Codable, CaseIterable, Identifiable {
    case meeting, dnd, conversation, custom
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .dnd: return "D&D"
        default: return rawValue.capitalized
        }
    }
    var icon: String {
        switch self {
        case .meeting: return "person.3.fill"
        case .dnd: return "dice.fill"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .custom: return "tag.fill"
        }
    }
}

enum MemoryType: String, Codable, CaseIterable, Identifiable {
    case fact, decision, actionItem, person, topic
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .actionItem: return "Action Item"
        default: return rawValue.capitalized
        }
    }
    var icon: String {
        switch self {
        case .fact: return "lightbulb.fill"
        case .decision: return "checkmark.seal.fill"
        case .actionItem: return "checklist"
        case .person: return "person.fill"
        case .topic: return "tag.fill"
        }
    }
}
