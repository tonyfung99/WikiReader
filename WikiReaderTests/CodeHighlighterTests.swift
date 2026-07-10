import Testing
@testable import WikiReader

@MainActor
struct CodeHighlighterTests {
    @Test func classifiesKeywordsStringsNumbers() {
        let tokens = CodeHighlighter.tokenize("let x = \"hi\" + 42")
        #expect(tokens.contains { $0.text == "let" && $0.kind == .keyword })
        #expect(tokens.contains { $0.text == "\"hi\"" && $0.kind == .string })
        #expect(tokens.contains { $0.text == "42" && $0.kind == .number })
    }

    @Test func lineCommentRunsToEndOfLine() {
        let tokens = CodeHighlighter.tokenize("code // trailing comment\nnext")
        #expect(tokens.contains { $0.text == "// trailing comment" && $0.kind == .comment })
        #expect(tokens.contains { $0.text == "next" && $0.kind == .plain })
    }

    @Test func hashCommentDetected() {
        let tokens = CodeHighlighter.tokenize("# python comment")
        #expect(tokens.first?.kind == .comment)
    }

    @Test func identifiersContainingKeywordsStayPlain() {
        let tokens = CodeHighlighter.tokenize("letter iffy")
        #expect(tokens.allSatisfy { $0.kind != .keyword })
    }

    @Test func roundTripPreservesText() {
        let code = "func greet(name: String) -> String {\n    return \"hi \\(name)\" // 1\n}"
        let rebuilt = CodeHighlighter.tokenize(code).map(\.text).joined()
        #expect(rebuilt == code)
    }
}
