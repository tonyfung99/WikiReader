import Testing
import Foundation
@testable import WikiReader

@MainActor
struct ArticleExtractorTests {
    @Test func extractsTitleAndConvertsContent() {
        let html = """
        <html><head><title>My Article &amp; More</title></head>
        <body>
          <nav>NAVIGATION</nav>
          <article>
            <h1>Heading One</h1>
            <script>var x = 1;</script>
            <p>Hello <strong>world</strong> with a <a href="https://example.com">link</a>.</p>
            <ul><li>first</li><li>second</li></ul>
          </article>
          <footer>FOOTER</footer>
        </body></html>
        """
        let content = ArticleExtractor.parse(html: html, url: URL(string: "https://example.com/post")!)
        #expect(content.title == "My Article & More")
        #expect(content.markdownBody.contains("# Heading One"))
        #expect(content.markdownBody.contains("**world**"))
        #expect(content.markdownBody.contains("[link](https://example.com)"))
        #expect(content.markdownBody.contains("- first"))
        #expect(content.markdownBody.contains("- second"))
        #expect(!content.markdownBody.contains("var x"))       // script stripped
        #expect(!content.markdownBody.contains("NAVIGATION"))  // outside <article>
        #expect(!content.markdownBody.contains("FOOTER"))
    }

    @Test func fallsBackToHostWhenNoTitle() {
        let content = ArticleExtractor.parse(html: "<body><p>Body only</p></body>",
                                             url: URL(string: "https://news.example.org/x")!)
        #expect(content.title == "news.example.org")
        #expect(content.markdownBody.contains("Body only"))
    }

    @Test func decodesNumericEntities() {
        let content = ArticleExtractor.parse(html: "<body><p>caf&#233; &#x2764;</p></body>",
                                             url: URL(string: "https://e.com")!)
        #expect(content.markdownBody.contains("café"))
        #expect(content.markdownBody.contains("❤"))
    }
}

@MainActor
struct ArticleComposeTests {
    @Test func composeArticleHasFrontmatterAndSourceLink() {
        let article = ArticleContent(title: "T", sourceURL: URL(string: "https://e.com/a")!, markdownBody: "Body text")
        let md = MarkdownComposer().compose(article: article)
        #expect(md.text.contains("type: article"))
        #expect(md.text.contains("source_url: \"https://e.com/a\""))
        #expect(md.text.contains("# T"))
        #expect(md.text.contains("Body text"))
        #expect(md.text.contains("[Source](https://e.com/a)"))
    }
}

@MainActor
struct VideoStubTests {
    @Test func videoStubMarksPendingTranscription() {
        let md = MarkdownComposer().videoStub(for: URL(string: "https://youtu.be/abc")!)
        #expect(md.title.hasPrefix("Video:"))
        #expect(md.text.contains("type: video"))
        #expect(md.text.contains("status: pending_transcription"))
        #expect(md.text.contains("https://youtu.be/abc"))
    }
}
