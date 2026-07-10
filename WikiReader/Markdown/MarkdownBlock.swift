import Foundation

/// A parsed top-level markdown block. Inline formatting inside each block is
/// rendered separately via `MarkdownInline`.
nonisolated struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case frontmatter(lines: [String])
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case list(items: [MarkdownListItem])
        case code(language: String?, code: String)
        case quote(lines: [String])
        case table(headers: [String], alignments: [ColumnAlignment], rows: [[String]])
        case rule
    }
}

nonisolated enum ColumnAlignment {
    case leading, center, trailing
}

nonisolated struct MarkdownListItem: Equatable {
    let text: String
    /// 0-based nesting level (2 spaces or 1 tab per level).
    let depth: Int
    /// 1-based number for ordered items, nil for bullets.
    let number: Int?
    /// nil unless the item is a `- [ ]` / `- [x]` task.
    let checked: Bool?
}
