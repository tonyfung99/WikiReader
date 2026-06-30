import SwiftUI

/// Loads a markdown file's contents and renders it.
struct MarkdownFileView: View {
    let file: VaultFile
    let root: URL?

    @State private var blocks: [MarkdownBlock] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var linkedFile: VaultFile?

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
                    MarkdownView(blocks: blocks)
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
        .task { await load() }
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
