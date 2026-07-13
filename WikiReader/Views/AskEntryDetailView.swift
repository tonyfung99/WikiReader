import SwiftUI

/// Reading view for one Ask history entry. Looks up the live entry by ID
/// from the environment-injected session on every render (not a captured
/// snapshot) so it updates automatically as polling resolves it.
struct AskEntryDetailView: View {
    let entryID: UUID
    let root: URL

    @Environment(AskWikiSession.self) private var session: AskWikiSession?

    @State private var selectedFile: VaultFile?
    @State private var missingTarget: String?
    @State private var showMissingAlert = false

    private var entry: AskQueryEntry? {
        session?.entries.first { $0.id == entryID }
    }

    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 18) {
                    Text(entry.question)
                        .font(.title3.weight(.semibold))
                    statusBody(for: entry)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "Entry removed",
                    systemImage: "trash",
                    description: Text("This question was cleared from history.")
                )
                .padding(.top, 40)
            }
        }
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
        .alert("Note not found", isPresented: $showMissingAlert) {
            Button("OK", role: .cancel) { missingTarget = nil }
        } message: {
            Text(missingTarget ?? "")
        }
    }

    @ViewBuilder
    private func statusBody(for entry: AskQueryEntry) -> some View {
        switch entry.status {
        case .submitting:
            ProgressView("Sending…")
        case .running:
            VStack(alignment: .leading, spacing: 12) {
                ProgressView("Running…")
                Button("Cancel", role: .destructive) { session?.cancel(entry.id) }
            }
        case .cancelled:
            ContentUnavailableView(
                "Cancelled",
                systemImage: "xmark.circle",
                description: Text("You stopped waiting for this answer.")
            )
        case .failed:
            ContentUnavailableView(
                "Query failed",
                systemImage: "exclamationmark.triangle",
                description: Text(entry.errorMessage ?? "Unknown error.")
            )
        case .done:
            doneBody(for: entry)
        }
    }

    @ViewBuilder
    private func doneBody(for entry: AskQueryEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(entry.provider ?? "Answer", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if entry.saved == true {
                    Label("Saved", systemImage: "tray.and.arrow.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownView(blocks: MarkdownParser.parse(entry.answerMarkdown ?? ""))
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in open(url) })

            if !entry.citations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Related Notes", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    ForEach(entry.citations) { citation in
                        Button {
                            openWikiLink(citation.wikiLink)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                    if citation.title != citation.wikiLink {
                                        Text(citation.wikiLink)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func open(_ url: URL) -> OpenURLAction.Result {
        guard let target = MarkdownInline.wikiLinkTarget(from: url) else { return .systemAction }
        openWikiLink(target)
        return .handled
    }

    private func openWikiLink(_ target: String) {
        if let file = WikiLinkResolver.resolve(target, in: root) {
            selectedFile = file
        } else {
            missingTarget = target
            showMissingAlert = true
        }
    }
}

#if DEBUG
private func previewSetup() -> (session: AskWikiSession, entryID: UUID) {
    let suite = UserDefaults(suiteName: "askentrydetail-preview-\(UUID().uuidString)")!
    let sample = AskQueryEntry(
        question: "What's the latest on Project X?",
        status: .done,
        jobID: "qry_preview",
        save: true,
        submittedAt: Date(),
        answerMarkdown: "# Project X\n\nHere's a summary with a [[Linked Note]].",
        citations: [WikiDaemonCitation(wikiLink: "Linked Note", title: "Linked Note")],
        saved: true,
        provider: "codex"
    )
    AskHistoryStore.save([sample], defaults: suite)
    return (AskWikiSession(defaults: suite), sample.id)
}
#endif

#Preview {
    let setup = previewSetup()
    return NavigationStack {
        AskEntryDetailView(entryID: setup.entryID, root: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
    .environment(setup.session)
}
