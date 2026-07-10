import SwiftUI

/// Loads the vault's wiki-link graph and hosts the interactive force layout.
struct GraphScreen: View {
    let root: URL

    @Environment(VaultIndex.self) private var index: VaultIndex?

    @State private var localGraph: VaultGraph?
    @State private var isLocalLoading = false
    @State private var selectedFile: VaultFile?

    private var graph: VaultGraph? { index?.graph ?? localGraph }
    private var isLoading: Bool { index.map(\.isBuilding) ?? isLocalLoading }

    var body: some View {
        Group {
            if let graph, !graph.isEmpty {
                GraphExplorerView(graph: graph) { node in
                    open(node)
                }
            } else if isLoading || graph == nil {
                ProgressView("Building graph…")
            } else {
                ContentUnavailableView(
                    "No links yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Add [[wiki-links]] between notes to grow the graph.")
                )
            }
        }
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
        .task {
            if let index {
                index.ensureBuilt()
            } else if localGraph == nil {
                isLocalLoading = true
                let url = root
                localGraph = await Task.detached(priority: .userInitiated) {
                    VaultGraph.build(root: url)
                }.value
                isLocalLoading = false
            }
        }
    }

    private func open(_ node: GraphNode) {
        guard let url = node.url else { return }
        selectedFile = VaultFile(url: url, isDirectory: false)
    }
}

/// Combines the graph map with a searchable topic index so the graph works as
/// both a visual overview and a practical vault navigation surface.
private struct GraphExplorerView: View {
    let graph: VaultGraph
    var onOpen: (GraphNode) -> Void

    @State private var searchText = ""
    @State private var selectedTopicID: String?
    @State private var isWide = false

    private var filteredTopics: [GraphTopic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return graph.topics }
        return graph.topics.filter { $0.id.localizedCaseInsensitiveContains(query) }
    }

    private var highlightedIDs: Set<String> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return Set(filteredTopics.map(\.id))
        }
        guard let selectedTopicID else { return [] }
        return graph.connectedNodeIDs(to: selectedTopicID).union([selectedTopicID])
    }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    topicList
                        .frame(width: 300)
                    Divider()
                    graphMap
                }
            } else {
                VStack(spacing: 0) {
                    graphMap
                        .frame(minHeight: 300)
                        .layoutPriority(1)
                    Divider()
                    topicList
                        .frame(minHeight: 180, maxHeight: 280)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 760 && proxy.size.width > proxy.size.height
        } action: { newValue in
            isWide = newValue
        }
        .searchable(text: $searchText, prompt: "Find topics")
    }

    private var graphMap: some View {
        ForceGraphView(
            graph: graph,
            selectedID: selectedTopicID,
            highlightedIDs: highlightedIDs
        ) { node in
            selectedTopicID = node.id
        } onOpen: { node in
            selectedTopicID = node.id
            onOpen(node)
        }
    }

    private var topicList: some View {
        GraphTopicList(
            topics: filteredTopics,
            selectedID: selectedTopicID
        ) { topic in
            selectedTopicID = topic.id
        } onOpen: { node in
            selectedTopicID = node.id
            onOpen(node)
        }
    }
}

private struct GraphTopicList: View {
    let topics: [GraphTopic]
    let selectedID: String?
    var onSelect: (GraphTopic) -> Void
    var onOpen: (GraphNode) -> Void

    var body: some View {
        List(topics) { topic in
            HStack(spacing: 8) {
                GraphTopicRow(topic: topic, isSelected: selectedID == topic.id)

                if topic.exists {
                    Button {
                        onSelect(topic)
                        onOpen(topic.node)
                    } label: {
                        Image(systemName: "arrow.forward.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open \(topic.id)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(topic) }
            .listRowBackground(selectedID == topic.id ? Color.accentColor.opacity(0.12) : Color.clear)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(topic.exists ? "Selects topic. Use the open button to read the note." : "Linked note is missing")
        }
        .listStyle(.plain)
        .overlay {
            if topics.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try another topic name.")
                )
            }
        }
    }
}

private struct GraphTopicRow: View {
    let topic: GraphTopic
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.exists ? "doc.text" : "doc.badge.questionmark")
                .foregroundStyle(topic.exists ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.id)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    Label("\(topic.connectionCount)", systemImage: "link")
                    if !topic.exists {
                        Text("Missing")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }
}

/// Animated force-directed graph drawn with Canvas edges and clickable node overlays.
struct ForceGraphView: View {
    @State private var layout: GraphLayout
    @State private var lastTick: Date?
    var selectedID: String?
    var highlightedIDs: Set<String>
    var onSelect: (GraphNode) -> Void
    var onOpen: (GraphNode) -> Void

    init(
        graph: VaultGraph,
        selectedID: String? = nil,
        highlightedIDs: Set<String> = [],
        onSelect: @escaping (GraphNode) -> Void,
        onOpen: @escaping (GraphNode) -> Void
    ) {
        _layout = State(initialValue: GraphLayout(graph: graph))
        self.selectedID = selectedID
        self.highlightedIDs = highlightedIDs
        self.onSelect = onSelect
        self.onOpen = onOpen
    }

    var body: some View {
        GeometryReader { geometry in
            let contentSize = GraphViewport.contentSize(nodeCount: layout.nodes.count, viewport: geometry.size)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation(paused: layout.isSettled)) { timeline in
                        Canvas { context, size in
                            _ = timeline.date  // redraw each frame
                            drawEdges(in: &context)
                        }
                        .onChange(of: timeline.date) { _, newValue in
                            advance(to: newValue)
                        }
                    }
                    .frame(width: contentSize.width, height: contentSize.height)

                    ForEach(layout.nodes) { node in
                        GraphNodeButton(
                            node: node,
                            isSelected: selectedID == node.id,
                            isHighlighted: isHighlighted(node.id),
                            position: layout.position(for: node.id)
                        ) {
                            onSelect(node)
                            if node.exists {
                                onOpen(node)
                            }
                        }
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .background(.background)
            }
            .onAppear { layout.seedIfNeeded(in: contentSize) }
            .onChange(of: contentSize) { _, newSize in layout.seedIfNeeded(in: newSize) }
            .accessibilityRepresentation {
                List(layout.nodes) { node in
                    if node.exists {
                        Button(node.id) {
                            onSelect(node)
                            onOpen(node)
                        }
                    } else {
                        Text(node.id).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func advance(to date: Date) {
        let dt = lastTick.map { date.timeIntervalSince($0) } ?? (1.0 / 60.0)
        lastTick = date
        layout.step(dt: dt)
    }

    private func drawEdges(in context: inout GraphicsContext) {
        for edge in layout.edges {
            guard layout.positions[edge.source] != nil, layout.positions[edge.target] != nil else { continue }
            var path = Path()
            path.move(to: layout.position(for: edge.source))
            path.addLine(to: layout.position(for: edge.target))
            let active = isHighlighted(edge.source) && isHighlighted(edge.target)
            context.stroke(
                path,
                with: .color(active ? .accentColor.opacity(0.5) : .secondary.opacity(0.18)),
                lineWidth: active ? 1.5 : 1
            )
        }
    }

    private func isHighlighted(_ id: String) -> Bool {
        highlightedIDs.isEmpty || highlightedIDs.contains(id)
    }
}

private struct GraphNodeButton: View {
    let node: GraphNode
    let isSelected: Bool
    let isHighlighted: Bool
    let position: CGPoint
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(node.exists ? Color.accentColor : Color.clear)
                    Circle()
                        .stroke(node.exists ? Color.accentColor : Color.secondary, lineWidth: node.exists ? 1 : 2)
                    if isSelected {
                        Circle()
                            .stroke(Color.orange, lineWidth: 3)
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(width: 16, height: 16)

                Text(node.id)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
            .frame(minWidth: 44, minHeight: 44)
            .opacity(isHighlighted ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .position(position)
        .accessibilityLabel(node.id)
        .accessibilityValue(node.exists ? "Note" : "Missing note")
    }
}

#Preview {
    let names = ["Index", "Swift", "iOS", "Graph", "Vault"]
    let nodes = names.map { GraphNode(id: $0, url: URL(string: "file:///\($0)")) }
    let edges = [
        GraphEdge(source: "Index", target: "Swift"),
        GraphEdge(source: "Index", target: "iOS"),
        GraphEdge(source: "Swift", target: "iOS"),
        GraphEdge(source: "Index", target: "Graph"),
        GraphEdge(source: "Graph", target: "Vault"),
    ]
    return GraphExplorerView(graph: VaultGraph(nodes: nodes, edges: edges)) { _ in }
}
