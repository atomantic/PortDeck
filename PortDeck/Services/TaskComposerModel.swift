import Foundation
import Observation

@MainActor
@Observable
final class TaskComposerModel {
    var description = DemoMode.isEnabled ? DemoData.taskDescription : ""
    var selectedTargetID: String? {
        didSet {
            if let selectedTargetID,
               let runner = assignableInstances.first(where: { $0.instanceID == selectedTargetID }) {
                retainedTargetName = runner.name
            } else if selectedTargetID == nil {
                retainedTargetName = nil
            }
        }
    }
    private(set) var assignableInstances: [AssignableInstance] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var lookupError: String?
    private(set) var submissionError: String?
    private(set) var createdTask: CreatedTask?

    private var loadedProfileID: UUID?
    private var lookupID = UUID()
    private var retainedTargetName: String?

    var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
            && !isSubmitting
            && loadedProfileID != nil
            && selectedTargetIsValidated
    }

    var selectedTargetName: String? {
        assignableInstances.first { $0.instanceID == selectedTargetID }?.name ?? retainedTargetName
    }

    func load(
        for instance: PortOSInstance,
        api: PortOSAPIClient,
        credentials: any CredentialStore
    ) async {
        let requestID = UUID()
        lookupID = requestID
        loadedProfileID = nil
        assignableInstances = []
        lookupError = nil
        submissionError = nil
        createdTask = nil
        isLoading = true
        defer {
            if lookupID == requestID { isLoading = false }
        }

        do {
            guard let baseURL = instance.baseURL else { throw PortOSAPIError.invalidResponse }
            let password = try credentials.password(for: instance.localID)
            let response = try await api.assignableInstances(baseURL: baseURL, password: password)
            try Task.checkCancellation()
            guard lookupID == requestID else { return }
            let valid = response.instances.filter {
                !$0.instanceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            assignableInstances = Self.uniqued(valid)
            if let selectedTargetID,
               !assignableInstances.contains(where: { $0.instanceID == selectedTargetID }) {
                self.selectedTargetID = nil
            }
            loadedProfileID = instance.localID
        } catch is CancellationError {
            return
        } catch {
            guard lookupID == requestID else { return }
            lookupError = error.localizedDescription
        }
    }

    func submit(
        to instance: PortOSInstance,
        api: PortOSAPIClient,
        credentials: any CredentialStore
    ) async {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, loadedProfileID == instance.localID else { return }
        guard selectedTargetIsValidated else {
            submissionError = "Reload the available runners before sending this pinned task."
            return
        }
        guard let baseURL = instance.baseURL else {
            submissionError = PortOSAPIError.invalidResponse.localizedDescription
            return
        }

        isSubmitting = true
        submissionError = nil
        createdTask = nil
        defer { isSubmitting = false }
        do {
            let password = try credentials.password(for: instance.localID)
            createdTask = try await api.createTask(
                description: trimmed,
                targetInstanceID: selectedTargetID,
                baseURL: baseURL,
                password: password
            )
            description = ""
        } catch {
            submissionError = error.localizedDescription
        }
    }

    private var selectedTargetIsValidated: Bool {
        guard let selectedTargetID else { return true }
        return assignableInstances.contains { $0.instanceID == selectedTargetID }
    }

    private static func uniqued(_ instances: [AssignableInstance]) -> [AssignableInstance] {
        var seen = Set<String>()
        return instances.filter { seen.insert($0.instanceID).inserted }
    }
}
