import Foundation

enum ClipKind: Equatable {
    case tweet(TweetReference)
    case video
    case article
}

struct TweetReference: Equatable {
    let screenName: String
    let statusID: String
}

enum URLClassifier {
    static func classify(_ url: URL) -> ClipKind {
        let host = normalizedHost(url)

        if isTwitterHost(host), let ref = tweetReference(from: url) {
            return .tweet(ref)
        }
        if isVideoHost(host) {
            return .video
        }
        return .article
    }

    static func normalizedHost(_ url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        for prefix in ["www.", "mobile.", "m."] where host.hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        return host
    }

    static func isTwitterHost(_ host: String) -> Bool {
        ["twitter.com", "x.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com"].contains(host)
    }

    static func isVideoHost(_ host: String) -> Bool {
        ["youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "tiktok.com"].contains(host)
    }

    /// Extracts the screen name + status id from a tweet URL.
    /// Handles `/user/status/123`, `/user/statuses/123`, and `/i/web/status/123`.
    static func tweetReference(from url: URL) -> TweetReference? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let statusIdx = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }),
              statusIdx + 1 < parts.count else { return nil }

        let id = String(parts[statusIdx + 1].prefix { $0.isNumber })
        guard !id.isEmpty else { return nil }

        // First path component is the handle; the /i/web/status form has none,
        // and fxtwitter accepts "i" as a stand-in.
        let handle = (statusIdx >= 1 && parts[0] != "i") ? parts[0] : "i"
        return TweetReference(screenName: handle, statusID: id)
    }
}
