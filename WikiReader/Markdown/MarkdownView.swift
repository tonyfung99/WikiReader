import SwiftUI

/// Renders parsed markdown blocks as SwiftUI views.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
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

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        listMarker(for: item)
                        Text(MarkdownInline.attributed(item.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 20)
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

        case .table(let headers, let alignments, let rows):
            MarkdownTableView(headers: headers, alignments: alignments, rows: rows)

        case .rule:
            Divider()
        }
    }

    @ViewBuilder
    private func listMarker(for item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.callout)
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
        } else if let number = item.number {
            Text("\(number).").monospacedDigit()
        } else {
            Text("•")
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

private struct MarkdownTableView: View {
    let headers: [String]
    let alignments: [ColumnAlignment]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { column in
                        Text(MarkdownInline.attributed(headers[column]))
                            .fontWeight(.semibold)
                            .gridColumnAlignment(horizontalAlignment(column))
                    }
                }
                Divider().gridCellColumns(max(headers.count, 1))
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(headers.indices, id: \.self) { column in
                            Text(MarkdownInline.attributed(cell(row, column)))
                        }
                    }
                    if row < rows.count - 1 {
                        Divider().gridCellColumns(max(headers.count, 1)).opacity(0.4)
                    }
                }
            }
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25))
            )
        }
    }

    private func cell(_ row: Int, _ column: Int) -> String {
        column < rows[row].count ? rows[row][column] : ""
    }

    private func horizontalAlignment(_ column: Int) -> HorizontalAlignment {
        let alignment = column < alignments.count ? alignments[column] : .leading
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
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
      - nested item
    - [ ] open task
    - [x] done task

    1. step one
    2. step two

    > a block quote

    | Feature | Status |
    | --- | :---: |
    | Tables | done |
    | Graph view | done |

    ```
    let answer = 42
    ```
    """
    ScrollView {
        MarkdownView(blocks: MarkdownParser.parse(sample))
            .padding()
    }
}
