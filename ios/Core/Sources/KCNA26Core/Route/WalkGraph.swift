import Foundation

/// The indoor walking graph from wayfinding.json, indexed for Dijkstra (owner: engine).
///
/// Node indices follow the file order of `nodes` (the web's `Object.keys(N)`), and each
/// node's neighbour list follows the file order of `edges`, pushing b onto a's list and a
/// onto b's (the web's `ADJ`). Both orders decide ties, so keep them.
/// Immutable after construction and safe to share between threads.
final class WalkGraph: Sendable {
    let nodes: [WayNode]
    private let index: [String: Int]
    private let adj: [[Neighbour]]

    init(_ way: Wayfinding) {
        let nodes = Array(way.nodes.values)
        var index: [String: Int] = [:]
        for (i, n) in nodes.enumerated() { index[n.key] = i } // Kotlin `associate`: last wins
        var lists = [[Neighbour]](repeating: [], count: nodes.count)
        for e in way.edges {
            guard let a = index[e.a] else { continue } // an edge to an unknown node is ignored, not a crash
            guard let b = index[e.b] else { continue }
            lists[a].append(Neighbour(to: b, text: e.textAB))
            lists[b].append(Neighbour(to: a, text: e.textBA))
        }
        self.nodes = nodes
        self.index = index
        self.adj = lists
    }

    var size: Int { nodes.count }

    func indexOf(_ key: String?) -> Int? {
        guard let key else { return nil }
        return index[key]
    }

    func node(_ i: Int) -> WayNode { nodes[i] }

    /// Horizontal metres between two nodes (web `len`).
    func horizontal(_ a: Int, _ b: Int) -> Double { Geo.javaHypot(nodes[a].x - nodes[b].x, nodes[a].y - nodes[b].y) }

    /// Edge cost, web `dN`: horizontal metres + 40 per level changed.
    func cost(_ a: Int, _ b: Int) -> Double {
        horizontal(a, b) + Double(abs(nodes[a].level - nodes[b].level)) * WalkGraph.LEVEL_COST
    }

    /// Shortest path from `s` to `t` as legs in walking order, a straight port of the
    /// web's `path(s, t)`: an O(V²) Dijkstra that picks the first unvisited node in index
    /// order with the strictly smallest distance, stops once `t` is taken, relaxes
    /// neighbours in adjacency order with a strict `<`. Returns an empty list when
    /// s == t and nil when `t` can't be reached.
    func path(_ s: Int, _ t: Int) -> [Leg]? {
        let n = nodes.count
        if !(0..<n).contains(s) || !(0..<n).contains(t) { return nil }
        var dist = [Double](repeating: .infinity, count: n)
        var prev = [Int](repeating: -1, count: n)
        var prevText = [String?](repeating: nil, count: n)
        var todo = [Bool](repeating: true, count: n)
        dist[s] = 0.0
        while true {
            var u = -1
            for k in 0..<n where todo[k] && dist[k] != .infinity && (u == -1 || dist[k] < dist[u]) {
                u = k
            }
            if u == -1 { break }
            todo[u] = false
            if u == t { break }
            for nb in adj[u] {
                let nd = dist[u] + cost(u, nb.to)
                if nd < dist[nb.to] {
                    dist[nb.to] = nd
                    prev[nb.to] = u
                    prevText[nb.to] = nb.text
                }
            }
        }
        var reversed: [Leg] = []
        var c = t
        while c != s {
            let p = prev[c]
            if p < 0 { return nil }
            reversed.append(Leg(from: p, to: c, text: prevText[c] ?? ""))
            c = p
            if reversed.count > n { return nil } // defensive: a cycle in prev can't happen with positive costs
        }
        return reversed.reversed()
    }

    private struct Neighbour: Sendable {
        let to: Int
        let text: String
    }

    /// Metres added per level changed (wayfinding.json routing.algorithm).
    static let LEVEL_COST = 40.0
}

/// One edge walked from node index `from` to `to`, with the edge's instruction for that direction.
struct Leg: Sendable, Hashable {
    let from: Int
    let to: Int
    let text: String
}
