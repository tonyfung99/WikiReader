import Foundation

nonisolated struct WikiLogEntry: Identifiable, Equatable {
    let date: String
    let operation: String
    let summary: String
    let id: Int
}

/// Parses the daemon's append-only `wiki/log.md`. Entries look like
/// `## [2026-07-03] ingest | Added a source page`.
nonisolated enum WikiLog {
    static func recentEntries(in text: String, limit: Int = 5) -> [WikiLogEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: "^##\\s*\\[([^\\]]+)\\]\\s*([^|]+)\\|\\s*(.*)$"
        ) else {
            return []
        }

        var entries: [WikiLogEntry] = []
        for (offset, line) in text.components(separatedBy: "\n").enumerated() {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                continue
            }
            entries.append(WikiLogEntry(
                date: ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces),
                operation: ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces),
                summary: ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces),
                id: offset
            ))
        }
        return Array(entries.reversed().prefix(limit))
    }
}
