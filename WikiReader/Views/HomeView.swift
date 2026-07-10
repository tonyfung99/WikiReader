import SwiftUI

/// Landing tab: recently modified notes, the daemon-maintained wiki index,
/// and recent daemon activity parsed from wiki/log.md.
struct HomeView: View {
    let root: URL

    @Environment(VaultIndex.self) private var index: VaultIndex?

    @State private var recents: [RecentNote] = []
    @State private var logEntries: [WikiLogEntry] = []
    @State private var indexFile: VaultFile?
    @State private var didLoad = false

    var body: some View {
        List {
            if let indexFile {
                Section {
                    NavigationLink {
                        MarkdownFileView(file: indexFile, root: root)
                    } label: {
                        Label("Wiki Index", systemImage: "books.vertical")
                    }
                }
            }

            if !recents.isEmpty {
                Section("Recent notes") {
                    ForEach(recents) { note in
                        NavigationLink {
                            MarkdownFileView(file: note.file, root: root)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.file.displayName)
                                Text(note.modified.formatted(.relative(presentation: .named)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !logEntries.isEmpty {
                Section("Wiki activity") {
                    ForEach(logEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.operation)
                                    .font(.footnote.smallCaps().weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.date)
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.summary)
                        }
                    }
                }
            }

            if didLoad && indexFile == nil && recents.isEmpty && logEntries.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "house",
                    description: Text("Clip some notes and they'll show up here.")
                )
            }
        }
        .navigationTitle("Home")
        .refreshable {
            index?.rebuild()
            await load()
        }
        .task {
            guard !didLoad else { return }
            await load()
        }
    }

    private func load() async {
        let url = root
        let loaded = await Task.detached(priority: .userInitiated) { () -> ([RecentNote], [WikiLogEntry], VaultFile?) in
            let recents = RecentNotes.scan(root: url)
            let logText = try? String(
                contentsOf: url.appendingPathComponent("wiki/log.md"), encoding: .utf8)
            let entries = logText.map { WikiLog.recentEntries(in: $0) } ?? []
            let indexURL = url.appendingPathComponent("wiki/index.md")
            let indexFile = FileManager.default.fileExists(atPath: indexURL.path)
                ? VaultFile(url: indexURL, isDirectory: false)
                : nil
            return (recents, entries, indexFile)
        }.value
        recents = loaded.0
        logEntries = loaded.1
        indexFile = loaded.2
        didLoad = true
    }
}

#if DEBUG
private func previewHomeVault() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("wr-home-preview", isDirectory: true)
    let wiki = root.appendingPathComponent("wiki", isDirectory: true)
    try? FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
    try? "# Recent Note\nBody.".write(
        to: root.appendingPathComponent("Recent Note.md"), atomically: true, encoding: .utf8)
    try? "# Index\n- [[Recent Note]]".write(
        to: wiki.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    try? "## [2026-07-09] ingest | Added a sample source".write(
        to: wiki.appendingPathComponent("log.md"), atomically: true, encoding: .utf8)
    return root
}

#Preview {
    NavigationStack {
        HomeView(root: previewHomeVault())
    }
}
#endif
