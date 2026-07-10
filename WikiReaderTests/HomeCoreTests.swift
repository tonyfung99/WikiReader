import Foundation
import Testing
@testable import WikiReader

@MainActor
struct HomeCoreTests {
    @Test func recentNotesSortedNewestFirst() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("recents-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let old = root.appendingPathComponent("old.md")
        let new = root.appendingPathComponent("new.md")
        try "old".write(to: old, atomically: true, encoding: .utf8)
        try "new".write(to: new, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: new.path)

        let recents = RecentNotes.scan(root: root)
        #expect(recents.map { $0.file.displayName } == ["new", "old"])
    }

    @Test func recentNotesHonorsLimit() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("recents-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<5 {
            try "n".write(to: root.appendingPathComponent("note\(i).md"), atomically: true, encoding: .utf8)
        }
        #expect(RecentNotes.scan(root: root, limit: 3).count == 3)
    }

    @Test func parsesLogEntriesNewestFirst() {
        let log = """
        # Wiki Log

        ## [2026-07-01] ingest | Added swift actors source
        ## [2026-07-02] query | Answered question about actors
        ## [2026-07-03] lint | Fixed 2 dead links
        """
        let entries = WikiLog.recentEntries(in: log, limit: 2)
        #expect(entries.count == 2)
        #expect(entries[0].date == "2026-07-03")
        #expect(entries[0].operation == "lint")
        #expect(entries[0].summary == "Fixed 2 dead links")
        #expect(entries[1].date == "2026-07-02")
    }

    @Test func ignoresNonLogHeadings() {
        let log = "## Not a log line\n## [2026-07-01] ingest | real entry"
        let entries = WikiLog.recentEntries(in: log)
        #expect(entries.count == 1)
        #expect(entries[0].summary == "real entry")
    }
}
