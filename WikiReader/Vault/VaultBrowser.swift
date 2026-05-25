import Foundation

/// Lists the browsable contents of a vault directory: subfolders and `.md`
/// files only, folders first, then alphabetical.
nonisolated enum VaultBrowser {
    static func list(directory: URL) -> [VaultFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let files = entries.map { url -> VaultFile in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return VaultFile(url: url, isDirectory: isDir)
        }

        return files
            .filter { $0.isDirectory || $0.isMarkdown }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// Reads a markdown file, downloading it from iCloud first if it's only a
    /// placeholder on this device.
    static func readContents(of file: VaultFile) throws -> String {
        if file.isPlaceholder {
            try FileManager.default.startDownloadingUbiquitousItem(at: file.url)
            // The materialized file lives at the de-decorated path.
            let realURL = file.url
                .deletingLastPathComponent()
                .appendingPathComponent(file.name)
            return try waitForContents(at: realURL)
        }
        return try String(contentsOf: file.url, encoding: .utf8)
    }

    private static func waitForContents(at url: URL, attempts: Int = 20) throws -> String {
        for _ in 0..<attempts {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
