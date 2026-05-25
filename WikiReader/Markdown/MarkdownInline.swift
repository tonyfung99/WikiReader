import Foundation

/// Converts inline markdown (bold/italic/code/links) plus Obsidian-style
/// `[[wiki-links]]` into an `AttributedString`. Wiki-links become links with a
/// custom scheme so taps can be intercepted.
nonisolated enum MarkdownInline {
    static let wikiLinkScheme = "wikilink"

    static func attributed(_ text: String) -> AttributedString {
        let processed = replaceWikiLinks(in: text)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: processed, options: options)) ?? AttributedString(text)
    }

    /// Rewrites `[[Target]]` / `[[Target|Alias]]` into `[Alias](wikilink:///Target)`.
    static func replaceWikiLinks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))

            let inner = ns.substring(with: match.range(at: 1))
            let parts = inner.components(separatedBy: "|")
            let target = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? inner
            let display = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            result += "[\(display)](\(wikiLinkScheme):///\(encoded))"

            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Decodes a wiki-link URL back to its target note name, or nil if the URL
    /// is an ordinary external link.
    static func wikiLinkTarget(from url: URL) -> String? {
        guard url.scheme == wikiLinkScheme else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return path.removingPercentEncoding ?? path
    }
}
