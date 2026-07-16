import Foundation

/// One renderable unit of a parsed document: either a merged run of
/// flowing-text blocks (heading/paragraph/quote/list) rendered as one
/// continuous, drag-selectable text view, or a single structural block
/// (table/image/code/callout/frontmatter/rule) rendered exactly as before.
nonisolated enum MarkdownRun: Identifiable {
    case text(id: UUID, blocks: [MarkdownBlock])
    case structural(MarkdownBlock)

    var id: UUID {
        switch self {
        case .text(let id, _): id
        case .structural(let block): block.id
        }
    }
}

nonisolated enum MarkdownRunGrouper {
    /// Groups consecutive heading/paragraph/quote/list blocks into one
    /// `.text` run each; every other block kind becomes its own
    /// `.structural` run, breaking any run in progress.
    static func group(_ blocks: [MarkdownBlock]) -> [MarkdownRun] {
        var runs: [MarkdownRun] = []
        var pending: [MarkdownBlock] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            runs.append(.text(id: pending[0].id, blocks: pending))
            pending = []
        }

        for block in blocks {
            if isFlowingText(block.kind) {
                pending.append(block)
            } else {
                flushPending()
                runs.append(.structural(block))
            }
        }
        flushPending()
        return runs
    }

    private static func isFlowingText(_ kind: MarkdownBlock.Kind) -> Bool {
        switch kind {
        case .heading, .paragraph, .quote, .list: true
        case .frontmatter, .code, .callout, .image, .table, .rule: false
        }
    }
}
