import Foundation

enum AudioRetention: String, CaseIterable, Identifiable {
    case keepForever = "keepForever"
    case deleteAfterTranscription = "deleteAfterTranscription"
    case deleteAfter7Days = "deleteAfter7Days"
    case deleteAfter30Days = "deleteAfter30Days"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keepForever: return "Keep Forever"
        case .deleteAfterTranscription: return "Delete After Transcription"
        case .deleteAfter7Days: return "Delete After 7 Days"
        case .deleteAfter30Days: return "Delete After 30 Days"
        }
    }

    var description: String {
        switch self {
        case .keepForever: return "Audio files are kept permanently for re-transcription"
        case .deleteAfterTranscription: return "Audio is deleted once transcription completes"
        case .deleteAfter7Days: return "Audio is automatically deleted after 7 days"
        case .deleteAfter30Days: return "Audio is automatically deleted after 30 days"
        }
    }
}

enum AppSettings {
    private static let audioRetentionKey = "audioRetentionPolicy"

    static var audioRetention: AudioRetention {
        get {
            guard let raw = UserDefaults.standard.string(forKey: audioRetentionKey) else {
                return .keepForever
            }
            return AudioRetention(rawValue: raw) ?? .keepForever
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: audioRetentionKey)
        }
    }
}
