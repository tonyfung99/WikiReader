import Foundation

/// A folder or markdown file inside the vault. Understands iCloud's
/// `.name.icloud` placeholder naming for not-yet-downloaded files.
nonisolated struct VaultFile: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }

    var isPlaceholder: Bool {
        url.lastPathComponent.hasSuffix(".icloud")
    }

    /// The user-facing name, with iCloud placeholder decoration stripped.
    var name: String {
        guard isPlaceholder else { return url.lastPathComponent }
        var trimmed = String(url.lastPathComponent.dropLast(".icloud".count))
        if trimmed.hasPrefix(".") { trimmed.removeFirst() }
        return trimmed
    }

    var isMarkdown: Bool {
        name.lowercased().hasSuffix(".md")
    }

    /// The on-disk URL to read, accounting for placeholder files that need
    /// downloading first.
    var displayName: String {
        isMarkdown ? String(name.dropLast(3)) : name
    }
}
