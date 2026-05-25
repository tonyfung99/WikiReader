import Foundation

struct ClipResult {
    let fileURL: URL
    let title: String
}

/// End-to-end clip pipeline shared by the share extension: classify the URL,
/// fetch its content, compose markdown, and write it into the vault.
struct ClipService {
    var twitter = FxTwitterClient()
    var composer = MarkdownComposer()
    var writer = VaultWriter()
    var vault: VaultAccess

    init(vault: VaultAccess = VaultAccess()) {
        self.vault = vault
    }

    func clip(url: URL) async throws -> ClipResult {
        switch URLClassifier.classify(url) {
        case .tweet(let ref):
            let content = try await twitter.fetchTweet(ref)
            return try save(composer.compose(tweet: content))
        case .video:
            throw ClipError.unsupported("video clipping isn't built yet")
        case .article:
            throw ClipError.unsupported("article clipping isn't built yet")
        }
    }

    private func save(_ markdown: ComposedMarkdown) throws -> ClipResult {
        let filename = Filename.make(title: markdown.title)
        let fileURL = try vault.withVault { directory in
            try writer.write(markdown.text, filename: filename, to: directory)
        }
        return ClipResult(fileURL: fileURL, title: markdown.title)
    }
}
