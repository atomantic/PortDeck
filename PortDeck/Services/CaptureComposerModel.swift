import Foundation
import Observation

@MainActor
@Observable
final class CaptureComposerModel {
    struct Selection: Equatable {
        let profileID: UUID?
        let destination: CaptureDestination
        let date: Date
    }

    struct AcceptedCapture {
        let profileID: UUID
        let profileName: String
        let destination: CaptureDestination
        let date: String
        let summary: String

        var attribution: String {
            let target = destination == .dailyLog ? "Daily Log for \(date)" : "Brain"
            return "\(profileName) · \(target)"
        }
    }

    var text = DemoMode.isEnabled ? DemoData.captureText : "" {
        didSet { if text != oldValue { draftRevision &+= 1 } }
    }
    var transcript = "" {
        didSet { if transcript != oldValue { draftRevision &+= 1 } }
    }
    var usedDictation = false {
        didSet { if usedDictation != oldValue { draftRevision &+= 1 } }
    }
    var selection: Selection? {
        didSet { if selection != oldValue { draftRevision &+= 1 } }
    }
    private(set) var acceptedCapture: AcceptedCapture?
    private var draftRevision: UInt64 = 0
    private var submitID: UUID?
    private(set) var isSubmitting = false
    private(set) var message: (String, InlineMessage.Kind)?

    // Dictation flows into the composer only. Clearing a submitted transcript must
    // never feed back through the controller and replace a newer typed draft.
    func receiveTranscript(_ value: String) {
        transcript = value
        text = value
    }

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
        selection = Selection(profileID: instance.localID, destination: destination, date: date)
        let requestID = UUID()
        submitID = requestID
        let revision = draftRevision
        let profileID = instance.localID
        let profileName = instance.displayName
        let submittedDate = Self.dateString(date)
        let submittedDictation = usedDictation
        isSubmitting = true
        message = nil
        acceptedCapture = nil
        defer {
            if submitID == requestID { isSubmitting = false }
        }
        do {
            let password = try credentials.password(for: profileID)
            guard let summary = try await deliverCapture(
                destination: destination,
                dictated: submittedDictation,
                text: trimmed,
                date: submittedDate,
                baseURL: baseURL,
                password: password,
                requestID: requestID,
                api: api
            ), submitID == requestID else { return }
            acceptedCapture = AcceptedCapture(
                profileID: profileID,
                profileName: profileName,
                destination: destination,
                date: submittedDate,
                summary: summary
            )
            message = (summary, .success)
            if draftRevision == revision {
                text = ""
                transcript = ""
                usedDictation = false
            }
        } catch {
            guard submitID == requestID else { return }
            message = (error.localizedDescription, .error)
        }
    }

    private func deliverCapture(
        destination: CaptureDestination,
        dictated: Bool,
        text: String,
        date: String,
        baseURL: URL,
        password: String?,
        requestID: UUID,
        api: PortOSAPIClient
    ) async throws -> String? {
        switch destination {
        case .brain:
            let response = try await api.invokeAction(
                id: "brain_capture",
                arguments: ["text": .string(text)],
                baseURL: baseURL,
                password: password
            )
            guard submitID == requestID,
                  accept(response, fallback: "Could not capture to Brain.") else { return nil }
            return response.result.summary ?? "Captured to Brain."
        case .dailyLog:
            if dictated {
                let response = try await api.invokeAction(
                    id: "daily_log_append",
                    arguments: ["text": .string(text), "date": .string(date)],
                    baseURL: baseURL,
                    password: password
                )
                guard submitID == requestID,
                      accept(response, fallback: "Could not add to the daily log.") else { return nil }
                return response.result.summary ?? "Added to the daily log."
            } else {
                let response = try await api.appendDailyLog(
                    text: text,
                    date: date,
                    source: "text",
                    baseURL: baseURL,
                    password: password
                )
                return "Added to the daily log for \(response.date)."
            }
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
