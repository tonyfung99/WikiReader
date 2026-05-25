import SwiftUI

/// Loads the vault's wiki-link graph and hosts the interactive force layout.
struct GraphScreen: View {
    let root: URL

    @State private var graph: VaultGraph?
    @State private var isLoading = true
    @State private var selectedFile: VaultFile?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Building graph…")
            } else if let graph, !graph.isEmpty {
                ForceGraphView(graph: graph) { node in
                    if let url = node.url {
                        selectedFile = VaultFile(url: url, isDirectory: false)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No links yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Add [[wiki-links]] between notes to grow the graph.")
                )
            }
        }
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file)
        }
        .task {
            let url = root
            graph = await Task.detached(priority: .userInitiated) {
                VaultGraph.build(root: url)
            }.value
            isLoading = false
        }
    }
}

/// Animated, draggable force-directed graph drawn with Canvas.
struct ForceGraphView: View {
    @State private var layout: GraphLayout
    @State private var lastTick: Date?
    var onOpen: (GraphNode) -> Void

    init(graph: VaultGraph, onOpen: @escaping (GraphNode) -> Void) {
        _layout = State(initialValue: GraphLayout(graph: graph))
        self.onOpen = onOpen
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    _ = timeline.date  // redraw each frame
                    draw(in: &context)
                }
                .onChange(of: timeline.date) { _, newValue in
                    advance(to: newValue)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onAppear { layout.seedIfNeeded(in: geometry.size) }
            .onChange(of: geometry.size) { _, newSize in layout.seedIfNeeded(in: newSize) }
        }
    }

    private func advance(to date: Date) {
        let dt = lastTick.map { date.timeIntervalSince($0) } ?? (1.0 / 60.0)
        lastTick = date
        layout.step(dt: dt)
    }

    private func draw(in context: inout GraphicsContext) {
        for edge in layout.edges {
            guard layout.positions[edge.source] != nil, layout.positions[edge.target] != nil else { continue }
            var path = Path()
            path.move(to: layout.position(for: edge.source))
            path.addLine(to: layout.position(for: edge.target))
            context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }

        for node in layout.nodes {
            let point = layout.position(for: node.id)
            let radius: CGFloat = 7
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(node.exists ? .accentColor : .secondary))
            context.draw(
                Text(node.id).font(.caption2).foregroundColor(.primary),
                at: CGPoint(x: point.x, y: point.y + radius + 6),
                anchor: .top
            )
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if layout.draggingID == nil {
                    layout.draggingID = layout.nearestNode(to: value.startLocation, within: 32)
                }
                if let id = layout.draggingID {
                    layout.setDraggedPosition(value.location, for: id)
                }
            }
            .onEnded { value in
                let id = layout.draggingID
                layout.draggingID = nil
                let moved = hypot(value.translation.width, value.translation.height)
                if moved < 8, let id, let node = layout.nodes.first(where: { $0.id == id }), node.exists {
                    onOpen(node)
                }
            }
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
    return ForceGraphView(graph: VaultGraph(nodes: nodes, edges: edges)) { _ in }
}
