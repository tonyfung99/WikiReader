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

nonisolated struct GraphTopic: Identifiable, Hashable {
    let node: GraphNode
    let incoming: [String]
    let outgoing: [String]

    var id: String { node.id }
    var url: URL? { node.url }
    var exists: Bool { node.exists }
    var connectionCount: Int { Set(incoming + outgoing).count }
}

nonisolated struct GraphEdge: Hashable {
    let source: String
    let target: String
}

nonisolated struct VaultGraph {
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    var isEmpty: Bool { nodes.isEmpty }

    var topics: [GraphTopic] {
        nodes.map { node in
            let incoming = edges
                .filter { $0.target == node.id }
                .map(\.source)
                .sorted()
            let outgoing = edges
                .filter { $0.source == node.id }
                .map(\.target)
                .sorted()
            return GraphTopic(node: node, incoming: incoming, outgoing: outgoing)
        }
        .sorted { lhs, rhs in
            if lhs.connectionCount != rhs.connectionCount {
                return lhs.connectionCount > rhs.connectionCount
            }
            if lhs.exists != rhs.exists {
                return lhs.exists && !rhs.exists
            }
            if lhs.incoming.count != rhs.incoming.count {
                return lhs.incoming.count > rhs.incoming.count
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func topic(id: String) -> GraphTopic? {
        topics.first { $0.id == id }
    }

    func connectedNodeIDs(to id: String) -> Set<String> {
        var connected: Set<String> = []
        for edge in edges {
            if edge.source == id {
                connected.insert(edge.target)
            }
            if edge.target == id {
                connected.insert(edge.source)
            }
        }
        return connected
    }

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
