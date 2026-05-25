import Testing
import Foundation
@testable import WikiReader

@MainActor
struct URLClassifierTests {
    @Test(arguments: [
        "https://x.com/jack/status/20",
        "https://twitter.com/jack/status/20",
        "https://www.twitter.com/jack/status/20",
        "https://mobile.twitter.com/jack/status/20",
        "https://fxtwitter.com/jack/status/20",
    ])
    func classifiesTweetHosts(_ urlString: String) throws {
        let kind = URLClassifier.classify(URL(string: urlString)!)
        guard case .tweet(let ref) = kind else {
            Issue.record("expected .tweet for \(urlString), got \(kind)")
            return
        }
        #expect(ref.screenName == "jack")
        #expect(ref.statusID == "20")
    }

    @Test func stripsQueryFromStatusID() {
        guard case .tweet(let ref) = URLClassifier.classify(URL(string: "https://x.com/foo/status/12345?s=20")!) else {
            Issue.record("expected .tweet"); return
        }
        #expect(ref.screenName == "foo")
        #expect(ref.statusID == "12345")
    }

    @Test func handlesIWebStatusForm() {
        guard case .tweet(let ref) = URLClassifier.classify(URL(string: "https://x.com/i/web/status/999")!) else {
            Issue.record("expected .tweet"); return
        }
        #expect(ref.screenName == "i")
        #expect(ref.statusID == "999")
    }

    @Test func handlesStatusesVariant() {
        guard case .tweet(let ref) = URLClassifier.classify(URL(string: "https://twitter.com/foo/statuses/77")!) else {
            Issue.record("expected .tweet"); return
        }
        #expect(ref.statusID == "77")
    }

    @Test(arguments: [
        "https://youtube.com/watch?v=abc",
        "https://youtu.be/abc",
        "https://vimeo.com/123",
        "https://www.tiktok.com/@a/video/1",
    ])
    func classifiesVideoHosts(_ urlString: String) {
        #expect(URLClassifier.classify(URL(string: urlString)!) == .video)
    }

    @Test func classifiesPlainArticle() {
        #expect(URLClassifier.classify(URL(string: "https://example.com/post/1")!) == .article)
    }

    @Test func twitterHostWithoutStatusIsArticle() {
        #expect(URLClassifier.classify(URL(string: "https://x.com/jack")!) == .article)
    }
}
