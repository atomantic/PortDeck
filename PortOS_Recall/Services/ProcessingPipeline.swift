import Foundation
import SwiftData

enum ProcessingPipeline {
    static func process(session: Session, context: ModelContext) async {
        RecallLogger.info("Starting processing pipeline for session: \(session.title)")

        // Step 1: Transcription
        if !session.isTranscribed, !session.audioPath.isEmpty {
            let audioURL = URL(fileURLWithPath: session.audioPath)
            if let result = await TranscriptionService.transcribe(audioURL: audioURL) {
                // Use speaker-labeled transcript when multiple speakers detected
                session.transcript = result.formattedTranscript
                session.isTranscribed = true

                // Apply audio retention policy
                if AppSettings.audioRetention == .deleteAfterTranscription {
                    deleteAudio(at: session.audioPath)
                    session.audioPath = ""
                }

                try? context.save()
                RecallLogger.success("Transcription complete for: \(session.title)")
            } else {
                RecallLogger.error("Transcription failed for: \(session.title)")
                return
            }
        }

        // Step 2: Analysis
        if !session.isAnalyzed, !session.transcript.isEmpty {
            let analysis = await AnalysisService.analyze(transcript: session.transcript)
            session.summary = analysis.summary
            session.decodedBulletPoints = analysis.bulletPoints
            session.decodedActionItems = analysis.actionItems

            if let json = try? JSONEncoder().encode(CodableAnalysis(from: analysis)),
               let jsonString = String(data: json, encoding: .utf8) {
                session.analysisJSON = jsonString
            }

            // Step 3: Memory extraction
            let _ = MemoryExtractor.extract(from: analysis, session: session, context: context)

            session.isAnalyzed = true
            try? context.save()
            RecallLogger.success("Analysis complete for: \(session.title)")
        }

        RecallLogger.success("Processing pipeline complete for: \(session.title)")
    }

    private static func deleteAudio(at path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        RecallLogger.info("Deleted audio per retention policy: \(url.lastPathComponent)")
    }
}

private struct CodableAnalysis: Codable {
    let summary: String
    let bulletPoints: [String]
    let actionItems: [String]
    let decisions: [String]
    let entities: [String]
    let topics: [String]

    init(from analysis: SessionAnalysis) {
        self.summary = analysis.summary
        self.bulletPoints = analysis.bulletPoints
        self.actionItems = analysis.actionItems
        self.decisions = analysis.decisions
        self.entities = analysis.entities
        self.topics = analysis.topics
    }
}
