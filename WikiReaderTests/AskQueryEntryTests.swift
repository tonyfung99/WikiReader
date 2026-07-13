import Testing
import Foundation
@testable import WikiReader

@MainActor
struct AskQueryEntryTests {
    @Test func codableRoundTripsAllStatusCases() throws {
        let statuses: [AskQueryEntry.Status] = [.submitting, .running, .done, .failed, .cancelled]
        for status in statuses {
            let entry = AskQueryEntry(
                question: "What changed?",
                status: status,
                jobID: "qry_1",
                save: true,
                submittedAt: Date(timeIntervalSince1970: 1_700_000_000),
                answerMarkdown: "# Answer",
                citations: [WikiDaemonCitation(wikiLink: "Note", title: "Note")],
                saved: true,
                saveError: nil,
                provider: "codex",
                errorMessage: status == .failed ? "boom" : nil
            )
            let data = try JSONEncoder().encode(entry)
            let decoded = try JSONDecoder().decode(AskQueryEntry.self, from: data)
            #expect(decoded == entry)
        }
    }

    @Test func resolvedStatusesAreNeverStale() {
        let old = Date(timeIntervalSinceNow: -3600)
        for status: AskQueryEntry.Status in [.done, .failed, .cancelled] {
            let entry = AskQueryEntry(question: "q", status: status, save: false, submittedAt: old)
            #expect(!entry.isStale(now: Date()))
        }
    }

    @Test func unresolvedRecentEntryIsNotStale() {
        let entry = AskQueryEntry(question: "q", status: .running, save: false, submittedAt: Date())
        #expect(!entry.isStale(now: Date()))
    }

    @Test func unresolvedOldEntryIsStale() {
        let submitted = Date(timeIntervalSince1970: 0)
        let now = submitted.addingTimeInterval(AskQueryEntry.staleThreshold + 1)
        let entry = AskQueryEntry(question: "q", status: .running, save: false, submittedAt: submitted)
        #expect(entry.isStale(now: now))
    }

    @Test func unresolvedEntryExactlyAtThresholdIsNotStale() {
        let submitted = Date(timeIntervalSince1970: 0)
        let now = submitted.addingTimeInterval(AskQueryEntry.staleThreshold)
        let entry = AskQueryEntry(question: "q", status: .submitting, save: false, submittedAt: submitted)
        #expect(!entry.isStale(now: now))
    }
}
