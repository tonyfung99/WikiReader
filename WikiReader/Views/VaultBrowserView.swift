import SwiftUI

/// Lists folders and markdown files in a vault directory. Folders push another
/// browser; markdown files push the reader.
struct VaultBrowserView: View {
    let directory: URL
    let title: String

    @State private var files: [VaultFile] = []
    @State private var didLoad = false

    var body: some View {
        List {
            if files.isEmpty && didLoad {
                ContentUnavailableView(
                    "No notes here",
                    systemImage: "doc.text",
                    description: Text("No subfolders or .md files in this folder.")
                )
            }
            ForEach(files) { file in
                if file.isDirectory {
                    NavigationLink {
                        VaultBrowserView(directory: file.url, title: file.name)
                    } label: {
                        Label(file.name, systemImage: "folder")
                    }
                } else {
                    NavigationLink {
                        MarkdownFileView(file: file)
                    } label: {
                        Label(file.displayName, systemImage: file.isPlaceholder ? "arrow.down.circle" : "doc.text")
                    }
                }
            }
        }
        .navigationTitle(title)
        .refreshable { reload() }
        .task {
            guard !didLoad else { return }
            reload()
        }
    }

    private func reload() {
        files = VaultBrowser.list(directory: directory)
        didLoad = true
    }
}

#if DEBUG
private func previewVaultDirectory() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("wr-vault-preview", isDirectory: true)
    let sub = root.appendingPathComponent("Topics", isDirectory: true)
    try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try? "# Note A".write(to: root.appendingPathComponent("Note A.md"), atomically: true, encoding: .utf8)
    try? "# Note B".write(to: root.appendingPathComponent("Note B.md"), atomically: true, encoding: .utf8)
    return root
}

#Preview {
    NavigationStack {
        VaultBrowserView(directory: previewVaultDirectory(), title: "Vault")
    }
}
#endif
