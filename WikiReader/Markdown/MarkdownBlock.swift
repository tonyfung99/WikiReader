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
        case bulletList(items: [String])
        case numberedList(items: [String])
        case code(language: String?, code: String)
        case quote(lines: [String])
        case rule
    }
}
