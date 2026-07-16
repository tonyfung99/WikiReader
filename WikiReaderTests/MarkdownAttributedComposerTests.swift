import Testing
import UIKit
@testable import WikiReader

@MainActor
struct MarkdownAttributedComposerTests {
    @Test func headingUsesBoldPreferredFont() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .heading(level: 1, text: "Title"))
        ])
        #expect(result.string == "Title")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test func paragraphUsesBodyFont() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .paragraph(text: "Hello"))
        ])
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let expected = UIFont.preferredFont(forTextStyle: .body)
        #expect(font?.pointSize == expected.pointSize)
    }

    @Test func wikilinkProducesLinkAttribute() throws {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .paragraph(text: "see [[Some Note]]"))
        ])
        var foundLink: URL?
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let url = value as? URL { foundLink = url }
        }
        let link = try #require(foundLink)
        #expect(link.scheme == "wikilink")
        #expect(MarkdownInline.wikiLinkTarget(from: link) == "Some Note")
    }

    @Test func bulletListItemHasMarkerPrefix() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .list(items: [
                MarkdownListItem(text: "first", depth: 0, number: nil, checked: nil)
            ]))
        ])
        #expect(result.string.hasPrefix("•"))
        #expect(result.string.contains("first"))
    }

    @Test func orderedListItemHasNumberPrefix() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .list(items: [
                MarkdownListItem(text: "step", depth: 0, number: 1, checked: nil)
            ]))
        ])
        #expect(result.string.hasPrefix("1."))
    }

    @Test func nestedListItemIndentsMoreThanTopLevel() throws {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .list(items: [
                MarkdownListItem(text: "top", depth: 0, number: nil, checked: nil),
                MarkdownListItem(text: "nested", depth: 1, number: nil, checked: nil),
            ]))
        ])
        let topStyle = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let nestedRange = try #require(result.string.range(of: "nested"))
        let nestedIndex = result.string.distance(from: result.string.startIndex, to: nestedRange.lowerBound)
        let nestedStyle = result.attribute(.paragraphStyle, at: nestedIndex, effectiveRange: nil) as? NSParagraphStyle
        #expect((nestedStyle?.headIndent ?? 0) > (topStyle?.headIndent ?? 0))
    }

    @Test func multipleBlocksAreSeparatedByNewline() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .paragraph(text: "First")),
            MarkdownBlock(kind: .paragraph(text: "Second")),
        ])
        #expect(result.string == "First\nSecond")
    }
}
