import Foundation

nonisolated enum VaultError: LocalizedError {
    case noVaultConfigured
    case bookmarkResolutionFailed(Error)
    case staleBookmark
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .noVaultConfigured:
            return "No vault folder selected. Open WikiReader and choose your vault."
        case .bookmarkResolutionFailed(let error):
            return "Could not resolve vault location: \(error.localizedDescription)"
        case .staleBookmark:
            return "Vault link is stale. Open WikiReader to re-select the vault folder."
        case .accessDenied:
            return "Permission to access the vault folder was denied."
        }
    }
}

/// Resolves the persisted bookmark to a security-scoped folder URL and runs
/// work inside a start/stop access pair.
///
/// Note: `.withSecurityScope` is a macOS-only bookmark option; on iOS the
/// document-picker URL is already security-scoped, so we pass no option there.
nonisolated struct VaultAccess {
    let store: VaultBookmarkStore

    init(store: VaultBookmarkStore = .shared) {
        self.store = store
    }

    static var creationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    func resolveVaultURL() throws -> URL {
        guard let data = store.loadBookmark() else { throw VaultError.noVaultConfigured }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: Self.resolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw VaultError.bookmarkResolutionFailed(error)
        }
        if isStale { throw VaultError.staleBookmark }
        return url
    }

    /// Runs `body` with security-scoped access to the vault root.
    @discardableResult
    func withVault<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolveVaultURL()
        guard url.startAccessingSecurityScopedResource() else { throw VaultError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}
