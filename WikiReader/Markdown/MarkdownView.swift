import SwiftUI

/// Renders parsed markdown blocks as SwiftUI views.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                view(for: block.kind)
            }
        }
    }

    @ViewBuilder
    private func view(for kind: MarkdownBlock.Kind) -> some View {
        switch kind {
        case .frontmatter(let lines):
            FrontmatterView(lines: lines)

        case .heading(let level, let text):
            Text(MarkdownInline.attributed(text))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(MarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(MarkdownInline.attributed(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                        Text(MarkdownInline.attributed(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .code(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .quote(let lines):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                Text(MarkdownInline.attributed(lines.joined(separator: "\n")))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}

private struct FrontmatterView: View {
    let lines: [String]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(lines.joined(separator: "\n"))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label("Metadata", systemImage: "list.bullet.rectangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    let sample = """
    ---
    title: "Sample Note"
    type: tweet
    ---
    # Heading One

    Body text with **bold**, *italic*, `inline code`, a [link](https://apple.com) \
    and an Obsidian [[Wiki Link]].

    ## A list

    - first item
    - second item

    1. step one
    2. step two

    > a block quote

    ```
    let answer = 42
    ```
    """
    ScrollView {
        MarkdownView(blocks: MarkdownParser.parse(sample))
            .padding()
    }
}
