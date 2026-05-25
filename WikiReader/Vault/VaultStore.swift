import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private(set) var hasVault: Bool
    private(set) var displayName: String?
    var errorMessage: String?

    private let bookmarkStore: VaultBookmarkStore
    private let access: VaultAccess
    private var accessedRoot: URL?

    init(bookmarkStore: VaultBookmarkStore = .shared) {
        self.bookmarkStore = bookmarkStore
        self.access = VaultAccess(store: bookmarkStore)
        self.hasVault = bookmarkStore.hasVault
        self.displayName = bookmarkStore.displayName()
    }

    /// Persists the user's chosen folder as a security-scoped bookmark.
    func setVault(url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(
                options: VaultAccess.creationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkStore.saveBookmark(data, displayName: url.lastPathComponent)
            hasVault = true
            displayName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save vault bookmark: \(error.localizedDescription)"
        }
    }

    func clearVault() {
        endBrowsing()
        bookmarkStore.clear()
        hasVault = false
        displayName = nil
    }

    /// Resolves the vault and opens a security-scoped session for browsing.
    /// Returns the root URL, or nil on failure (with `errorMessage` set).
    func beginBrowsing() -> URL? {
        endBrowsing()
        do {
            let root = try access.resolveVaultURL()
            guard root.startAccessingSecurityScopedResource() else {
                errorMessage = "Couldn't access the vault folder."
                return nil
            }
            accessedRoot = root
            return root
        } catch {
            errorMessage = error.localizedDescription
            if case VaultError.staleBookmark = error { clearVault() }
            return nil
        }
    }

    func endBrowsing() {
        accessedRoot?.stopAccessingSecurityScopedResource()
        accessedRoot = nil
    }
}
