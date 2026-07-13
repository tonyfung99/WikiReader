import Foundation
import Observation

/// Owns Ask-wiki query state and its lifecycle — submission, polling,
/// resumption, cancellation — independent of any view's appear/disappear.
/// Created once in MainTabs and shared via the environment, so switching
/// tabs (or backgrounding, or relaunching the app) never orphans an
/// in-flight query the way view-scoped @State used to.
@MainActor
@Observable
final class AskWikiSession {
    static let baseURLKey = "wikiDaemon.baseURL"
    static let defaultBaseURLString = "https://wiki.artanis-tech.com"

    private(set) var entries: [AskQueryEntry]

    private let defaults: UserDefaults
    // nonisolated(unsafe): every mutation happens through this class's
    // @MainActor-isolated methods; the only nonisolated access is in
    // `deinit`, which by construction has no concurrent access to race with.
    private nonisolated(unsafe) var pollTasks: [UUID: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.entries = AskHistoryStore.load(defaults: defaults)
        resumeUnresolvedEntries()
    }

    /// A poll `Task` keeps this instance alive for its whole run (any
    /// instance method call across suspension points must keep its receiver
    /// alive) — so if the owning view is torn down mid-query (e.g. a vault
    /// switch recreates MainTabs), this session would otherwise keep polling
    /// independently of the new session that replaces it, both racing to
    /// persist the same App Group history. Cancelling here closes that gap.
    deinit {
        for task in pollTasks.values { task.cancel() }
    }

    /// Resolves the configured daemon URL from the same
    /// `@AppStorage("wikiDaemon.baseURL")` key the settings sheet edits.
    var configuredBaseURL: URL? {
        var text = (UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURLString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://\(text)" }
        return URL(string: text)
    }

    func submit(question: String, save: Bool) {
        guard let baseURL = configuredBaseURL else {
            insert(AskQueryEntry(
                question: question, status: .failed, save: save, submittedAt: Date(),
                errorMessage: "Enter a valid daemon URL in Settings."
            ))
            return
        }
        let token = WikiDaemonTokenStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            insert(AskQueryEntry(
                question: question, status: .failed, save: save, submittedAt: Date(),
                errorMessage: "Set a bearer token in Settings."
            ))
            return
        }

        let entry = AskQueryEntry(question: question, save: save, submittedAt: Date())
        insert(entry)
        startPolling(entryID: entry.id, baseURL: baseURL, token: token, resuming: false)
    }

    /// Call on init and whenever the app becomes active: resumes polling
    /// for any entry still submitting/running, or fails it fast (no wasted
    /// request) if it's past the daemon's own job-expiry window.
    func resumeUnresolvedEntries() {
        guard let baseURL = configuredBaseURL else { return }
        let token = WikiDaemonTokenStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let now = Date()
        for entry in entries where !entry.isResolved {
            guard pollTasks[entry.id] == nil else { continue }
            if entry.isStale(now: now) {
                update(entry.id) {
                    $0.status = .failed
                    $0.errorMessage = "Timed out — the daemon's job window expired."
                }
                continue
            }
            if entry.status == .submitting, entry.jobID == nil {
                update(entry.id) {
                    $0.status = .failed
                    $0.errorMessage = "Interrupted before the daemon confirmed the question."
                }
                continue
            }
            startPolling(entryID: entry.id, baseURL: baseURL, token: token, resuming: true)
        }
    }

    /// Stops local polling and marks the entry cancelled. No daemon cancel
    /// endpoint exists — the server job keeps running unattended; the app
    /// simply stops waiting for it.
    func cancel(_ entryID: UUID) {
        guard let existing = entry(entryID), !existing.isResolved else { return }
        pollTasks[entryID]?.cancel()
        pollTasks[entryID] = nil
        update(entryID) { $0.status = .cancelled }
    }

    func clearHistory() {
        for task in pollTasks.values { task.cancel() }
        pollTasks.removeAll()
        entries.removeAll()
        persist()
    }

    // MARK: - Private

    private func startPolling(entryID: UUID, baseURL: URL, token: String, resuming: Bool) {
        let client = WikiDaemonClient(baseURL: baseURL, token: token)
        pollTasks[entryID] = Task { [weak self] in
            await self?.run(entryID: entryID, client: client, resuming: resuming)
        }
    }

    private func run(entryID: UUID, client: WikiDaemonClient, resuming: Bool) async {
        do {
            let jobID: String
            if resuming {
                guard let existing = entry(entryID)?.jobID else { return }
                jobID = existing
            } else {
                guard let question = entry(entryID)?.question, let save = entry(entryID)?.save else { return }
                let start = try await client.startQuery(question: question, save: save)
                jobID = start.jobID
                update(entryID) {
                    $0.status = .running
                    $0.jobID = jobID
                }
            }

            while !Task.isCancelled {
                let status = try await client.queryStatus(jobID: jobID)
                switch status.status {
                case .queued, .running:
                    break
                case .done:
                    update(entryID) {
                        $0.status = .done
                        $0.answerMarkdown = status.answerMarkdown
                        $0.citations = status.citations
                        $0.saved = status.saved
                        $0.saveError = status.saveError
                        $0.provider = status.provider
                    }
                    pollTasks[entryID] = nil
                    return
                case .failed:
                    update(entryID) {
                        $0.status = .failed
                        $0.errorMessage = status.error?.message ?? "The daemon reported a failed query."
                    }
                    pollTasks[entryID] = nil
                    return
                }
                guard !Task.isCancelled else { return }
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        } catch is CancellationError {
            return
        } catch {
            // Foundation's URLSession async APIs often surface a Task
            // cancellation as URLError.cancelled rather than
            // CancellationError — guard against clobbering a status
            // `cancel()` already set (e.g. .cancelled) in that race.
            guard let current = entry(entryID), !current.isResolved else { return }
            update(entryID) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
            pollTasks[entryID] = nil
        }
    }

    private func entry(_ id: UUID) -> AskQueryEntry? {
        entries.first { $0.id == id }
    }

    private func insert(_ entry: AskQueryEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    private func update(_ id: UUID, _ mutate: (inout AskQueryEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
        persist()
    }

    private func persist() {
        AskHistoryStore.save(entries, defaults: defaults)
    }
}
