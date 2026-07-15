import Foundation

/// One Ask-wiki history item: the question, its lifecycle status, and the
/// resolved answer once known. `.cancelled` and the fail-fast "timed out"
/// use of `.failed` are client-only states — the daemon's own
/// `WikiDaemonQueryStatus` has no equivalent, since there's no cancel
/// endpoint and no server-side notion of a client giving up.
nonisolated struct AskQueryEntry: Codable, Identifiable, Equatable {
    enum Status: String, Codable, Equatable {
        case submitting, running, done, failed, cancelled
    }

    let id: UUID
    var question: String
    var status: Status
    var jobID: String?
    var save: Bool
    var submittedAt: Date

    var answerMarkdown: String?
    var citations: [WikiDaemonCitation]
    var saved: Bool?
    var saveError: String?
    var provider: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        question: String,
        status: Status = .submitting,
        jobID: String? = nil,
        save: Bool,
        submittedAt: Date,
        answerMarkdown: String? = nil,
        citations: [WikiDaemonCitation] = [],
        saved: Bool? = nil,
        saveError: String? = nil,
        provider: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.question = question
        self.status = status
        self.jobID = jobID
        self.save = save
        self.submittedAt = submittedAt
        self.answerMarkdown = answerMarkdown
        self.citations = citations
        self.saved = saved
        self.saveError = saveError
        self.provider = provider
        self.errorMessage = errorMessage
    }

    var isResolved: Bool {
        switch status {
        case .done, .failed, .cancelled: true
        case .submitting, .running: false
        }
    }

    /// Kept in lockstep with the daemon's `JobStore(expiry_seconds: …)` — past
    /// this, a still-unresolved entry's job has certainly been evicted
    /// server-side, so there's no point polling for it. Raised alongside the
    /// daemon's longer agent timeout so a heavy query that legitimately runs
    /// for several minutes is never failed-fast on resume before it finishes.
    static let staleThreshold: TimeInterval = 900

    func isStale(now: Date) -> Bool {
        !isResolved && now.timeIntervalSince(submittedAt) > Self.staleThreshold
    }
}
