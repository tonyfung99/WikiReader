import Foundation

nonisolated enum WikiLinkParser {
    /// Returns the target names of every `[[wiki-link]]` in the text,
    /// dropping any `|alias` and a trailing `.md`.
    static func links(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let inner = ns.substring(with: match.range(at: 1))
            var target = inner.components(separatedBy: "|").first ?? inner
            target = target.trimmingCharacters(in: .whitespaces)
            if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
            return target
        }
    }
}

nonisolated struct GraphNode: Identifiable, Hashable {
    let id: String
    let url: URL?
    var exists: Bool { url != nil }
}

nonisolated struct GraphEdge: Hashable {
    let source: String
    let target: String
}

nonisolated struct VaultGraph {
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    var isEmpty: Bool { nodes.isEmpty }

    /// Walks the vault, builds a node per `.md` file (plus phantom nodes for
    /// link targets that don't exist yet), and an edge per `[[wiki-link]]`.
    static func build(root: URL) -> VaultGraph {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return VaultGraph(nodes: [], edges: [])
        }

        var nodeURLs: [String: URL] = [:]
        var names: Set<String> = []
        var edges: Set<GraphEdge> = []

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let name = url.deletingPathExtension().lastPathComponent
            nodeURLs[name] = url
            names.insert(name)

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for target in WikiLinkParser.links(in: text) where !target.isEmpty {
                names.insert(target)
                if target != name {
                    edges.insert(GraphEdge(source: name, target: target))
                }
            }
        }

        let nodes = names.sorted().map { GraphNode(id: $0, url: nodeURLs[$0]) }
        return VaultGraph(nodes: nodes, edges: Array(edges))
    }
}
