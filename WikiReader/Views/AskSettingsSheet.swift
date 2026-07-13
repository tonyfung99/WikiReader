import SwiftUI

/// Connection settings and history management for the Ask tab, presented
/// as a modal sheet — kept out of the main Ask flow.
struct AskSettingsSheet: View {
    @Environment(AskWikiSession.self) private var session: AskWikiSession?
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AskWikiSession.baseURLKey) private var baseURLString = AskWikiSession.defaultBaseURLString

    @State private var token = ""
    @State private var hasLoadedToken = false
    @State private var health: WikiDaemonHealthResponse?
    @State private var healthError: String?
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("http://host:7880", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        Label("Check Connection", systemImage: "waveform.path.ecg")
                    }
                    if let health {
                        HStack(spacing: 12) {
                            Label(health.vaultName ?? "Vault", systemImage: "checkmark.circle")
                            if let provider = health.provider {
                                Text(provider).foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(health.queryAvailable ? .green : .secondary)
                    }
                    if let healthError {
                        Text(healthError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Clear History", role: .destructive) {
                        showClearConfirmation = true
                    }
                }
            }
            .navigationTitle("Ask Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
        .confirmationDialog(
            "Clear all Ask history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                session?.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func checkHealth() async {
        healthError = nil
        health = nil
        var text = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            healthError = "Enter a valid daemon URL."
            return
        }
        if !text.contains("://") { text = "http://\(text)" }
        guard let baseURL = URL(string: text) else {
            healthError = "Enter a valid daemon URL."
            return
        }
        do {
            health = try await WikiDaemonClient(baseURL: baseURL, token: token).health()
        } catch {
            healthError = error.localizedDescription
        }
    }
}

#Preview {
    AskSettingsSheet()
        .environment(AskWikiSession(defaults: UserDefaults(suiteName: "asksettings-preview-\(UUID().uuidString)")!))
}
