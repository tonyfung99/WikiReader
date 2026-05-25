import Foundation

struct ComposedMarkdown {
    let title: String
    let text: String
}

/// Builds a markdown document (YAML frontmatter + body) from clipped content.
struct MarkdownComposer {
    func compose(tweet: TweetContent) -> ComposedMarkdown {
        let title = Self.title(for: tweet)
        let text = Self.frontmatter(tweet: tweet, title: title) + "\n" + Self.body(tweet: tweet)
        return ComposedMarkdown(title: title, text: text)
    }

    // MARK: - Title

    static func title(for tweet: TweetContent) -> String {
        let firstLine = tweet.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let author = tweet.authorName.isEmpty ? "@\(tweet.authorHandle)" : tweet.authorName

        if trimmed.isEmpty {
            return "Tweet by \(author)"
        }
        let snippet = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        return "\(author): \(snippet)"
    }

    // MARK: - Frontmatter

    static func frontmatter(tweet: TweetContent, title: String) -> String {
        let author = tweet.authorName.isEmpty
            ? "@\(tweet.authorHandle)"
            : "\(tweet.authorName) (@\(tweet.authorHandle))"
        let captured = Date.now.formatted(.iso8601)

        var lines = ["---"]
        lines.append("title: \(yaml(title))")
        lines.append("source_url: \(yaml(tweet.canonicalURL.absoluteString))")
        lines.append("author: \(yaml(author))")
        lines.append("captured_at: \(yaml(captured))")
        if let created = tweet.createdAt {
            lines.append("posted_at: \(yaml(created.formatted(.iso8601)))")
        }
        lines.append("type: tweet")
        lines.append("tags: [clipped, tweet]")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Body

    static func body(tweet: TweetContent) -> String {
        var sections: [String] = []

        let author = tweet.authorName.isEmpty ? "@\(tweet.authorHandle)" : tweet.authorName
        sections.append("# \(author) (@\(tweet.authorHandle))")

        if !tweet.text.isEmpty {
            sections.append(tweet.text)
        }

        if !tweet.photoURLs.isEmpty {
            let photos = tweet.photoURLs
                .map { "![photo](\($0.absoluteString))" }
                .joined(separator: "\n")
            sections.append(photos)
        }

        if !tweet.videoURLs.isEmpty {
            let videos = tweet.videoURLs
                .map { "- Video: \($0.absoluteString)" }
                .joined(separator: "\n")
            sections.append("**Video**\n\n\(videos)")
        }

        if let quoted = tweet.quoted {
            sections.append(quotedSection(quoted))
        }

        let links = tweet.linkedURLs.filter { $0.host != tweet.canonicalURL.host }
        if !links.isEmpty {
            let list = links.map { "- \($0.absoluteString)" }.joined(separator: "\n")
            sections.append("## Links in this post\n\n\(list)")
        }

        if let stats = statsLine(tweet) {
            sections.append(stats)
        }

        sections.append("[View original tweet](\(tweet.canonicalURL.absoluteString))")

        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func quotedSection(_ quoted: QuotedTweet) -> String {
        let header = "**Quoting \(quoted.authorName) (@\(quoted.authorHandle)):**"
        let quotedBody = quoted.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        var section = "\(header)\n\(quotedBody)"
        if let url = quoted.url {
            section += "\n>\n> \(url.absoluteString)"
        }
        return section
    }

    private static func statsLine(_ tweet: TweetContent) -> String? {
        var parts: [String] = []
        if let likes = tweet.likes { parts.append("\(likes) likes") }
        if let retweets = tweet.retweets { parts.append("\(retweets) retweets") }
        guard !parts.isEmpty else { return nil }
        return "_\(parts.joined(separator: " · "))_"
    }

    // MARK: - YAML

    /// Double-quotes and escapes a scalar so it is always valid YAML.
    static func yaml(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
