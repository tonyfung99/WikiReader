import SwiftUI

/// Loads a markdown file's contents and renders it.
struct MarkdownFileView: View {
    let file: VaultFile

    @State private var blocks: [MarkdownBlock] = []
    @State private var loadError: String?
    @State private var isLoading = true

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
        .task { await load() }
        .environment(\.openURL, OpenURLAction { url in
            // Cross-note navigation isn't in v1; swallow wiki-link taps so they
            // don't try to open an unknown scheme externally.
            MarkdownInline.wikiLinkTarget(from: url) != nil ? .handled : .systemAction
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
