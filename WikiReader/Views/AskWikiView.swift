import SwiftUI

struct AskWikiView: View {
    let root: URL

    @AppStorage("wikiDaemon.baseURL") private var baseURLString = "https://wiki.artanis-tech.com"
    @AppStorage("wikiDaemon.saveAnswers") private var saveAnswers = true

    @State private var token = ""
    @State private var hasLoadedToken = false
    @State private var question = ""
    @State private var phase: QueryPhase = .idle
    @State private var health: WikiDaemonHealthResponse?
    @State private var selectedFile: VaultFile?
    @State private var queryTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                connectionSection
                questionSection
                statusSection
                answerSection
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Ask")
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
        .onAppear {
            guard !hasLoadedToken else { return }
            token = WikiDaemonTokenStore.load()
            hasLoadedToken = true
        }
        .onChange(of: token) { _, newValue in
            guard hasLoadedToken else { return }
            WikiDaemonTokenStore.save(newValue)
        }
        .onDisappear {
            queryTask?.cancel()
            queryTask = nil
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daemon", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await checkHealth() }
                } label: {
                    Label("Check", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            TextField("http://host:7880", text: $baseURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)

            SecureField("Bearer token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            if let health {
                HStack(spacing: 12) {
                    Label(health.vaultName ?? "Vault", systemImage: "checkmark.circle")
                    if let provider = health.provider {
                        Text(provider)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .foregroundStyle(health.queryAvailable ? .green : .secondary)
            }
        }
    }

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Question", systemImage: "questionmark.bubble")
                    .font(.headline)
                Spacer()
                Toggle("Save", isOn: $saveAnswers)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            TextEditor(text: $question)
                .frame(minHeight: 120)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                )

            Button {
                submit()
            } label: {
                Label(phase.isBusy ? "Querying" : "Ask Wiki", systemImage: phase.isBusy ? "hourglass" : "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .submitting:
            ProgressView("Starting query…")
        case .running(let jobID):
            HStack(spacing: 10) {
                ProgressView()
                Text(jobID)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            ContentUnavailableView(
                "Query failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var answerSection: some View {
        if case .done(let response) = phase {
            AnswerResultView(response: response, root: root, selectedFile: $selectedFile)
        }
    }

    private var canSubmit: Bool {
        !phase.isBusy &&
        configuredBaseURL != nil &&
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var configuredBaseURL: URL? {
        var text = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://\(text)"
        }
        return URL(string: text)
    }

    @MainActor
    private func submit() {
        guard let baseURL = configuredBaseURL else {
            phase = .failed("Enter a valid daemon URL.")
            return
        }

        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, !trimmedToken.isEmpty else { return }

        queryTask?.cancel()
        queryTask = Task {
            await runQuery(baseURL: baseURL, token: trimmedToken, question: trimmedQuestion)
        }
    }

    @MainActor
    private func runQuery(baseURL: URL, token: String, question: String) async {
        let client = WikiDaemonClient(baseURL: baseURL, token: token)

        do {
            phase = .submitting
            let start = try await client.startQuery(question: question, save: saveAnswers)
            phase = .running(jobID: start.jobID)

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let status = try await client.queryStatus(jobID: start.jobID)

                switch status.status {
                case .queued, .running:
                    phase = .running(jobID: start.jobID)
                case .done:
                    phase = .done(status)
                    return
                case .failed:
                    phase = .failed(status.error?.message ?? "The daemon reported a failed query.")
                    return
                }
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func checkHealth() async {
        guard let baseURL = configuredBaseURL else {
            phase = .failed("Enter a valid daemon URL.")
            return
        }

        do {
            health = try await WikiDaemonClient(baseURL: baseURL, token: token).health()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct AnswerResultView: View {
    let response: WikiDaemonQueryStatusResponse
    let root: URL
    @Binding var selectedFile: VaultFile?

    @State private var missingTarget: String?
    @State private var showMissingAlert = false

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(response.answerMarkdown ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(response.provider ?? "Answer", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if response.saved == true {
                    Label("Saved", systemImage: "tray.and.arrow.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownView(blocks: blocks)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    open(url)
                })

            if !response.citations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Related Notes", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    ForEach(response.citations) { citation in
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
        .alert("Note not found", isPresented: $showMissingAlert) {
            Button("OK", role: .cancel) { missingTarget = nil }
        } message: {
            Text(missingTarget ?? "")
        }
    }

    private func open(_ url: URL) -> OpenURLAction.Result {
        guard let target = MarkdownInline.wikiLinkTarget(from: url) else {
            return .systemAction
        }
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

private enum QueryPhase: Equatable {
    case idle
    case submitting
    case running(jobID: String)
    case done(WikiDaemonQueryStatusResponse)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .submitting, .running:
            return true
        case .idle, .done, .failed:
            return false
        }
    }
}

#Preview {
    NavigationStack {
        AskWikiView(root: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
}
