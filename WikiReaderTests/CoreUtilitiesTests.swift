import Testing
import Foundation
@testable import WikiReader

@MainActor
struct FilenameTests {
    @Test func slugifyBasics() {
        #expect(Filename.slugify("Hello, World!") == "hello-world")
        #expect(Filename.slugify("  Multiple   spaces -- and?? punct ") == "multiple-spaces-and-punct")
        #expect(Filename.slugify("!!!") == "")
    }

    @Test func slugifyTruncatesAndTrims() {
        let slug = Filename.slugify(String(repeating: "a", count: 100), maxLength: 10)
        #expect(slug.count <= 10)
        #expect(!slug.hasSuffix("-"))
    }

    @Test func makeBuildsTimestampedSlug() {
        let name = Filename.make(title: "Hi There", date: Date(timeIntervalSince1970: 0))
        #expect(name.hasSuffix("-hi-there.md"))
    }

    @Test func makeEmptyTitleStillValid() {
        let name = Filename.make(title: "???", date: Date(timeIntervalSince1970: 0))
        #expect(name.hasSuffix(".md"))
        #expect(!name.contains("--"))
    }
}

@MainActor
struct VaultWriterTests {
    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writesContentLeavingNoTempFile() throws {
        let dir = try makeTempDir()
        let url = try VaultWriter().write("# Hi", filename: "note.md", to: dir)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Hi")
        let temps = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
        #expect(temps.isEmpty)
    }

    @Test func uniqueNamingAvoidsCollisions() throws {
        let dir = try makeTempDir()
        let writer = VaultWriter()
        let first = try writer.write("a", filename: "note.md", to: dir)
        let second = try writer.write("b", filename: "note.md", to: dir)
        #expect(first.lastPathComponent == "note.md")
        #expect(second.lastPathComponent == "note-1.md")
    }
}

@MainActor
struct WikiLinkParserTests {
    @Test func parsesTargetsAliasesAndStripsMd() {
        let links = WikiLinkParser.links(in: "see [[Foo]] and [[Bar|alias]] and [[Baz.md]]")
        #expect(links == ["Foo", "Bar", "Baz"])
    }

    @Test func noLinksReturnsEmpty() {
        #expect(WikiLinkParser.links(in: "nothing here").isEmpty)
    }
}

@MainActor
struct VaultGraphTests {
    @Test func topicSummariesCountIncomingOutgoingAndSortByConnectedness() {
        let graph = VaultGraph(
            nodes: [
                GraphNode(id: "Index", url: URL(fileURLWithPath: "/Index.md")),
                GraphNode(id: "Swift", url: URL(fileURLWithPath: "/Swift.md")),
                GraphNode(id: "Missing", url: nil),
                GraphNode(id: "Leaf", url: URL(fileURLWithPath: "/Leaf.md")),
            ],
            edges: [
                GraphEdge(source: "Index", target: "Swift"),
                GraphEdge(source: "Index", target: "Missing"),
                GraphEdge(source: "Swift", target: "Index"),
                GraphEdge(source: "Leaf", target: "Swift"),
            ]
        )

        let topics = graph.topics

        #expect(topics.map(\.id) == ["Swift", "Index", "Leaf", "Missing"])
        #expect(topics[0].incoming == ["Index", "Leaf"])
        #expect(topics[0].outgoing == ["Index"])
        #expect(topics[0].connectionCount == 2)
        #expect(topics[2].connectionCount == 1)
        #expect(!topics[3].exists)
    }

    @Test func connectedNodeIDsIncludesIncomingAndOutgoingNeighbors() {
        let graph = VaultGraph(
            nodes: [
                GraphNode(id: "A", url: URL(fileURLWithPath: "/A.md")),
                GraphNode(id: "B", url: URL(fileURLWithPath: "/B.md")),
                GraphNode(id: "C", url: URL(fileURLWithPath: "/C.md")),
                GraphNode(id: "D", url: URL(fileURLWithPath: "/D.md")),
            ],
            edges: [
                GraphEdge(source: "A", target: "B"),
                GraphEdge(source: "C", target: "A"),
                GraphEdge(source: "D", target: "B"),
            ]
        )

        #expect(graph.connectedNodeIDs(to: "A") == ["B", "C"])
        #expect(graph.connectedNodeIDs(to: "B") == ["A", "D"])
        #expect(graph.connectedNodeIDs(to: "Z").isEmpty)
    }

    @Test func graphViewportContentSizeCreatesScrollableCanvas() {
        let compact = CGSize(width: 390, height: 600)
        let content = GraphViewport.contentSize(nodeCount: 24, viewport: compact)

        #expect(content.width > compact.width)
        #expect(content.height > compact.height)
        #expect(content.width >= 720)
        #expect(content.height >= 560)
    }
}

@MainActor
struct MarkdownComposerTests {
    private func tweet(text: String, name: String = "Ann", handle: String = "a") -> TweetContent {
        TweetContent(
            canonicalURL: URL(string: "https://x.com/a/status/1")!,
            authorName: name, authorHandle: handle, text: text,
            createdAt: nil, createdAtRaw: nil,
            photoURLs: [], videoURLs: [], quoted: nil, likes: nil, retweets: nil
        )
    }

    @Test func yamlEscapesQuotesBackslashesAndNewlines() {
        #expect(MarkdownComposer.yaml(#"a "b" \c"#) == #""a \"b\" \\c""#)
        #expect(MarkdownComposer.yaml("line1\nline2") == "\"line1 line2\"")
    }

    @Test func titleTruncatesLongTextAndFallsBack() {
        let long = MarkdownComposer.title(for: tweet(text: String(repeating: "x", count: 100)))
        #expect(long.hasPrefix("Ann: "))
        #expect(long.contains("…"))

        let empty = MarkdownComposer.title(for: tweet(text: "", name: ""))
        #expect(empty == "Tweet by @a")
    }

    @Test func composeIncludesFrontmatterTextAndSourceLink() {
        let md = MarkdownComposer().compose(tweet: tweet(text: "hello world"))
        #expect(md.text.hasPrefix("---\n"))
        #expect(md.text.contains("type: tweet"))
        #expect(md.text.contains("hello world"))
        #expect(md.text.contains("[View original tweet](https://x.com/a/status/1)"))
    }
}
