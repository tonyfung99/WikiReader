import Testing
@testable import WikiReader

@MainActor
struct MarkdownRunTests {
    private func blocks(_ kinds: [MarkdownBlock.Kind]) -> [MarkdownBlock] {
        kinds.map { MarkdownBlock(kind: $0) }
    }

    @Test func consecutiveFlowingBlocksMergeIntoOneRun() {
        let input = blocks([
            .heading(level: 1, text: "Title"),
            .paragraph(text: "Body"),
            .list(items: [MarkdownListItem(text: "item", depth: 0, number: nil, checked: nil)]),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 1)
        guard case .text(_, let runBlocks) = runs[0] else {
            Issue.record("expected a text run")
            return
        }
        #expect(runBlocks.count == 3)
    }

    @Test func tableBetweenParagraphsProducesThreeRuns() {
        let input = blocks([
            .paragraph(text: "Before"),
            .table(headers: ["A"], alignments: [.leading], rows: [["1"]]),
            .paragraph(text: "After"),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 3)
        guard case .text = runs[0] else { Issue.record("expected text run first"); return }
        guard case .structural(let middle) = runs[1] else { Issue.record("expected structural run second"); return }
        if case .table = middle.kind {} else { Issue.record("expected table block") }
        guard case .text = runs[2] else { Issue.record("expected text run third"); return }
    }

    @Test func calloutBetweenParagraphsProducesThreeRuns() {
        let input = blocks([
            .paragraph(text: "Before"),
            .callout(type: "note", title: "Note", lines: ["callout body"], foldable: false),
            .paragraph(text: "After"),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 3)
    }

    @Test func emptyBlockListProducesNoRuns() {
        #expect(MarkdownRunGrouper.group([]).isEmpty)
    }

    @Test func onlyStructuralBlocksProduceOneRunEach() {
        let input = blocks([
            .rule,
            .image(alt: "a", source: "b.png"),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 2)
    }
}
