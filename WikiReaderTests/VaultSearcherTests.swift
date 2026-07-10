import Foundation
import Testing
@testable import WikiReader

@MainActor
struct VaultSearcherTests {
    /// Builds a throwaway vault on disk and returns its root.
    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("searcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, contents) in files {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func titleMatchOutranksBodyMatch() throws {
        let root = try makeVault([
            "Swift Concurrency.md": "notes about actors",
            "Journal.md": "today I studied swift concurrency for hours swift swift",
        ])
        let results = VaultSearcher.build(root: root).search("swift")
        #expect(results.count == 2)
        #expect(results[0].title == "Swift Concurrency")
    }

    @Test func headingMatchOutranksBodyMatch() throws {
        let root = try makeVault([
            "A.md": "# Databases\nsome text",
            "B.md": "text mentioning databases once",
        ])
        let results = VaultSearcher.build(root: root).search("databases")
        #expect(results.first?.title == "A")
    }

    @Test func allTokensMustMatch() throws {
        let root = try makeVault([
            "Both.md": "alpha beta",
            "OnlyAlpha.md": "alpha gamma",
        ])
        let results = VaultSearcher.build(root: root).search("alpha beta")
        #expect(results.map(\.title) == ["Both"])
    }

    @Test func emptyQueryReturnsNothing() throws {
        let root = try makeVault(["A.md": "text"])
        #expect(VaultSearcher.build(root: root).search("   ").isEmpty)
    }

    @Test func searchIsCaseInsensitive() throws {
        let root = try makeVault(["Note.md": "Contains MixedCase Word"])
        #expect(VaultSearcher.build(root: root).search("mixedcase").count == 1)
    }

    @Test func snippetSurroundsMatchWithEllipses() {
        let text = String(repeating: "x", count: 200) + " needle " + String(repeating: "y", count: 200)
        let snippet = VaultSearcher.snippet(in: text, around: "needle")
        #expect(snippet.contains("needle"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.count < 200)
    }

    @Test func nonMarkdownFilesIgnored() throws {
        let root = try makeVault(["real.md": "findme", "skip.txt": "findme"])
        #expect(VaultSearcher.build(root: root).search("findme").count == 1)
    }

    @Test func subdirectoriesAreIndexed() throws {
        let root = try makeVault(["wiki/entities/Person.md": "findme deep"])
        #expect(VaultSearcher.build(root: root).search("findme").count == 1)
    }
}
