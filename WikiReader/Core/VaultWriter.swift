import Foundation

/// Writes a markdown file into the vault directory using a temp-then-rename
/// dance, so filesystem watchers (llm_wiki, iCloud) never observe a partial
/// or zero-byte file.
struct VaultWriter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func write(_ content: String, filename: String, to directory: URL) throws -> URL {
        let finalURL = uniqueURL(for: filename, in: directory)
        let tempURL = directory.appendingPathComponent(".\(finalURL.lastPathComponent).tmp")

        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        try Data(content.utf8).write(to: tempURL, options: .atomic)
        try fileManager.moveItem(at: tempURL, to: finalURL)
        return finalURL
    }

    /// Returns a URL whose filename doesn't collide with an existing file,
    /// appending `-1`, `-2`, … if needed.
    func uniqueURL(for filename: String, in directory: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}
