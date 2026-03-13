import Foundation
import Speech

struct TranscriptionResult {
    var text: String
    var segments: [SpeakerSegment]

    var formattedTranscript: String {
        guard !segments.isEmpty, segments.contains(where: { $0.speaker > 0 }) else {
            return text
        }
        return segments.map { segment in
            "Speaker \(segment.speaker): \(segment.text)"
        }.joined(separator: "\n\n")
    }
}

struct SpeakerSegment {
    var speaker: Int
    var text: String
    var timestamp: TimeInterval
}

enum TranscriptionService {
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(audioURL: URL) async -> TranscriptionResult? {
        guard let recognizer = SFSpeechRecognizer(),
              recognizer.isAvailable else {
            RecallLogger.error("Speech recognizer not available")
            return nil
        }

        RecallLogger.transcription("Starting transcription for: \(audioURL.lastPathComponent)")

        // Check if directory (multi-chunk) or single file
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: audioURL.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return await transcribeChunks(directory: audioURL, recognizer: recognizer)
        } else {
            return await transcribeSingleFile(url: audioURL, recognizer: recognizer)
        }
    }

    private static func transcribeChunks(directory: URL, recognizer: SFSpeechRecognizer) async -> TranscriptionResult? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "m4a" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return nil }

        var fullText = ""
        var allSegments: [SpeakerSegment] = []
        var timeOffset: TimeInterval = 0

        for file in files {
            if let result = await transcribeSingleFile(url: file, recognizer: recognizer) {
                if !fullText.isEmpty { fullText += " " }
                fullText += result.text

                let offsetSegments = result.segments.map { segment in
                    SpeakerSegment(speaker: segment.speaker, text: segment.text, timestamp: segment.timestamp + timeOffset)
                }
                allSegments.append(contentsOf: offsetSegments)

                // Estimate chunk duration from last segment timestamp
                if let lastSegment = result.segments.last {
                    timeOffset += lastSegment.timestamp + 5
                }
            }
        }

        RecallLogger.transcription("Completed transcription: \(fullText.count) characters")
        guard !fullText.isEmpty else { return nil }
        return TranscriptionResult(text: fullText, segments: allSegments)
    }

    private static func transcribeSingleFile(url: URL, recognizer: SFSpeechRecognizer) async -> TranscriptionResult? {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    RecallLogger.error("Transcription error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let result, result.isFinal else { return }

                let text = result.bestTranscription.formattedString
                let segments = detectSpeakerChanges(from: result.bestTranscription)

                continuation.resume(returning: TranscriptionResult(text: text, segments: segments))
            }
        }
    }

    /// Detect speaker changes using voice pitch analysis from transcription segments.
    /// Groups consecutive segments by estimated speaker based on pitch clustering.
    private static func detectSpeakerChanges(from transcription: SFTranscription) -> [SpeakerSegment] {
        let sfSegments = transcription.segments
        guard !sfSegments.isEmpty else { return [] }

        // If there's only one segment or very few, just return as single speaker
        guard sfSegments.count > 1 else {
            return [SpeakerSegment(speaker: 1, text: transcription.formattedString, timestamp: 0)]
        }

        // Use voiceAnalytics pitch to cluster speakers if available
        var pitches: [(segment: SFTranscriptionSegment, pitch: Double)] = []
        for segment in sfSegments {
            if let analytics = segment.voiceAnalytics,
               let pitchValue = analytics.pitch.acousticFeatureValuePerFrame.first {
                pitches.append((segment, Double(pitchValue)))
            }
        }

        // If no voice analytics available, return as single speaker
        guard pitches.count > sfSegments.count / 2 else {
            return [SpeakerSegment(speaker: 1, text: transcription.formattedString, timestamp: 0)]
        }

        // Simple 2-speaker clustering: split by median pitch
        let sortedPitches = pitches.map(\.pitch).sorted()
        let medianPitch = sortedPitches[sortedPitches.count / 2]

        // Build speaker segments by grouping consecutive same-speaker words
        var result: [SpeakerSegment] = []
        var currentSpeaker = 0
        var currentText = ""
        var currentTimestamp: TimeInterval = 0

        for item in pitches {
            let speaker = item.pitch >= medianPitch ? 1 : 2

            if speaker != currentSpeaker {
                if !currentText.isEmpty {
                    result.append(SpeakerSegment(speaker: currentSpeaker, text: currentText.trimmingCharacters(in: .whitespaces), timestamp: currentTimestamp))
                }
                currentSpeaker = speaker
                currentText = item.segment.substring
                currentTimestamp = item.segment.timestamp
            } else {
                currentText += " " + item.segment.substring
            }
        }

        if !currentText.isEmpty {
            result.append(SpeakerSegment(speaker: currentSpeaker, text: currentText.trimmingCharacters(in: .whitespaces), timestamp: currentTimestamp))
        }

        // If clustering produced only 1 speaker, reset to single speaker
        let uniqueSpeakers = Set(result.map(\.speaker))
        if uniqueSpeakers.count <= 1 {
            return [SpeakerSegment(speaker: 1, text: transcription.formattedString, timestamp: 0)]
        }

        RecallLogger.transcription("Detected \(uniqueSpeakers.count) speakers across \(result.count) segments")
        return result
    }
}
