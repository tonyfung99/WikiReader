import Foundation

nonisolated struct ArticleContent: Equatable {
    var title: String
    var sourceURL: URL
    var markdownBody: String
}

/// Fetches a web page and reduces it to readable markdown. Dependency-free:
/// a focused set of regex passes rather than a full Readability port — good
/// enough to feed an LLM knowledge base.
nonisolated struct ArticleExtractor {
    var session: URLSession = .shared

    func fetch(_ url: URL) async throws -> ArticleContent {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; WikiReader/1.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClipError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw ClipError.badResponse(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ClipError.badResponse(http.statusCode) }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ClipError.noContent
        }

        let content = Self.parse(html: html, url: url)
        guard !content.markdownBody.isEmpty else { throw ClipError.noContent }
        return content
    }

    // MARK: - Parsing (pure, testable)

    static func parse(html: String, url: URL) -> ArticleContent {
        let title = extractTitle(html) ?? url.host ?? "Untitled"
        let region = mainRegion(html)
        let markdown = htmlToMarkdown(removeNoise(region))
        return ArticleContent(title: title, sourceURL: url, markdownBody: markdown)
    }

    private static let blockOptions: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

    private static func replace(_ string: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: blockOptions) else { return string }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    private static func extractTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: blockOptions) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
        let decoded = decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func mainRegion(_ html: String) -> String {
        for tag in ["article", "main", "body"] {
            if let element = firstElement(html, tag) { return element }
        }
        return html
    }

    private static func firstElement(_ html: String, _ tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)[^>]*>(.*?)</\(tag)>", options: blockOptions) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func removeNoise(_ html: String) -> String {
        var s = replace(html, "<!--.*?-->", "")
        for tag in ["script", "style", "noscript", "nav", "header", "footer", "aside", "form", "svg", "iframe"] {
            s = replace(s, "<\(tag)[^>]*>.*?</\(tag)>", "")
        }
        return s
    }

    private static func htmlToMarkdown(_ html: String) -> String {
        var s = html
        s = replace(s, "<a\\s+[^>]*?href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>", "[$2]($1)")
        s = replace(s, "<(strong|b)[^>]*>(.*?)</\\1>", "**$2**")
        s = replace(s, "<(em|i)[^>]*>(.*?)</\\1>", "*$2*")
        s = replace(s, "<code[^>]*>(.*?)</code>", "`$1`")
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            s = replace(s, "<h\(level)[^>]*>(.*?)</h\(level)>", "\n\n\(hashes) $1\n\n")
        }
        s = replace(s, "<li[^>]*>(.*?)</li>", "\n- $1")
        s = replace(s, "</p>", "\n\n")
        s = replace(s, "<br[^>]*>", "\n")
        s = replace(s, "</div>", "\n")
        s = stripTags(s)
        s = decodeEntities(s)
        return normalize(s)
    }

    private static func stripTags(_ string: String) -> String {
        replace(string, "<[^>]+>", "")
    }

    private static func decodeEntities(_ string: String) -> String {
        var out = string
        let named: [String: String] = [
            "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”",
        ]
        for (key, value) in named { out = out.replacingOccurrences(of: key, with: value) }
        out = decodeNumericEntities(out)
        return out.replacingOccurrences(of: "&amp;", with: "&")  // last, so &amp;lt; → &lt; → <
    }

    private static func decodeNumericEntities(_ string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#([xX]?)([0-9A-Fa-f]+);") else { return string }
        let ns = string as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let isHex = !ns.substring(with: match.range(at: 1)).isEmpty
            let digits = ns.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func normalize(_ string: String) -> String {
        var blanks = 0
        var lines: [String] = []
        for rawLine in string.components(separatedBy: "\n") {
            let line = rawLine
                .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                blanks += 1
                if blanks > 1 { continue }
            } else {
                blanks = 0
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
