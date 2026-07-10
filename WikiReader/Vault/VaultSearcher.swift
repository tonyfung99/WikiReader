import Foundation

nonisolated struct SearchResult: Identifiable, Equatable {
    let file: VaultFile
    let title: String
    let snippet: String
    let score: Int

    var id: URL { file.url }
}

/// In-memory full-text index over the vault's markdown files. At current
/// vault scale (hundreds of notes, a few MB) a linear scan per query is
/// instant; revisit only past ~10k notes.
nonisolated struct VaultSearcher {
    struct Document: Equatable {
        let file: VaultFile
        let title: String
        let titleLower: String
        let headingsLower: String
        let bodyLower: String
        let rawBody: String
    }

    let documents: [Document]
    /// Files that couldn't be read (e.g. iCloud not downloaded yet).
    let skippedCount: Int

    static func build(root: URL) -> VaultSearcher {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return VaultSearcher(documents: [], skippedCount: 0)
        }

        var documents: [Document] = []
        var skipped = 0

        for case let url as URL in enumerator {
            if url.lastPathComponent.hasSuffix(".icloud") {
                skipped += 1
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                skipped += 1
                continue
            }
            let file = VaultFile(url: url, isDirectory: false)
            let headings = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
                .joined(separator: " ")
            documents.append(Document(
                file: file,
                title: file.displayName,
                titleLower: file.displayName.lowercased(),
                headingsLower: headings.lowercased(),
                bodyLower: text.lowercased(),
                rawBody: text
            ))
        }
        return VaultSearcher(documents: documents, skippedCount: skipped)
    }

    func search(_ query: String, limit: Int = 50) -> [SearchResult] {
        let tokens = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        var results: [SearchResult] = []
        for document in documents {
            var score = 0
            var matchedAll = true
            for token in tokens {
                var tokenScore = 0
                if document.titleLower.contains(token) { tokenScore += 100 }
                if document.headingsLower.contains(token) { tokenScore += 20 }
                if document.bodyLower.contains(token) { tokenScore += 1 }
                guard tokenScore > 0 else {
                    matchedAll = false
                    break
                }
                score += tokenScore
            }
            guard matchedAll else { continue }
            results.append(SearchResult(
                file: document.file,
                title: document.title,
                snippet: Self.snippet(in: document.rawBody, around: tokens[0]),
                score: score
            ))
        }

        return Array(
            results.sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    static func snippet(in text: String, around token: String, radius: Int = 60) -> String {
        guard let range = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(radius * 2)).replacingOccurrences(of: "\n", with: " ")
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}
