import Foundation
import os

struct RecallLogger {
    private static let logger = os.Logger(subsystem: "net.shadowpuppet.PortDeck", category: "general")

    static func recording(_ message: String) {
        logger.info("🎙️ \(message)")
    }

    static func transcription(_ message: String) {
        logger.info("📝 \(message)")
    }

    static func analysis(_ message: String) {
        logger.info("🧠 \(message)")
    }

    static func info(_ message: String) {
        logger.info("ℹ️ \(message)")
    }

    static func success(_ message: String) {
        logger.info("✅ \(message)")
    }

    static func warning(_ message: String) {
        logger.warning("⚠️ \(message)")
    }

    static func error(_ message: String) {
        logger.error("❌ \(message)")
    }
}
