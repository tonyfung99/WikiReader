import SwiftUI

/// The Ask tab: a doc-list of past questions (newest first) with a
/// persistent input bar pinned at the bottom. Connection settings live
/// behind the toolbar gear icon, out of the main flow. Query state lives in
/// the environment-injected AskWikiSession, not here — so it survives tab
/// switches, backgrounding, and app relaunch.
struct AskWikiView: View {
    let root: URL
    @Binding var pendingQuestion: String?

    init(root: URL, pendingQuestion: Binding<String?> = .constant(nil)) {
        self.root = root
        self._pendingQuestion = pendingQuestion
    }

    @Environment(AskWikiSession.self) private var session: AskWikiSession?
    @AppStorage("wikiDaemon.saveAnswers") private var saveAnswer = true

    @State private var composeText = ""
    @State private var showSettings = false
    @FocusState private var isComposeFocused: Bool

    private var entries: [AskQueryEntry] {
        session?.entries ?? []
    }

    private var canSend: Bool {
        !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            historyList
            AskInputBar(text: $composeText, saveAnswer: $saveAnswer, canSend: canSend, isFocused: $isComposeFocused, onSend: send)
        }
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape", action: { showSettings = true })
            }
        }
        .sheet(isPresented: $showSettings) {
            AskSettingsSheet()
        }
        .onAppear { consumePendingQuestion() }
        .onChange(of: pendingQuestion) { _, _ in consumePendingQuestion() }
        .onDisappear { isComposeFocused = false }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No questions yet",
                        systemImage: "questionmark.bubble",
                        description: Text("Ask the wiki something below.")
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                ForEach(entries) { entry in
                    NavigationLink {
                        AskEntryDetailView(entryID: entry.id, root: root)
                    } label: {
                        AskEntryRow(entry: entry) {
                            session?.cancel(entry.id)
                        }
                    }
                    .id(entry.id)
                }
            }
            .listStyle(.plain)
            .onChange(of: entries.first?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation { proxy.scrollTo(newValue, anchor: .top) }
            }
        }
    }

    private func consumePendingQuestion() {
        guard let pending = pendingQuestion, !pending.isEmpty else { return }
        composeText = pending
        pendingQuestion = nil
    }

    private func send() {
        let trimmed = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isComposeFocused = false
        session?.submit(question: trimmed, save: saveAnswer)
        composeText = ""
    }
}

private struct AskEntryRow: View {
    let entry: AskQueryEntry
    var onCancel: () -> Void

    private var isRunning: Bool {
        entry.status == .submitting || entry.status == .running
    }

    private var statusText: String {
        switch entry.status {
        case .submitting: "Sending…"
        case .running: "Running…"
        case .cancelled: "Cancelled"
        case .failed: entry.errorMessage ?? "Failed"
        case .done: snippet
        }
    }

    private var snippet: String {
        guard let markdown = entry.answerMarkdown else { return "" }
        let flattened = markdown.replacingOccurrences(of: "\n", with: " ")
        return flattened.count > 120 ? String(flattened.prefix(120)) + "…" : flattened
    }

    private var statusColor: Color {
        switch entry.status {
        case .submitting, .running, .done: .secondary
        case .failed: .red
        case .cancelled: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.question)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            HStack {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Spacer()
                Text(entry.submittedAt.formatted(.relative(presentation: .named)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isRunning {
                Button("Cancel", role: .destructive, action: onCancel)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AskInputBar: View {
    @Binding var text: String
    @Binding var saveAnswer: Bool
    let canSend: Bool
    var isFocused: FocusState<Bool>.Binding
    var onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the wiki…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused(isFocused)
                Toggle(isOn: $saveAnswer) {
                    Image(systemName: "tray.and.arrow.down")
                }
                .toggleStyle(.button)
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

#if DEBUG
private func previewSession() -> AskWikiSession {
    let suite = UserDefaults(suiteName: "askwikiview-preview-\(UUID().uuidString)")!
    let now = Date()
    let entries = [
        AskQueryEntry(question: "What's next on the roadmap?", status: .running, jobID: "qry_preview_running", save: true, submittedAt: now),
        AskQueryEntry(
            question: "Summarize my notes on Swift actors",
            status: .done, jobID: "qry_preview_done", save: true, submittedAt: now.addingTimeInterval(-3600),
            answerMarkdown: "# Swift Actors\n\nActors serialize access to their mutable state, eliminating a whole class of data races.",
            saved: true, provider: "codex"
        ),
        AskQueryEntry(
            question: "How does the ingest pipeline dedupe sources?",
            status: .failed, save: false, submittedAt: now.addingTimeInterval(-7200),
            errorMessage: "The daemon reported a failed query."
        ),
        AskQueryEntry(question: "What changed in the graph view last week?", status: .cancelled, save: false, submittedAt: now.addingTimeInterval(-9000)),
    ]
    AskHistoryStore.save(entries, defaults: suite)
    return AskWikiSession(defaults: suite)
}
#endif

#Preview {
    NavigationStack {
        AskWikiView(root: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
    .environment(previewSession())
}
