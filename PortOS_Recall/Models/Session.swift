import Foundation
import SwiftData

@Model
final class Session {
    var title: String = ""
    var contextRaw: String = SessionContext.conversation.rawValue
    var startTime: Date = Date.now
    var endTime: Date? = nil
    var audioPath: String = ""
    var transcript: String = ""
    var summary: String = ""
    var bulletPoints: String = "[]"
    var actionItems: String = "[]"
    var analysisJSON: String = ""
    var isAnalyzed: Bool = false
    var isTranscribed: Bool = false
    var durationSeconds: Double = 0

    @Relationship(deleteRule: .cascade)
    var memories: [Memory]? = nil

    @Relationship(deleteRule: .nullify, inverse: \Participant.sessions)
    var participants: [Participant]? = nil

    var context: SessionContext {
        get { SessionContext(rawValue: contextRaw) ?? .conversation }
        set { contextRaw = newValue.rawValue }
    }

    var decodedBulletPoints: [String] {
        get { Self.decodeStringArray(bulletPoints) }
        set { bulletPoints = Self.encodeStringArray(newValue) }
    }

    var decodedActionItems: [String] {
        get { Self.decodeStringArray(actionItems) }
        set { actionItems = Self.encodeStringArray(newValue) }
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled Session" : title
    }

    var formattedDuration: String {
        durationSeconds.formattedDuration
    }

    private static let jsonDecoder = JSONDecoder()
    private static let jsonEncoder = JSONEncoder()

    private static func decodeStringArray(_ raw: String) -> [String] {
        (try? jsonDecoder.decode([String].self, from: Data(raw.utf8))) ?? []
    }

    private static func encodeStringArray(_ array: [String]) -> String {
        (try? String(data: jsonEncoder.encode(array), encoding: .utf8)) ?? "[]"
    }

    init(
        title: String = "",
        context: SessionContext = .conversation,
        startTime: Date = .now,
        endTime: Date? = nil,
        audioPath: String = "",
        transcript: String = "",
        summary: String = "",
        bulletPoints: String = "[]",
        actionItems: String = "[]",
        analysisJSON: String = "",
        isAnalyzed: Bool = false,
        isTranscribed: Bool = false,
        durationSeconds: Double = 0
    ) {
        self.title = title
        self.contextRaw = context.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.audioPath = audioPath
        self.transcript = transcript
        self.summary = summary
        self.bulletPoints = bulletPoints
        self.actionItems = actionItems
        self.analysisJSON = analysisJSON
        self.isAnalyzed = isAnalyzed
        self.isTranscribed = isTranscribed
        self.durationSeconds = durationSeconds
    }
}
