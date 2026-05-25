import Foundation

/// Persists the security-scoped bookmark that points at the user's chosen
/// vault folder. Stored in the App Group so the host app (which creates it)
/// and the share extension (which consumes it) see the same value.
nonisolated struct VaultBookmarkStore {
    static let shared = VaultBookmarkStore()

    private let bookmarkKey = "vault.bookmark"
    private let displayNameKey = "vault.displayName"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    var hasVault: Bool { loadBookmark() != nil }

    func saveBookmark(_ data: Data, displayName: String?) {
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(displayName, forKey: displayNameKey)
    }

    func loadBookmark() -> Data? {
        defaults.data(forKey: bookmarkKey)
    }

    func displayName() -> String? {
        defaults.string(forKey: displayNameKey)
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: displayNameKey)
    }
}
