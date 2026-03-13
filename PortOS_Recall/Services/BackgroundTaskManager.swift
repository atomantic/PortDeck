import Foundation
import BackgroundTasks
import SwiftData

enum BackgroundTaskManager {
    static let processingTaskIdentifier = "net.shadowpuppet.PortOSRecall.processing"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleProcessingTask(processingTask)
        }
        RecallLogger.info("Registered background processing task")
    }

    static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            RecallLogger.info("Scheduled background processing task")
        } catch {
            RecallLogger.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    private static func handleProcessingTask(_ task: BGProcessingTask) {
        RecallLogger.info("Background processing task started")

        let taskOperation = Task {
            guard let container = try? ModelContainer(for: Session.self, Memory.self, Participant.self) else {
                task.setTaskCompleted(success: false)
                return
            }

            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Session>(
                predicate: #Predicate<Session> { !$0.isAnalyzed }
            )

            guard let sessions = try? context.fetch(descriptor) else {
                task.setTaskCompleted(success: true)
                return
            }

            for session in sessions {
                await ProcessingPipeline.process(session: session, context: context)
            }

            task.setTaskCompleted(success: true)
            RecallLogger.success("Background processing completed for \(sessions.count) sessions")
        }

        task.expirationHandler = {
            taskOperation.cancel()
            RecallLogger.warning("Background processing task expired")
        }
    }
}
