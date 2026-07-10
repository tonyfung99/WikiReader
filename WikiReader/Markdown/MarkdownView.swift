import SwiftUI

/// Renders parsed markdown blocks as SwiftUI views.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var baseDirectory: URL? = nil

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

        case .callout(let type, let title, let lines, let foldable):
            CalloutView(type: type, title: title, lines: lines, foldable: foldable)

        case .image(let alt, let source):
            MarkdownImageView(alt: alt, source: source, baseDirectory: baseDirectory)

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

private struct MarkdownImageView: View {
    let alt: String
    let source: String
    let baseDirectory: URL?

    var body: some View {
        Group {
            if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            } else if let image = localImage {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }

    private var remoteURL: URL? {
        let lower = source.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return URL(string: source)
    }

    private var localImage: UIImage? {
        guard let baseDirectory else { return nil }
        let decoded = source.removingPercentEncoding ?? source
        let url = baseDirectory.appendingPathComponent(decoded)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private var placeholder: some View {
        Label(alt.isEmpty ? "Image unavailable" : alt, systemImage: "photo")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondary.opacity(0.08))
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

private struct CalloutView: View {
    let type: String
    let title: String
    let lines: [String]
    let foldable: Bool

    @State private var expanded = false

    private var icon: String {
        switch type {
        case "note": "pencil"
        case "info": "info.circle"
        case "tip", "hint": "lightbulb"
        case "warning", "caution": "exclamationmark.triangle"
        case "danger", "error", "bug": "xmark.octagon"
        case "quote", "cite": "quote.opening"
        case "success", "check", "done": "checkmark.circle"
        case "question", "help", "faq": "questionmark.circle"
        default: "pin"
        }
    }

    private var tint: Color {
        switch type {
        case "note", "info": .blue
        case "tip", "hint": .teal
        case "warning", "caution": .orange
        case "danger", "error", "bug": .red
        case "success", "check", "done": .green
        case "question", "help", "faq": .purple
        default: .gray
        }
    }

    var body: some View {
        Group {
            if foldable {
                DisclosureGroup(isExpanded: $expanded) {
                    bodyText.padding(.top, 4)
                } label: {
                    header
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    if !lines.isEmpty {
                        bodyText
                    }
                }
            }
        }
        .padding(12)
        .background(tint.opacity(0.1))
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var bodyText: some View {
        Text(MarkdownInline.attributed(lines.joined(separator: "\n")))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    > [!warning] Careful
    > Callouts render with icon and tint.

    > [!tip]- Folded tip
    > Hidden until expanded.

    | Feature | Status |
    | --- | :---: |
    | Tables | done |
    | Graph view | done |

    ![WikiReader](https://www.apple.com/favicon.ico)

    ```
    let answer = 42
    ```
    """
    ScrollView {
        MarkdownView(blocks: MarkdownParser.parse(sample))
            .padding()
    }
}
