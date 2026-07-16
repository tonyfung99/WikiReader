import UIKit

/// Builds a single Dynamic-Type-correct NSAttributedString from a run of
/// flowing-text blocks (heading/paragraph/quote/list), preserving inline
/// formatting and [[wikilinks]] via the existing MarkdownInline pipeline.
/// Uses UIFont.preferredFont(forTextStyle:) throughout — not a bridged
/// SwiftUI Font — because that's what actually responds live to the
/// system text-size setting (including Control Center's slider).
nonisolated enum MarkdownAttributedComposer {
    static func compose(_ blocks: [MarkdownBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(attributedString(for: block.kind))
        }
        return result
    }

    private static func attributedString(for kind: MarkdownBlock.Kind) -> NSAttributedString {
        switch kind {
        case .heading(let level, let text):
            return styled(text, style: headingStyle(level), bold: true, paragraphSpacing: 8)

        case .paragraph(let text):
            return styled(text, style: .body, paragraphSpacing: 14)

        case .quote(let lines):
            return styled(
                lines.joined(separator: "\n"), style: .body,
                color: .secondaryLabel, indent: 14, paragraphSpacing: 14
            )

        case .list(let items):
            let list = NSMutableAttributedString()
            for (index, item) in items.enumerated() {
                if index > 0 { list.append(NSAttributedString(string: "\n")) }
                list.append(listItemAttributedString(item))
            }
            return list

        case .frontmatter, .code, .callout, .image, .table, .rule:
            return NSAttributedString(string: "")
        }
    }

    private static func headingStyle(_ level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .title1
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }

    private static func styled(
        _ text: String,
        style: UIFont.TextStyle,
        bold: Bool = false,
        color: UIColor = .label,
        indent: CGFloat = 0,
        paragraphSpacing: CGFloat = 0
    ) -> NSAttributedString {
        let baseFont = bold
            ? boldVariant(of: UIFont.preferredFont(forTextStyle: style))
            : UIFont.preferredFont(forTextStyle: style)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = paragraphSpacing

        let attributed = NSMutableAttributedString(attributedString: inline(text, baseFont: baseFont))
        attributed.addAttribute(
            .foregroundColor, value: color,
            range: NSRange(location: 0, length: attributed.length)
        )
        attributed.addAttribute(
            .paragraphStyle, value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        return attributed
    }

    private static func listItemAttributedString(_ item: MarkdownListItem) -> NSAttributedString {
        let indent: CGFloat = 20 + CGFloat(item.depth) * 20
        let markerWidth: CGFloat = 20

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = indent - markerWidth
        paragraphStyle.headIndent = indent
        paragraphStyle.paragraphSpacing = 6
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
        paragraphStyle.defaultTabInterval = indent

        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString()
        result.append(marker(for: item))
        result.append(NSAttributedString(string: "\t"))
        result.append(inline(item.text, baseFont: baseFont))
        result.addAttribute(
            .paragraphStyle, value: paragraphStyle,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private static func marker(for item: MarkdownListItem) -> NSAttributedString {
        if let checked = item.checked {
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: checked ? "checkmark.square.fill" : "square")?
                .withTintColor(checked ? .tintColor : .secondaryLabel, renderingMode: .alwaysOriginal)
            return NSAttributedString(attachment: attachment)
        } else if let number = item.number {
            return NSAttributedString(string: "\(number).")
        } else {
            return NSAttributedString(string: "•")
        }
    }

    /// Walks MarkdownInline.attributed(_:)'s runs and translates its
    /// semantic markdown attributes (bold/italic/code emphasis, links)
    /// into concrete NSAttributedString attributes layered on `baseFont` —
    /// deliberately not a blind NSAttributedString(attributedString)
    /// bridge, since that does not reliably turn emphasis markers into an
    /// actual bold/italic UIFont.
    private static func inline(_ text: String, baseFont: UIFont) -> NSAttributedString {
        let source = MarkdownInline.attributed(text)
        let result = NSMutableAttributedString()

        for run in source.runs {
            let substring = String(source[run.range].characters)
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) {
                    font = boldVariant(of: font)
                }
                if intent.contains(.emphasized) {
                    font = italicVariant(of: font)
                }
                if intent.contains(.code) {
                    font = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: substring, attributes: attributes))
        }
        return result
    }

    private static func boldVariant(of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func italicVariant(of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
