import Testing
@testable import WikiReader

@MainActor
struct MarkdownParserTests {
    private func firstTable(_ blocks: [MarkdownBlock]) -> (headers: [String], alignments: [ColumnAlignment], rows: [[String]])? {
        for block in blocks {
            if case .table(let headers, let alignments, let rows) = block.kind {
                return (headers, alignments, rows)
            }
        }
        return nil
    }

    @Test func parsesTableWithAlignments() throws {
        let md = """
        | Name | Role | Score |
        | :--- | :---: | ---: |
        | Ada | Pioneer | 100 |
        | Alan | Theorist | 98 |
        """
        let table = try #require(firstTable(MarkdownParser.parse(md)))
        #expect(table.headers == ["Name", "Role", "Score"])
        #expect(table.alignments == [.leading, .center, .trailing])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["Ada", "Pioneer", "100"])
        #expect(table.rows[1] == ["Alan", "Theorist", "98"])
    }

    @Test func raggedRowPaddedToHeaderWidth() throws {
        let md = "| a | b | c |\n| - | - | - |\n| 1 | 2 |"
        let table = try #require(firstTable(MarkdownParser.parse(md)))
        #expect(table.rows[0] == ["1", "2", ""])
    }

    @Test func pipeLineWithoutDelimiterStaysParagraph() {
        let blocks = MarkdownParser.parse("a | b | c\nmore text")
        #expect(blocks.allSatisfy { if case .table = $0.kind { false } else { true } })
    }

    @Test func extractsFrontmatter() throws {
        let blocks = MarkdownParser.parse("---\ntitle: X\ntype: tweet\n---\n# H")
        guard case .frontmatter(let lines) = try #require(blocks.first).kind else {
            Issue.record("expected frontmatter first"); return
        }
        #expect(lines == ["title: X", "type: tweet"])
    }

    @Test func parsesListsCodeQuoteRule() {
        let md = """
        - a
        - b

        1. one
        2. two

        > quoted

        ```swift
        let x = 1
        ```

        ---
        """
        let kinds = MarkdownParser.parse(md).map(\.kind)
        #expect(kinds.contains { if case .bulletList(let i) = $0 { i == ["a", "b"] } else { false } })
        #expect(kinds.contains { if case .numberedList(let i) = $0 { i == ["one", "two"] } else { false } })
        #expect(kinds.contains { if case .quote = $0 { true } else { false } })
        #expect(kinds.contains { if case .code(let lang, _) = $0 { lang == "swift" } else { false } })
        #expect(kinds.contains { if case .rule = $0 { true } else { false } })
    }
}
