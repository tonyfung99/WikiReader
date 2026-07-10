import Foundation
import Observation

/// Vault-wide derived data — the wiki-link graph and the full-text search
/// index — built once per vault session, off the main thread, and shared
/// across tabs via the environment.
@MainActor
@Observable
final class VaultIndex {
    let root: URL

    private(set) var graph: VaultGraph?
    private(set) var searcher: VaultSearcher?
    private(set) var isBuilding = false

    private var buildTask: Task<Void, Never>?

    init(root: URL) {
        self.root = root
    }

    /// Builds the index if it hasn't been built yet. Safe to call repeatedly.
    func ensureBuilt() {
        guard graph == nil, buildTask == nil else { return }
        rebuild()
    }

    /// Discards and rebuilds (e.g. after pull-to-refresh).
    func rebuild() {
        buildTask?.cancel()
        isBuilding = true
        let url = root
        buildTask = Task {
            let built = await Task.detached(priority: .userInitiated) {
                (VaultGraph.build(root: url), VaultSearcher.build(root: url))
            }.value
            graph = built.0
            searcher = built.1
            isBuilding = false
            buildTask = nil
        }
    }
}
