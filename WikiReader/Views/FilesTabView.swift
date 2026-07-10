import SwiftUI

/// The Files tab root: the folder browser with vault-wide full-text search
/// layered on top. A non-empty search query replaces the browser with ranked
/// results; an "Ask the wiki" row escalates the query to the Ask tab.
struct FilesTabView: View {
    let root: URL
    let title: String
    var onAskWiki: (String) -> Void

    @Environment(VaultIndex.self) private var index: VaultIndex?
    @State private var searchText = ""

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                VaultBrowserView(directory: root, title: title, root: root)
            } else {
                SearchResultsList(
                    query: trimmedQuery,
                    root: root,
                    searcher: index?.searcher,
                    isBuilding: index?.isBuilding ?? false,
                    onAskWiki: onAskWiki
                )
                .navigationTitle(title)
            }
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .onChange(of: trimmedQuery) { _, newValue in
            if !newValue.isEmpty {
                index?.ensureBuilt()
            }
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SearchResultsList: View {
    let query: String
    let root: URL
    let searcher: VaultSearcher?
    let isBuilding: Bool
    var onAskWiki: (String) -> Void

    private var results: [SearchResult] {
        searcher?.search(query) ?? []
    }

    var body: some View {
        List {
            if searcher == nil || isBuilding {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Indexing vault…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(results) { result in
                    NavigationLink {
                        MarkdownFileView(file: result.file, root: root)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                            Text(result.snippet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                if results.isEmpty {
                    Text("No notes match \u{201C}\(query)\u{201D}.")
                        .foregroundStyle(.secondary)
                }
                if let skipped = searcher?.skippedCount, skipped > 0 {
                    Text("\(skipped) file\(skipped == 1 ? "" : "s") not yet indexed (downloading from iCloud).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    onAskWiki(query)
                } label: {
                    Label("Ask the wiki instead", systemImage: "questionmark.bubble")
                }
            } footer: {
                Text("Sends this as a question to the wiki daemon.")
            }
        }
    }
}

#if DEBUG
private func previewSearchVault() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("wr-search-preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try? "# Swift Actors\nNotes about actor isolation.".write(
        to: root.appendingPathComponent("Swift Actors.md"), atomically: true, encoding: .utf8)
    try? "Daily journal mentioning actors briefly.".write(
        to: root.appendingPathComponent("Journal.md"), atomically: true, encoding: .utf8)
    return root
}

#Preview {
    NavigationStack {
        FilesTabView(root: previewSearchVault(), title: "Vault") { _ in }
    }
    .environment(VaultIndex(root: previewSearchVault()))
}
#endif
