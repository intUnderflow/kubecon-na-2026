package app.kcna26.route

import androidx.compose.runtime.Immutable
import app.kcna26.data.Entrance
import app.kcna26.data.PointXY
import app.kcna26.data.Repository
import app.kcna26.geo.Geo
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import app.kcna26.data.Room as RoomData

/**
 * Indoor turn-by-turn routing (owner: engine): a port of schedule_app.js `path`, `route`,
 * `lvStartNode` and the summary in `wayHTML`, driven by wayfinding.json and rooms.json.
 *
 * - Dijkstra over the walking graph; edge cost = horizontal metres + 40 per level changed.
 * - Start texts, the Lower Concourse merge, the " About N m." suffix on same-level steps
 *   of 40 m or more, up/down/walk kinds, and the room's finalStep as the last step.
 * - All 7 test_vectors.json routes match word for word, and every route matches the web
 *   version's own output (see the unit tests in app/src/test/.../route/).
 *
 * Immutable and thread-safe. A route over 18 nodes takes microseconds, so it's fine to
 * recompute one for every location fix; [Route.start] tells you when a live start moved.
 */
class Router(private val repo: Repository) {
    private val way = repo.wayfinding
    private val graph = WalkGraph(way)
    private val mergeNodes: Set<Int> = way.routing.lowerConcourseMerge.nodes.mapNotNull(graph::indexOf).toSet()
    private val mergeWhere: Map<String, String> = way.routing.lowerConcourseMerge.where

    /** The entrance used when no other start works: E200S, as in the web. */
    private val defaultEntrance: Entrance? = way.entrances[DEFAULT_ENTRANCE] ?: way.entrances.values.firstOrNull()

    /** The entrances, in file order (E200S, EWT, EHY, E200W): the "Entrances" group of the From picker. */
    val startEntrances: List<Entrance> = way.entrances.values.toList()

    /**
     * The "Rooms" group of the From picker, as the web builds it: every room a session
     * uses that has a position and a walking-graph attachment, sorted by name
     * (case-insensitive, which gives the same order as the web's `localeCompare` here).
     * 37 rooms: OFF has no position, and REG and COAT have no sessions.
     */
    val startRooms: List<RoomData> = run {
        val used = repo.sessions.mapTo(HashSet()) { it.room }
        repo.rooms.values
            .filter { it.code in used && isRoutable(it) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** True if [roomCode] can be routed to (and from): it has a position, an attach node and a final step. */
    fun isRoutable(roomCode: String): Boolean = repo.room(roomCode)?.let(::isRoutable) == true

    /**
     * True if [value] is a usable From setting: "LIVE", an entrance key or a routable room
     * code. The web resets anything else to E200S.
     */
    fun isValidFrom(value: String): Boolean =
        value == FROM_LIVE || way.entrances.containsKey(value) || isRoutable(value)

    /** A live GPS position as a route start, converted to local metres with wayfinding.json "origin". */
    fun myLocation(lat: Double, lng: Double, accuracyM: Double): RouteFrom.MyLocation {
        val p = Geo.toLocal(lat, lng, way.origin)
        return RouteFrom.MyLocation(p.x, p.y, accuracyM)
    }

    /**
     * Maps a From setting value (`SettingsStore.directionsFrom`) and the latest fix to a start.
     * "LIVE" with no usable [fix] yet starts at E200S, exactly like the web; the resulting route
     * then has `live == false`, so show "Until GPS finds you, the steps start at the 200 South
     * entrance." ([NO_FIX_NOTE]). Unknown values also start at E200S.
     */
    fun resolveFrom(value: String, fix: RouteFrom.MyLocation?): RouteFrom = when {
        value == FROM_LIVE -> if (fix != null && fix.x.isFinite() && fix.y.isFinite()) fix else RouteFrom.Entrance(DEFAULT_ENTRANCE)
        way.entrances.containsKey(value) -> RouteFrom.Entrance(value)
        isRoutable(value) -> RouteFrom.Room(value)
        else -> RouteFrom.Entrance(DEFAULT_ENTRANCE)
    }

    /** [route] for a From setting value; see [resolveFrom]. */
    fun routeFromSetting(value: String, roomCode: String, fix: RouteFrom.MyLocation?): Route? =
        route(resolveFrom(value, fix), roomCode)

    /**
     * Route to [roomCode] from [from], or null if the room has no position (OFF) or is
     * unknown. For [RouteFrom.MyLocation] the start comes from [myLocationStart] and the
     * result has `live = true`; a non-finite position counts as no fix and starts at E200S
     * with `live = false`. An unknown entrance or start room also falls back to E200S.
     * Starting from the destination room itself gives the single end step
     * "You’re already in this room.".
     */
    fun route(from: RouteFrom, roomCode: String): Route? {
        val dest = repo.room(roomCode)?.takeIf(::isRoutable) ?: return null
        val destPos = dest.pos ?: return null
        val destLevel = dest.level ?: return null
        val destNode = graph.indexOf(dest.attachNode) ?: return null
        val finalStep = dest.finalStep ?: return null

        val start = when (from) {
            is RouteFrom.MyLocation -> if (from.x.isFinite() && from.y.isFinite()) from else null
            is RouteFrom.Entrance -> from.takeIf { way.entrances.containsKey(it.key) }
            is RouteFrom.Room -> from.takeIf { isRoutable(it.code) }
        } ?: RouteFrom.Entrance(defaultEntrance?.key ?: return null)

        val steps = ArrayList<Step>()
        val pts = ArrayList<PointXY>()
        val sNode: Int
        val startLevel: Int
        var startPoint: StartPoint? = null
        when (start) {
            is RouteFrom.MyLocation -> {
                val sp = myLocationStart(start.x, start.y)
                sNode = graph.indexOf(sp.node) ?: return null
                startLevel = graph.node(sNode).level
                startPoint = sp
                steps += Step(StepKind.START, sp.text, startLevel)
                pts += PointXY(start.x, start.y)
                pts += graph.node(sNode).pos
            }
            is RouteFrom.Entrance -> {
                val e = way.entrances.getValue(start.key)
                sNode = graph.indexOf(e.node) ?: return null
                startLevel = graph.node(sNode).level
                steps += Step(StepKind.START, "Start at the ${e.name}.", startLevel)
                pts += graph.node(sNode).pos
            }
            is RouteFrom.Room -> {
                val r = repo.room(start.code) ?: return null
                if (r.code == dest.code) {
                    return Route(
                        steps = listOf(Step(StepKind.END, ALREADY_HERE, destLevel)),
                        points = listOf(destPos),
                        totalM = 0.0,
                        levelsChanged = 0,
                        live = false,
                    )
                }
                sNode = graph.indexOf(r.attachNode) ?: return null
                startLevel = r.level ?: graph.node(sNode).level
                val node = graph.node(sNode)
                val text = if (r.finalStep.orEmpty().startsWith(YOURE_THERE)) "Start in the ${node.name}."
                else "Start at ${r.name}, then step out to the ${node.name}."
                steps += Step(StepKind.START, text, startLevel)
                pts += r.pos ?: node.pos
                pts += node.pos
            }
        }

        val legs = graph.path(sNode, destNode).orEmpty()
        for (run in mergeLegs(legs)) {
            val from0 = graph.node(run.from)
            val to = graph.node(run.to)
            val dl = to.level - from0.level
            val text = if (run.concourse) {
                val where = mergeWhere[to.key].orEmpty()
                if (to.y > from0.y) MERGE_NORTH.replace("{where}", where) else MERGE_SOUTH.replace("{where}", where)
            } else {
                run.text
            }
            val kind = when {
                dl > 0 -> StepKind.UP
                dl < 0 -> StepKind.DOWN
                else -> StepKind.WALK
            }
            // A merged run is measured straight from its first to its last node (web `len(l.from, l.to)`).
            val suffix = if (dl == 0) aboutSuffix(graph.horizontal(run.from, run.to)) else ""
            steps += Step(kind, text + suffix, to.level)
            for (i in run.nodes) pts += graph.node(i).pos
        }
        steps += Step(StepKind.END, finalStep, destLevel)
        pts += destPos

        return Route(
            steps = steps,
            points = pts,
            totalM = polylineLength(pts),
            levelsChanged = destLevel - startLevel,
            live = start is RouteFrom.MyLocation,
            start = startPoint,
        )
    }

    /**
     * Where a "My location" route starts, for a position in local metres (web `lvStartNode`):
     * the nearest node by (distance + 15 m per level above 1), first in file order on ties.
     * If that node is within 80 m (straight line) start there; otherwise start at the
     * entrance nearest by straight-line distance, with the step "Head to the {entrance},
     * about N m {direction} of you." (the web's sentence about its Google Maps button is left
     * out: the app has no such button). [x] and [y] should be finite; [route] treats a
     * non-finite position as no fix.
     */
    fun myLocationStart(x: Double, y: Double): StartPoint {
        var best: Int = -1
        var bestD = Double.POSITIVE_INFINITY
        for (i in 0 until graph.size) {
            val n = graph.node(i)
            val d = hypot(n.x - x, n.y - y) + (n.level - 1) * LEVEL_PENALTY
            if (d < bestD) {
                bestD = d
                best = i
            }
        }
        if (best >= 0) {
            val n = graph.node(best)
            if (hypot(n.x - x, n.y - y) <= INSIDE_RADIUS_M) {
                return StartPoint.Inside(
                    node = n.key,
                    text = "Start from where you are, near the ${n.name} (Level ${n.level}). " +
                        "GPS can’t tell floors apart; if that’s wrong, pick a room or entrance above.",
                )
            }
        }
        var entrance: Entrance? = null
        var ed = Double.POSITIVE_INFINITY
        for (e in way.entrances.values) {
            val n = graph.indexOf(e.node)?.let(graph::node) ?: continue
            val d = hypot(n.x - x, n.y - y)
            if (d < ed) {
                ed = d
                entrance = e
            }
        }
        val e = entrance ?: defaultEntrance ?: startEntrances.first()
        val node = graph.indexOf(e.node)?.let(graph::node)
        val p = PointXY(x, y)
        val brg = node?.let { Geo.bearing(p, it.pos) } ?: 0.0
        return StartPoint.Outside(
            entrance = e.key,
            node = e.node,
            distanceM = ed,
            bearingDeg = brg,
            // The web adds "The Google Maps button above walks you there."; the app has no such button.
            text = "Head to the ${e.name}, about ${Geo.r10(ed)} m ${Geo.dir8(brg)} of you.",
        )
    }

    /**
     * "About {round10(total)} m · {min} min · up/down N level(s)", with
     * min = max(1, round(total·1.15/75 + |levels|·0.6)); "" when total ≤ 5 m.
     * The level part is left out when [Route.levelsChanged] is 0.
     */
    fun summary(route: Route): String = summaryOf(route.totalM, route.levelsChanged)

    private fun isRoutable(r: RoomData): Boolean =
        r.hasPosition && r.finalStep != null && graph.indexOf(r.attachNode) != null

    /** Web: consecutive same-level legs between Lower Concourse nodes collapse into one run. */
    private fun mergeLegs(legs: List<Leg>): List<LegRun> {
        val out = ArrayList<LegRun>(legs.size)
        for (l in legs) {
            val con = l.from in mergeNodes && l.to in mergeNodes && graph.node(l.from).level == graph.node(l.to).level
            val last = out.lastOrNull()
            if (last != null && last.concourse && con) {
                out[out.size - 1] = last.copy(to = l.to, nodes = last.nodes + l.to)
            } else {
                out += LegRun(l.from, l.to, l.text, con, listOf(l.to))
            }
        }
        return out
    }

    /** A step's worth of legs: [nodes] are the node indices walked through, ending with [to]. */
    private data class LegRun(val from: Int, val to: Int, val text: String, val concourse: Boolean, val nodes: List<Int>)

    companion object {
        /** The From setting value for the live position (= SettingsStore.FROM_LIVE). */
        const val FROM_LIVE = "LIVE"

        /** Fallback start (web: "E200S"). */
        const val DEFAULT_ENTRANCE = "E200S"

        /** Web note shown when the From setting is LIVE but the route isn't live yet. */
        const val NO_FIX_NOTE = "Until GPS finds you, the steps start at the 200 South entrance."

        /** End step when starting from the destination room. */
        const val ALREADY_HERE = "You’re already in this room."

        /** finalStep prefix that turns the room start text into "Start in the {node}." */
        const val YOURE_THERE = "You’re there"

        /** Lower Concourse merge texts, from wayfinding.json routing.lowerConcourseMerge.rule. */
        const val MERGE_NORTH = "Walk north up the Lower Concourse to {where}. Hall DE and the showcase are on your left, the Grand Ballroom on your right."
        const val MERGE_SOUTH = "Walk south down the Lower Concourse to {where}. The Grand Ballroom is on your left, Hall DE and the showcase on your right."

        /** "My location" start: metres added per level above 1 when picking the nearest node. */
        const val LEVEL_PENALTY = 15.0

        /** "My location" start: the nearest node must be within this many metres, or we start outside. */
        const val INSIDE_RADIUS_M = 80.0

        /** Same-level steps at least this long get " About N m.". */
        const val ABOUT_MIN_M = 40.0

        /** " About N m." for [m] ≥ 40, else "" (web `about`). */
        fun aboutSuffix(m: Double): String = if (m >= ABOUT_MIN_M) " About ${Geo.round10(m)} m." else ""

        /** The route summary for a total length and a signed level change; see [Router.summary]. */
        fun summaryOf(totalM: Double, levelsChanged: Int): String {
            if (!(totalM > 5.0)) return ""
            val levels = abs(levelsChanged)
            val mins = max(1L, Geo.jsRound(totalM * 1.15 / 75.0 + levels * 0.6))
            val sb = StringBuilder("About ").append(Geo.round10(totalM)).append(" m · ").append(mins).append(" min")
            if (levelsChanged != 0) {
                sb.append(" · ").append(if (levelsChanged > 0) "up" else "down").append(' ').append(levels)
                    .append(if (levels > 1) " levels" else " level")
            }
            return sb.toString()
        }

        /** Sum of the segment lengths of a polyline. */
        fun polylineLength(points: List<PointXY>): Double {
            var m = 0.0
            for (i in 1 until points.size) m += Geo.distance(points[i - 1], points[i])
            return m
        }
    }
}

/** Step kinds (wayfinding.json "stepKinds"); [wire] is the lowercase name used in test_vectors.json. */
enum class StepKind {
    START, WALK, UP, DOWN, END;

    val wire: String get() = name.lowercase()

    val changesLevel: Boolean get() = this == UP || this == DOWN
}

/**
 * One instruction line.
 * @property level the floor you're on once this step is done (for START, the start level;
 *   for END, the room's level), or null if unknown (a Step built outside the router).
 */
@Immutable
data class Step(val kind: StepKind, val text: String, val level: Int? = null)

/**
 * A walking route.
 * @property points map polyline in local metres: the start (live position, entrance node, or
 *   start room then its node), every node walked through including merged ones, and the room.
 * @property totalM polyline length in metres.
 * @property levelsChanged destination level − start level (negative = down). The start level
 *   is the start node's for live and entrance starts, and the start room's for a room start.
 * @property live true when the route starts from the live GPS position.
 * @property start for live routes, where the live position resolved to ([StartPoint.key]
 *   changes when the start moves to another node or entrance); null otherwise.
 */
@Immutable
data class Route(
    val steps: List<Step>,
    val points: List<PointXY>,
    val totalM: Double,
    val levelsChanged: Int,
    val live: Boolean,
    val start: StartPoint? = null,
)

/** Where a route starts. Matches the "From" setting (SettingsStore.directionsFrom). */
sealed interface RouteFrom {
    /** Live position in local metres with GPS accuracy (m). See [Router.myLocation]. */
    data class MyLocation(val x: Double, val y: Double, val acc: Double) : RouteFrom

    /** An entrance key: E200S, EWT, EHY, E200W. */
    data class Entrance(val key: String) : RouteFrom

    /** A room code (starts at that room's attachNode). */
    data class Room(val code: String) : RouteFrom
}

/** Start of a "My location" route. */
@Immutable
sealed interface StartPoint {
    /** Wayfinding node the walking graph starts from. */
    val node: String

    /** Text of the START step. */
    val text: String

    /** Changes when the start changes, so the screen knows to re-route (web: LV.key). */
    val key: String

    /** Inside: start at the nearest node. */
    data class Inside(override val node: String, override val text: String) : StartPoint {
        override val key: String get() = node
    }

    /** Outside: walk to [entrance] first ([distanceM] at [bearingDeg] true). */
    data class Outside(
        val entrance: String,
        override val node: String,
        val distanceM: Double,
        val bearingDeg: Double,
        override val text: String,
    ) : StartPoint {
        override val key: String get() = "o$entrance"
    }
}
