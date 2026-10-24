import Foundation
import Observation

@MainActor
@Observable
final class CaptureComposerModel {
    var text = DemoMode.isEnabled ? DemoData.captureText : ""
    var transcript = ""
    var usedDictation = false
    private(set) var isSubmitting = false
    private(set) var message: (String, InlineMessage.Kind)?

    func submit(
        to instance: PortOSInstance,
        destination: CaptureDestination,
        date: Date,
        api: PortOSAPIClient,
        credentials: any CredentialStore
    ) async {
        guard let baseURL = instance.baseURL, !isSubmitting else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        message = nil
        defer { isSubmitting = false }
        do {
            let password = try credentials.password(for: instance.localID)
            switch destination {
            case .brain:
                let response = try await api.invokeAction(
                    id: "brain_capture",
                    arguments: ["text": .string(trimmed)],
                    baseURL: baseURL,
                    password: password
                )
                guard accept(response, fallback: "Could not capture to Brain.") else { return }
                message = (response.result.summary ?? "Captured to Brain.", .success)
            case .dailyLog:
                let date = Self.dateString(date)
                if usedDictation {
                    let response = try await api.invokeAction(
                        id: "daily_log_append",
                        arguments: ["text": .string(trimmed), "date": .string(date)],
                        baseURL: baseURL,
                        password: password
                    )
                    guard accept(response, fallback: "Could not add to the daily log.") else { return }
                    message = (response.result.summary ?? "Added to the daily log.", .success)
                } else {
                    let response = try await api.appendDailyLog(
                        text: trimmed,
                        date: date,
                        source: "text",
                        baseURL: baseURL,
                        password: password
                    )
                    message = ("Added to the daily log for \(response.date).", .success)
                }
            }
            text = ""
            transcript = ""
            usedDictation = false
        } catch {
            message = (error.localizedDescription, .error)
        }
    }

    private func accept(_ response: PaletteActionResponse, fallback: String) -> Bool {
        guard response.ok, response.result.okFlag != false else {
            let summary = response.result.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            message = (summary.flatMap { $0.isEmpty ? nil : $0 } ?? fallback, .error)
            return false
        }
        return true
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
