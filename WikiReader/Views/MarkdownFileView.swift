import SwiftUI

/// Loads a markdown file's contents and renders it.
struct MarkdownFileView: View {
    let file: VaultFile
    let root: URL?

    @Environment(VaultIndex.self) private var index: VaultIndex?

    @State private var blocks: [MarkdownBlock] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var linkedFile: VaultFile?

    /// Titles of notes that link to this one, from the shared graph.
    private var backlinks: [String] {
        guard root != nil, let graph = index?.graph else { return [] }
        let name = fold(file.displayName)
        return Set(graph.edges.filter { fold($0.target) == name }.map(\.source)).sorted()
    }

    private func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    init(file: VaultFile, root: URL? = nil) {
        self.file = file
        self.root = root
    }

    var body: some View {
        ScrollView {
            Group {
                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if let loadError {
                    ContentUnavailableView(
                        "Couldn't open note",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        MarkdownView(blocks: blocks, baseDirectory: file.url.deletingLastPathComponent())
                        if !backlinks.isEmpty {
                            BacklinksView(names: backlinks) { name in
                                openBacklink(name)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(file.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $linkedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
        .task {
            index?.ensureBuilt()
            await load()
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let target = MarkdownInline.wikiLinkTarget(from: url) else {
                return .systemAction
            }
            if let root, let file = WikiLinkResolver.resolve(target, in: root) {
                linkedFile = file
            }
            return .handled
        })
    }

    private func openBacklink(_ name: String) {
        guard let root, let target = WikiLinkResolver.resolve(name, in: root) else { return }
        linkedFile = target
    }

    private func load() async {
        let target = file
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[MarkdownBlock], Error> in
            do {
                let text = try VaultBrowser.readContents(of: target)
                return .success(MarkdownParser.parse(text))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let parsed): blocks = parsed
        case .failure(let error): loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private struct BacklinksView: View {
    let names: [String]
    var onOpen: (String) -> Void

    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(names, id: \.self) { name in
                    Button {
                        onOpen(name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.up.left")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Linked from (\(names.count))", systemImage: "arrow.turn.up.left")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
private func previewMarkdownFile() -> VaultFile {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("wr-preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("Sample Note.md")
    try? """
    # Sample Note

    Hello from a **preview** — no real vault needed, just a temp file. \
    Here's an Obsidian [[Linked Note]] and a [web link](https://apple.com).
    """.write(to: url, atomically: true, encoding: .utf8)
    return VaultFile(url: url, isDirectory: false)
}

#Preview {
    NavigationStack {
        MarkdownFileView(file: previewMarkdownFile())
    }
}
#endif
