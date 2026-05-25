import Foundation

/// Normalized representation of a clipped tweet, independent of the
/// fxtwitter wire format.
struct TweetContent: Equatable {
    var canonicalURL: URL
    var authorName: String
    var authorHandle: String
    var text: String
    var createdAt: Date?
    var createdAtRaw: String?
    var photoURLs: [URL]
    var videoURLs: [URL]
    var quoted: QuotedTweet?
    var likes: Int?
    var retweets: Int?

    /// URLs found inside the tweet body — the "linked post" content.
    var linkedURLs: [URL] {
        TweetContent.extractURLs(from: text)
    }

    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url }
    }
}

struct QuotedTweet: Equatable {
    var authorName: String
    var authorHandle: String
    var text: String
    var url: URL?
}
