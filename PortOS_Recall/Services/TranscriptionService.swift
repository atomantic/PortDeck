import Foundation
import Speech

enum TranscriptionService {
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(audioURL: URL) async -> String? {
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

    private static func transcribeChunks(directory: URL, recognizer: SFSpeechRecognizer) async -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "m4a" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return nil }

        var fullTranscript = ""

        for file in files {
            if let chunk = await transcribeSingleFile(url: file, recognizer: recognizer) {
                if !fullTranscript.isEmpty { fullTranscript += " " }
                fullTranscript += chunk
            }
        }

        RecallLogger.transcription("Completed transcription: \(fullTranscript.count) characters")
        return fullTranscript.isEmpty ? nil : fullTranscript
    }

    private static func transcribeSingleFile(url: URL, recognizer: SFSpeechRecognizer) async -> String? {
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
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
