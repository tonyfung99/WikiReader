import Foundation

nonisolated enum WikiLinkResolver {
    static func resolve(_ target: String, in root: URL) -> VaultFile? {
        let normalizedTarget = normalized(target)
        guard !normalizedTarget.isEmpty else { return nil }

        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            let file = VaultFile(
                url: url,
                isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            )
            guard !file.isDirectory, file.isMarkdown else { continue }
            if normalized(file.displayName) == normalizedTarget {
                return file
            }
        }

        return nil
    }

    private static func normalized(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".md") {
            trimmed.removeLast(3)
        }
        return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
