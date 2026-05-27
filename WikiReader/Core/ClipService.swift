import Foundation

struct ClipResult {
    let fileURL: URL
    let title: String
}

/// End-to-end clip pipeline shared by the share extension: classify the URL,
/// fetch its content, compose markdown, and write it into the vault.
struct ClipService {
    var twitter = FxTwitterClient()
    var articles = ArticleExtractor()
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
        case .article:
            let article = try await articles.fetch(url)
            return try save(composer.compose(article: article))
        case .video:
            return try save(composer.videoStub(for: url), subdirectory: "pending")
        }
    }

    private func save(_ markdown: ComposedMarkdown, subdirectory: String? = nil) throws -> ClipResult {
        let filename = Filename.make(title: markdown.title)
        let fileURL = try vault.withVault { root in
            let directory = subdirectory.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
            if subdirectory != nil {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return try writer.write(markdown.text, filename: filename, to: directory)
        }
        return ClipResult(fileURL: fileURL, title: markdown.title)
    }
}
