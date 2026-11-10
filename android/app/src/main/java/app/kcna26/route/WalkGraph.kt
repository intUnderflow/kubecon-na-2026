package app.kcna26.route

import app.kcna26.data.WayNode
import app.kcna26.data.Wayfinding
import kotlin.math.abs
import kotlin.math.hypot

/**
 * The indoor walking graph from wayfinding.json, indexed for Dijkstra (owner: engine).
 *
 * Node indices follow the file order of `nodes` (the web's `Object.keys(N)`), and each
 * node's neighbour list follows the file order of `edges`, pushing b onto a's list and a
 * onto b's (the web's `ADJ`). Both orders decide ties, so keep them.
 * Immutable after construction and safe to share between threads.
 */
internal class WalkGraph(way: Wayfinding) {
    val nodes: List<WayNode> = way.nodes.values.toList()
    private val index: Map<String, Int> = nodes.withIndex().associate { (i, n) -> n.key to i }
    private val adj: Array<List<Neighbour>>

    init {
        val lists = Array(nodes.size) { ArrayList<Neighbour>(4) }
        for (e in way.edges) {
            val a = index[e.a] ?: continue // an edge to an unknown node is ignored, not a crash
            val b = index[e.b] ?: continue
            lists[a].add(Neighbour(b, e.textAB))
            lists[b].add(Neighbour(a, e.textBA))
        }
        adj = Array(nodes.size) { lists[it] }
    }

    val size: Int get() = nodes.size

    fun indexOf(key: String?): Int? = key?.let { index[it] }

    fun node(i: Int): WayNode = nodes[i]

    /** Horizontal metres between two nodes (web `len`). */
    fun horizontal(a: Int, b: Int): Double = hypot(nodes[a].x - nodes[b].x, nodes[a].y - nodes[b].y)

    /** Edge cost, web `dN`: horizontal metres + 40 per level changed. */
    fun cost(a: Int, b: Int): Double = horizontal(a, b) + abs(nodes[a].level - nodes[b].level) * LEVEL_COST

    /**
     * Shortest path from [s] to [t] as legs in walking order, a straight port of the
     * web's `path(s, t)`: an O(V²) Dijkstra that picks the first unvisited node in index
     * order with the strictly smallest distance, stops once [t] is taken, relaxes
     * neighbours in adjacency order with a strict `<`. Returns an empty list when
     * s == t and null when [t] can't be reached.
     */
    fun path(s: Int, t: Int): List<Leg>? {
        val n = nodes.size
        if (s !in 0 until n || t !in 0 until n) return null
        val dist = DoubleArray(n) { Double.POSITIVE_INFINITY }
        val prev = IntArray(n) { -1 }
        val prevText = arrayOfNulls<String>(n)
        val todo = BooleanArray(n) { true }
        dist[s] = 0.0
        while (true) {
            var u = -1
            for (k in 0 until n) {
                if (todo[k] && dist[k] != Double.POSITIVE_INFINITY && (u == -1 || dist[k] < dist[u])) u = k
            }
            if (u == -1) break
            todo[u] = false
            if (u == t) break
            for (nb in adj[u]) {
                val nd = dist[u] + cost(u, nb.to)
                if (nd < dist[nb.to]) {
                    dist[nb.to] = nd
                    prev[nb.to] = u
                    prevText[nb.to] = nb.text
                }
            }
        }
        val out = ArrayDeque<Leg>()
        var c = t
        while (c != s) {
            val p = prev[c]
            if (p < 0) return null
            out.addFirst(Leg(p, c, prevText[c].orEmpty()))
            c = p
            if (out.size > n) return null // defensive: a cycle in prev can't happen with positive costs
        }
        return out.toList()
    }

    private class Neighbour(val to: Int, val text: String)

    companion object {
        /** Metres added per level changed (wayfinding.json routing.algorithm). */
        const val LEVEL_COST = 40.0
    }
}

/** One edge walked from node index [from] to [to], with the edge's instruction for that direction. */
internal data class Leg(val from: Int, val to: Int, val text: String)
