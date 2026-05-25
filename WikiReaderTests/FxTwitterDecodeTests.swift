import Testing
import Foundation
@testable import WikiReader

@MainActor
struct FxTwitterDecodeTests {
    @Test func decodesAndMapsFullTweet() throws {
        let json = """
        {"code":200,"message":"OK","tweet":{
          "url":"https://x.com/jack/status/20",
          "text":"just setting up my twttr",
          "created_at":"Tue Mar 21 20:50:14 +0000 2006",
          "created_timestamp":1142974214,
          "author":{"name":"jack","screen_name":"jack"},
          "likes":311,"retweets":125,
          "media":{"photos":[{"url":"https://pbs.twimg.com/a.jpg"}]}
        }}
        """
        let resp = try JSONDecoder().decode(FxTwitterResponse.self, from: Data(json.utf8))
        let content = FxTwitterClient.makeContent(from: try #require(resp.tweet),
                                                  requestURL: URL(string: "https://api.fxtwitter.com/jack/status/20")!)
        #expect(content.text == "just setting up my twttr")
        #expect(content.authorName == "jack")
        #expect(content.authorHandle == "jack")
        #expect(content.canonicalURL.absoluteString == "https://x.com/jack/status/20")
        #expect(content.likes == 311)
        #expect(content.retweets == 125)
        #expect(content.photoURLs.map(\.absoluteString) == ["https://pbs.twimg.com/a.jpg"])
        #expect(content.createdAt != nil)
    }

    @Test func missingOptionalFieldsGetDefaults() throws {
        let json = #"{"code":200,"message":"OK","tweet":{"text":"hi","author":{"screen_name":"a"}}}"#
        let resp = try JSONDecoder().decode(FxTwitterResponse.self, from: Data(json.utf8))
        let content = FxTwitterClient.makeContent(from: try #require(resp.tweet),
                                                  requestURL: URL(string: "https://api.fxtwitter.com/a/status/1")!)
        #expect(content.authorName == "")
        #expect(content.photoURLs.isEmpty)
        #expect(content.videoURLs.isEmpty)
        #expect(content.quoted == nil)
        // canonical falls back to the request URL when the tweet omits `url`
        #expect(content.canonicalURL.absoluteString == "https://api.fxtwitter.com/a/status/1")
    }

    @Test func flattensQuotedTweet() throws {
        let json = #"""
        {"code":200,"message":"OK","tweet":{"text":"top","author":{"name":"A","screen_name":"a"},
        "quote":{"url":"https://x.com/b/status/2","text":"quoted","author":{"name":"B","screen_name":"b"}}}}
        """#
        let resp = try JSONDecoder().decode(FxTwitterResponse.self, from: Data(json.utf8))
        let content = FxTwitterClient.makeContent(from: try #require(resp.tweet),
                                                  requestURL: URL(string: "https://api.fxtwitter.com/a/status/1")!)
        let quoted = try #require(content.quoted)
        #expect(quoted.authorHandle == "b")
        #expect(quoted.text == "quoted")
        #expect(quoted.url?.absoluteString == "https://x.com/b/status/2")
    }

    @Test func extractsLinkedURLsFromText() {
        let content = TweetContent(
            canonicalURL: URL(string: "https://x.com/a/status/1")!,
            authorName: "A", authorHandle: "a",
            text: "see https://example.com/x for more",
            createdAt: nil, createdAtRaw: nil,
            photoURLs: [], videoURLs: [], quoted: nil, likes: nil, retweets: nil
        )
        #expect(content.linkedURLs.contains { $0.absoluteString == "https://example.com/x" })
    }
}
