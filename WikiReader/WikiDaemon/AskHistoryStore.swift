import Foundation

/// Persists Ask-wiki query history as JSON in the App Group's UserDefaults
/// — local-only, never synced across devices, never written into the vault
/// (the daemon owns `wiki/` as sole writer).
nonisolated enum AskHistoryStore {
    private static let key = "askWiki.history"

    static func load(defaults: UserDefaults = AppGroup.defaults) -> [AskQueryEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let entries = (try? JSONDecoder().decode([AskQueryEntry].self, from: data)) ?? []
        return entries.sorted { $0.submittedAt > $1.submittedAt }
    }

    static func save(_ entries: [AskQueryEntry], defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: key)
    }
}
