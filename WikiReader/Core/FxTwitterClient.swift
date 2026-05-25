import Foundation

/// Fetches tweet content via the fxtwitter (FixTweet) JSON API, which exposes
/// tweet text/media without authentication.
struct FxTwitterClient {
    var session: URLSession = .shared
    var host = "api.fxtwitter.com"

    func fetchTweet(_ ref: TweetReference) async throws -> TweetContent {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/\(ref.screenName)/status/\(ref.statusID)"
        guard let url = comps.url else { throw ClipError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("WikiReader/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15  // share extension has a tight time budget

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

        let decoded = try JSONDecoder().decode(FxTwitterResponse.self, from: data)
        guard let tweet = decoded.tweet else { throw ClipError.noContent }
        return Self.makeContent(from: tweet, requestURL: url)
    }

    static func makeContent(from tweet: FxTweet, requestURL: URL) -> TweetContent {
        let canonical = tweet.url.flatMap(URL.init(string:)) ?? requestURL
        let created = tweet.createdTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }

        let quoted = tweet.quote.map {
            QuotedTweet(
                authorName: $0.author?.name ?? "",
                authorHandle: $0.author?.screenName ?? "",
                text: $0.text ?? "",
                url: $0.url.flatMap(URL.init(string:))
            )
        }

        return TweetContent(
            canonicalURL: canonical,
            authorName: tweet.author?.name ?? "",
            authorHandle: tweet.author?.screenName ?? "",
            text: tweet.text ?? "",
            createdAt: created,
            createdAtRaw: tweet.createdAt,
            photoURLs: (tweet.media?.photos ?? []).compactMap { $0.url.flatMap(URL.init(string:)) },
            videoURLs: (tweet.media?.videos ?? []).compactMap { $0.url.flatMap(URL.init(string:)) },
            quoted: quoted,
            likes: tweet.likes,
            retweets: tweet.retweets
        )
    }
}

// MARK: - Wire format

struct FxTwitterResponse: Decodable {
    let code: Int
    let message: String
    let tweet: FxTweet?
}

struct FxTweet: Decodable {
    let url: String?
    let text: String?
    let createdAt: String?
    let createdTimestamp: Int?
    let author: FxAuthor?
    let media: FxMedia?
    let quote: FxQuote?
    let likes: Int?
    let retweets: Int?

    enum CodingKeys: String, CodingKey {
        case url, text, author, media, quote, likes, retweets
        case createdAt = "created_at"
        case createdTimestamp = "created_timestamp"
    }
}

struct FxAuthor: Decodable {
    let name: String?
    let screenName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case screenName = "screen_name"
    }
}

struct FxMedia: Decodable {
    let photos: [FxPhoto]?
    let videos: [FxVideo]?
}

struct FxPhoto: Decodable { let url: String? }
struct FxVideo: Decodable { let url: String? }

/// Quoted tweet — modeled non-recursively (we don't follow quotes of quotes).
struct FxQuote: Decodable {
    let url: String?
    let text: String?
    let author: FxAuthor?
}
