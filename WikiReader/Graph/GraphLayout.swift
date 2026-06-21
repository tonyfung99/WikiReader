import SwiftUI

nonisolated enum GraphViewport {
    static func contentSize(nodeCount: Int, viewport: CGSize) -> CGSize {
        let safeWidth = max(viewport.width, 1)
        let safeHeight = max(viewport.height, 1)
        let nodeScale = min(max(sqrt(Double(max(nodeCount, 1))) / 4.0, 1.15), 3.0)

        return CGSize(
            width: max(720, safeWidth * nodeScale),
            height: max(560, safeHeight * nodeScale)
        )
    }
}

/// A small force-directed layout: nodes repel each other, edges act as springs,
/// and a gentle gravity keeps the graph centered. Stepped once per animation
/// frame by the view.
@MainActor
@Observable
final class GraphLayout {
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    private(set) var positions: [String: CGPoint] = [:]
    private var velocities: [String: CGVector] = [:]

    var canvasSize: CGSize = .zero

    /// True once motion is negligible, so the view can pause its animation
    /// schedule instead of stepping the simulation every frame forever.
    private(set) var isSettled = false
    private var quietFrames = 0

    // Tuning constants.
    private let repulsion: Double = 9000
    private let springLength: Double = 70
    private let springStrength: Double = 0.04
    private let gravity: Double = 0.02
    private let damping: Double = 0.85
    private let maxSpeed: Double = 400

    init(graph: VaultGraph) {
        self.nodes = graph.nodes
        self.edges = graph.edges
    }

    func seedIfNeeded(in size: CGSize) {
        canvasSize = size
        guard positions.isEmpty, !nodes.isEmpty else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.35
        for (index, node) in nodes.enumerated() {
            let angle = (Double(index) / Double(nodes.count)) * 2 * .pi
            positions[node.id] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            velocities[node.id] = .zero
        }
        quietFrames = 0
        isSettled = false
    }

    func position(for id: String) -> CGPoint {
        positions[id] ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    func step(dt: Double) {
        guard !nodes.isEmpty, canvasSize != .zero else { return }
        let clampedDt = min(dt, 1.0 / 30.0)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        var forces: [String: CGVector] = [:]

        // Repulsion between every pair of nodes.
        for i in 0..<nodes.count {
            let a = nodes[i].id
            let pa = position(for: a)
            for j in (i + 1)..<nodes.count {
                let b = nodes[j].id
                let pb = position(for: b)
                var dx = pa.x - pb.x
                var dy = pa.y - pb.y
                var distSq = dx * dx + dy * dy
                if distSq < 0.01 {
                    dx = Double.random(in: -1...1)
                    dy = Double.random(in: -1...1)
                    distSq = 1
                }
                let force = repulsion / distSq
                let dist = sqrt(distSq)
                let fx = force * dx / dist
                let fy = force * dy / dist
                forces[a, default: .zero].dx += fx
                forces[a, default: .zero].dy += fy
                forces[b, default: .zero].dx -= fx
                forces[b, default: .zero].dy -= fy
            }
        }

        // Spring attraction along edges.
        for edge in edges {
            guard positions[edge.source] != nil, positions[edge.target] != nil else { continue }
            let ps = position(for: edge.source)
            let pt = position(for: edge.target)
            let dx = pt.x - ps.x
            let dy = pt.y - ps.y
            let dist = max(hypot(dx, dy), 0.01)
            let force = (dist - springLength) * springStrength
            let fx = force * dx / dist
            let fy = force * dy / dist
            forces[edge.source, default: .zero].dx += fx
            forces[edge.source, default: .zero].dy += fy
            forces[edge.target, default: .zero].dx -= fx
            forces[edge.target, default: .zero].dy -= fy
        }

        // Integrate.
        var maxObservedSpeed = 0.0
        for node in nodes {
            let id = node.id

            var velocity = velocities[id] ?? .zero
            var force = forces[id] ?? .zero
            let pos = position(for: id)

            force.dx += (center.x - pos.x) * gravity
            force.dy += (center.y - pos.y) * gravity

            velocity.dx = (velocity.dx + force.dx) * damping
            velocity.dy = (velocity.dy + force.dy) * damping

            let speed = hypot(velocity.dx, velocity.dy)
            if speed > maxSpeed {
                velocity.dx *= maxSpeed / speed
                velocity.dy *= maxSpeed / speed
            }

            velocities[id] = velocity
            positions[id] = CGPoint(x: pos.x + velocity.dx * clampedDt, y: pos.y + velocity.dy * clampedDt)
            maxObservedSpeed = max(maxObservedSpeed, hypot(velocity.dx, velocity.dy))
        }

        // Settle (and let the view pause) once motion stays negligible.
        quietFrames = maxObservedSpeed < 5 ? quietFrames + 1 : 0
        isSettled = quietFrames >= 24
    }
}
