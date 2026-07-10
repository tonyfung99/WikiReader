import Foundation

nonisolated struct RecentNote: Identifiable, Equatable {
    let file: VaultFile
    let modified: Date

    var id: URL { file.url }
}

/// Finds the most recently modified markdown notes in the vault.
nonisolated enum RecentNotes {
    static func scan(root: URL, limit: Int = 10) -> [RecentNote] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var notes: [RecentNote] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            notes.append(RecentNote(file: VaultFile(url: url, isDirectory: false), modified: modified))
        }
        return Array(notes.sorted { $0.modified > $1.modified }.prefix(limit))
    }
}
