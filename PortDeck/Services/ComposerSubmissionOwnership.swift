import Foundation

/// Shared request exclusion and draft ownership; used only on the main actor.
struct ComposerSubmissionOwnership {
    struct Submission {
        fileprivate let id: UUID
        fileprivate let draftRevision: UInt64
    }

    private var activeRequestID: UUID?
    private var draftRevision: UInt64 = 0

    var isSubmitting: Bool { activeRequestID != nil }

    mutating func draftDidChange() {
        draftRevision += 1
    }

    mutating func begin() -> Submission? {
        guard !isSubmitting else { return nil }
        let submission = Submission(id: UUID(), draftRevision: draftRevision)
        activeRequestID = submission.id
        return submission
    }

    func ownsRequest(_ submission: Submission) -> Bool {
        activeRequestID == submission.id
    }

    func ownsDraft(_ submission: Submission) -> Bool {
        ownsRequest(submission) && draftRevision == submission.draftRevision
    }

    mutating func finish(_ submission: Submission) {
        if ownsRequest(submission) { activeRequestID = nil }
    }
}
