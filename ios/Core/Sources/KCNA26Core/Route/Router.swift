import Foundation

/// Indoor turn-by-turn routing (owner: engine): a port of schedule_app.js `path`, `route`,
/// `lvStartNode` and the summary in `wayHTML`, driven by wayfinding.json and rooms.json.
///
/// - Dijkstra over the walking graph; edge cost = horizontal metres + 40 per level changed.
/// - Start texts, the Lower Concourse merge, the " About N m." suffix on same-level steps
///   of 40 m or more, up/down/walk kinds, and the room's finalStep as the last step.
/// - All 7 test_vectors.json routes match word for word, and every route matches the web
///   version's own output (see RouterTests and WebParityTests).
///
/// Immutable and thread-safe. A route over 18 nodes takes microseconds, so it's fine to
/// recompute one for every location fix; ``Route/start`` tells you when a live start moved.
///
/// ```swift
/// let router = Router(repo)                              // once per Repository
/// let route = router.routeFromSetting(settings.directionsFrom, room.code, fix)
/// router.summary(route)                                  // "About 250 m · 4 min · up 1 level"
/// ```
final class Router: Sendable {
    private let repo: Repository
    private let way: Wayfinding
    private let graph: WalkGraph
    private let mergeNodes: Set<Int>
    private let mergeWhere: OrderedMap<String, String>

    /// The entrance used when no other start works: E200S, as in the web.
    private let defaultEntrance: Entrance?

    /// The entrances, in file order (E200S, EWT, EHY, E200W): the "Entrances" group of the From picker.
    let startEntrances: [Entrance]

    /// The "Rooms" group of the From picker, as the web builds it: every room a session
    /// uses that has a position and a walking-graph attachment, sorted by name
    /// (case-insensitive, which gives the same order as the web's `localeCompare` here).
    /// 37 rooms: OFF has no position, and REG and COAT have no sessions.
    let startRooms: [Room]

    init(_ repo: Repository) {
        let way = repo.wayfinding
        let graph = WalkGraph(way)
        self.repo = repo
        self.way = way
        self.graph = graph
        mergeNodes = Set(way.routing.lowerConcourseMerge.nodes.compactMap { graph.indexOf($0) })
        mergeWhere = way.routing.lowerConcourseMerge.where
        defaultEntrance = way.entrances[Router.DEFAULT_ENTRANCE] ?? way.entrances.values.first
        startEntrances = Array(way.entrances.values)
        let used = Set(repo.sessions.map(\.room))
        startRooms = repo.rooms.values
            .filter { used.contains($0.code) && Router.isRoutable($0, graph) }
            .stableSorted(with: .by(.caseInsensitiveOrder) { $0.name })
    }

    /// True if `roomCode` can be routed to (and from): it has a position, an attach node and a final step.
    func isRoutable(_ roomCode: String) -> Bool {
        guard let r = repo.room(roomCode) else { return false }
        return Router.isRoutable(r, graph)
    }

    /// True if `value` is a usable From setting: "LIVE", an entrance key or a routable room
    /// code. The web resets anything else to E200S.
    func isValidFrom(_ value: String) -> Bool {
        kotlinEquals(value, Router.FROM_LIVE) || way.entrances.containsKey(value) || isRoutable(value)
    }

    /// A live GPS position as a route start, converted to local metres with wayfinding.json "origin".
    func myLocation(_ lat: Double, _ lng: Double, _ accuracyM: Double) -> RouteFrom.MyLocation {
        let p = Geo.toLocal(lat, lng, way.origin)
        return RouteFrom.MyLocation(p.x, p.y, accuracyM)
    }

    /// Maps a From setting value (`SettingsStore.directionsFrom`) and the latest fix to a start.
    /// "LIVE" with no usable `fix` yet starts at E200S, exactly like the web; the resulting route
    /// then has `live == false`, so show "Until GPS finds you, the steps start at the 200 South
    /// entrance." (``NO_FIX_NOTE``). Unknown values also start at E200S.
    func resolveFrom(_ value: String, _ fix: RouteFrom.MyLocation?) -> RouteFrom {
        if kotlinEquals(value, Router.FROM_LIVE) {
            if let fix, fix.x.isFinite, fix.y.isFinite { return .myLocation(fix) }
            return .entrance(Router.DEFAULT_ENTRANCE)
        }
        if way.entrances.containsKey(value) { return .entrance(value) }
        if isRoutable(value) { return .room(value) }
        return .entrance(Router.DEFAULT_ENTRANCE)
    }

    /// ``route(_:_:)`` for a From setting value; see ``resolveFrom(_:_:)``.
    func routeFromSetting(_ value: String, _ roomCode: String, _ fix: RouteFrom.MyLocation?) -> Route? {
        route(resolveFrom(value, fix), roomCode)
    }

    /// Route to `roomCode` from `from`, or nil if the room has no position (OFF) or is
    /// unknown. For ``RouteFrom/myLocation(_:)`` the start comes from ``myLocationStart(_:_:)``
    /// and the result has `live = true`; a non-finite position counts as no fix and starts at
    /// E200S with `live = false`. An unknown entrance or start room also falls back to E200S.
    /// Starting from the destination room itself gives the single end step
    /// "You’re already in this room.".
    func route(_ from: RouteFrom, _ roomCode: String) -> Route? {
        guard let dest = repo.room(roomCode), Router.isRoutable(dest, graph) else { return nil }
        guard let destPos = dest.pos, let destLevel = dest.level,
              let destNode = graph.indexOf(dest.attachNode), let finalStep = dest.finalStep else { return nil }

        let usable: RouteFrom?
        switch from {
        case .myLocation(let m): usable = m.x.isFinite && m.y.isFinite ? from : nil
        case .entrance(let key): usable = way.entrances.containsKey(key) ? from : nil
        case .room(let code): usable = isRoutable(code) ? from : nil
        }
        let start: RouteFrom
        if let usable {
            start = usable
        } else {
            guard let key = defaultEntrance?.key else { return nil }
            start = .entrance(key)
        }

        var steps: [Step] = []
        var pts: [PointXY] = []
        let sNode: Int
        let startLevel: Int
        var startPoint: StartPoint?
        switch start {
        case .myLocation(let m):
            let sp = myLocationStart(m.x, m.y)
            guard let i = graph.indexOf(sp.node) else { return nil }
            sNode = i
            startLevel = graph.node(sNode).level
            startPoint = sp
            steps.append(Step(.start, sp.text, startLevel))
            pts.append(PointXY(m.x, m.y))
            pts.append(graph.node(sNode).pos)
        case .entrance(let key):
            guard let e = way.entrances[key], let i = graph.indexOf(e.node) else { return nil }
            sNode = i
            startLevel = graph.node(sNode).level
            steps.append(Step(.start, "Start at the \(e.name).", startLevel))
            pts.append(graph.node(sNode).pos)
        case .room(let code):
            guard let r = repo.room(code) else { return nil }
            if r.code == dest.code {
                return Route(
                    steps: [Step(.end, Router.ALREADY_HERE, destLevel)],
                    points: [destPos],
                    totalM: 0.0,
                    levelsChanged: 0,
                    live: false
                )
            }
            guard let i = graph.indexOf(r.attachNode) else { return nil }
            sNode = i
            startLevel = r.level ?? graph.node(sNode).level
            let node = graph.node(sNode)
            let text = (r.finalStep ?? "").kotlinStartsWith(Router.YOURE_THERE)
                ? "Start in the \(node.name)."
                : "Start at \(r.name), then step out to the \(node.name)."
            steps.append(Step(.start, text, startLevel))
            pts.append(r.pos ?? node.pos)
            pts.append(node.pos)
        }

        let legs = graph.path(sNode, destNode) ?? []
        for run in mergeLegs(legs) {
            let from0 = graph.node(run.from)
            let to = graph.node(run.to)
            let dl = to.level - from0.level
            let text: String
            if run.concourse {
                let `where` = mergeWhere[to.key] ?? ""
                text = to.y > from0.y
                    ? Router.MERGE_NORTH.kotlinReplace("{where}", `where`)
                    : Router.MERGE_SOUTH.kotlinReplace("{where}", `where`)
            } else {
                text = run.text
            }
            let kind: StepKind = dl > 0 ? .up : (dl < 0 ? .down : .walk)
            // A merged run is measured straight from its first to its last node (web `len(l.from, l.to)`).
            let suffix = dl == 0 ? Router.aboutSuffix(graph.horizontal(run.from, run.to)) : ""
            steps.append(Step(kind, text + suffix, to.level))
            for i in run.nodes { pts.append(graph.node(i).pos) }
        }
        steps.append(Step(.end, finalStep, destLevel))
        pts.append(destPos)

        let live: Bool
        if case .myLocation = start { live = true } else { live = false }
        return Route(
            steps: steps,
            points: pts,
            totalM: Router.polylineLength(pts),
            levelsChanged: destLevel - startLevel,
            live: live,
            start: startPoint
        )
    }

    /// Where a "My location" route starts, for a position in local metres (web `lvStartNode`):
    /// the nearest node by (distance + 15 m per level above 1), first in file order on ties.
    /// If that node is within 80 m (straight line) start there; otherwise start at the
    /// entrance nearest by straight-line distance, with the step "Head to the {entrance},
    /// about N m {direction} of you." (the web's sentence about its Google Maps button is left
    /// out: the app has no such button). `x` and `y` should be finite; ``route(_:_:)`` treats a
    /// non-finite position as no fix.
    func myLocationStart(_ x: Double, _ y: Double) -> StartPoint {
        var best = -1
        var bestD = Double.infinity
        for i in 0..<graph.size {
            let n = graph.node(i)
            let d = Geo.javaHypot(n.x - x, n.y - y) + Double(n.level - 1) * Router.LEVEL_PENALTY
            if d < bestD {
                bestD = d
                best = i
            }
        }
        if best >= 0 {
            let n = graph.node(best)
            if Geo.javaHypot(n.x - x, n.y - y) <= Router.INSIDE_RADIUS_M {
                return .inside(StartPoint.Inside(
                    node: n.key,
                    text: "Start from where you are, near the \(n.name) (Level \(n.level)). "
                        + "GPS can’t tell floors apart; if that’s wrong, pick a room or entrance above."
                ))
            }
        }
        var entrance: Entrance?
        var ed = Double.infinity
        for e in way.entrances.values {
            guard let i = graph.indexOf(e.node) else { continue }
            let n = graph.node(i)
            let d = Geo.javaHypot(n.x - x, n.y - y)
            if d < ed {
                ed = d
                entrance = e
            }
        }
        guard let e = entrance ?? defaultEntrance ?? startEntrances.first else {
            // Kotlin throws NoSuchElementException here (a wayfinding.json without entrances);
            // an empty start makes route() answer nil instead of crashing.
            return .outside(StartPoint.Outside(entrance: "", node: "", distanceM: ed, bearingDeg: 0.0, text: ""))
        }
        let node = graph.indexOf(e.node).map { graph.node($0) }
        let p = PointXY(x, y)
        let brg = node.map { Geo.bearing(p, $0.pos) } ?? 0.0
        return .outside(StartPoint.Outside(
            entrance: e.key,
            node: e.node,
            distanceM: ed,
            bearingDeg: brg,
            // The web adds "The Google Maps button above walks you there."; the app has no such button.
            text: "Head to the \(e.name), about \(Geo.r10(ed)) m \(Geo.dir8(brg)) of you."
        ))
    }

    /// "About {round10(total)} m · {min} min · up/down N level(s)", with
    /// min = max(1, round(total·1.15/75 + |levels|·0.6)); "" when total ≤ 5 m.
    /// The level part is left out when ``Route/levelsChanged`` is 0.
    func summary(_ route: Route) -> String { Router.summaryOf(route.totalM, route.levelsChanged) }

    private static func isRoutable(_ r: Room, _ graph: WalkGraph) -> Bool {
        r.hasPosition && r.finalStep != nil && graph.indexOf(r.attachNode) != nil
    }

    /// Web: consecutive same-level legs between Lower Concourse nodes collapse into one run.
    private func mergeLegs(_ legs: [Leg]) -> [LegRun] {
        var out: [LegRun] = []
        out.reserveCapacity(legs.count)
        for l in legs {
            let con = mergeNodes.contains(l.from) && mergeNodes.contains(l.to)
                && graph.node(l.from).level == graph.node(l.to).level
            if let last = out.last, last.concourse, con {
                out[out.count - 1] = LegRun(from: last.from, to: l.to, text: last.text, concourse: last.concourse, nodes: last.nodes + [l.to])
            } else {
                out.append(LegRun(from: l.from, to: l.to, text: l.text, concourse: con, nodes: [l.to]))
            }
        }
        return out
    }

    /// A step's worth of legs: `nodes` are the node indices walked through, ending with `to`.
    private struct LegRun {
        let from: Int
        let to: Int
        let text: String
        let concourse: Bool
        let nodes: [Int]
    }

    /// The From setting value for the live position (= SettingsStore.FROM_LIVE).
    static let FROM_LIVE = "LIVE"

    /// Fallback start (web: "E200S").
    static let DEFAULT_ENTRANCE = "E200S"

    /// Web note shown when the From setting is LIVE but the route isn't live yet.
    static let NO_FIX_NOTE = "Until GPS finds you, the steps start at the 200 South entrance."

    /// End step when starting from the destination room.
    static let ALREADY_HERE = "You’re already in this room."

    /// finalStep prefix that turns the room start text into "Start in the {node}."
    static let YOURE_THERE = "You’re there"

    /// Lower Concourse merge texts, from wayfinding.json routing.lowerConcourseMerge.rule.
    static let MERGE_NORTH = "Walk north up the Lower Concourse to {where}. Hall DE and the showcase are on your left, the Grand Ballroom on your right."
    static let MERGE_SOUTH = "Walk south down the Lower Concourse to {where}. The Grand Ballroom is on your left, Hall DE and the showcase on your right."

    /// "My location" start: metres added per level above 1 when picking the nearest node.
    static let LEVEL_PENALTY = 15.0

    /// "My location" start: the nearest node must be within this many metres, or we start outside.
    static let INSIDE_RADIUS_M = 80.0

    /// Same-level steps at least this long get " About N m.".
    static let ABOUT_MIN_M = 40.0

    /// " About N m." for `m` ≥ 40, else "" (web `about`).
    static func aboutSuffix(_ m: Double) -> String { m >= ABOUT_MIN_M ? " About \(Geo.round10(m)) m." : "" }

    /// The route summary for a total length and a signed level change; see ``summary(_:)``.
    static func summaryOf(_ totalM: Double, _ levelsChanged: Int) -> String {
        if !(totalM > 5.0) { return "" }
        let levels = levelsChanged == Int.min ? Int.max : abs(levelsChanged) // Swift's abs traps on Int.min
        let minutes: Double = totalM * 1.15 / 75.0 + Double(levels) * 0.6
        let mins = max(Int64(1), Geo.jsRound(minutes))
        var sb = "About \(Geo.round10(totalM)) m · \(mins) min"
        if levelsChanged != 0 {
            sb += " · \(levelsChanged > 0 ? "up" : "down") \(levels)\(levels > 1 ? " levels" : " level")"
        }
        return sb
    }

    /// Sum of the segment lengths of a polyline.
    static func polylineLength(_ points: [PointXY]) -> Double {
        var m = 0.0
        for i in points.indices.dropFirst() { m += Geo.distance(points[i - 1], points[i]) }
        return m
    }
}

/// Step kinds (wayfinding.json "stepKinds"); ``wire`` is the lowercase name used in test_vectors.json.
enum StepKind: String, Sendable, Hashable, CaseIterable {
    case start, walk, up, down, end

    /// Kotlin's enum `name`: "START", "WALK", ….
    var name: String { rawValue.uppercased() }

    var wire: String { rawValue }

    var changesLevel: Bool { self == .up || self == .down }
}

/// One instruction line.
/// - `level`: the floor you're on once this step is done (for START, the start level;
///   for END, the room's level), or nil if unknown (a Step built outside the router).
struct Step: Sendable, Hashable {
    let kind: StepKind
    let text: String
    let level: Int?

    init(kind: StepKind, text: String, level: Int? = nil) {
        self.kind = kind
        self.text = text
        self.level = level
    }

    init(_ kind: StepKind, _ text: String, _ level: Int? = nil) {
        self.init(kind: kind, text: text, level: level)
    }
}

/// A walking route.
/// - `points`: map polyline in local metres: the start (live position, entrance node, or
///   start room then its node), every node walked through including merged ones, and the room.
/// - `totalM`: polyline length in metres.
/// - `levelsChanged`: destination level − start level (negative = down). The start level
///   is the start node's for live and entrance starts, and the start room's for a room start.
/// - `live`: true when the route starts from the live GPS position.
/// - `start`: for live routes, where the live position resolved to (``StartPoint/key``
///   changes when the start moves to another node or entrance); nil otherwise.
struct Route: Sendable, Hashable {
    let steps: [Step]
    let points: [PointXY]
    let totalM: Double
    let levelsChanged: Int
    let live: Bool
    let start: StartPoint?

    init(steps: [Step], points: [PointXY], totalM: Double, levelsChanged: Int, live: Bool, start: StartPoint? = nil) {
        self.steps = steps
        self.points = points
        self.totalM = totalM
        self.levelsChanged = levelsChanged
        self.live = live
        self.start = start
    }
}

/// Where a route starts. Matches the "From" setting (SettingsStore.directionsFrom).
/// Kotlin's sealed interface: `RouteFrom.Entrance(key)` -> `.entrance(key)`,
/// `RouteFrom.Room(code)` -> `.room(code)`, `RouteFrom.MyLocation(x, y, acc)` ->
/// `.myLocation(RouteFrom.MyLocation(x, y, acc))` (or `.myLocation(x, y, acc)`).
enum RouteFrom: Sendable, Hashable {
    /// Live position in local metres with GPS accuracy (m). See ``Router/myLocation(_:_:_:)``.
    case myLocation(MyLocation)

    /// An entrance key: E200S, EWT, EHY, E200W.
    case entrance(String)

    /// A room code (starts at that room's attachNode).
    case room(String)

    /// Kotlin `RouteFrom.MyLocation`.
    struct MyLocation: Sendable, Hashable {
        let x: Double
        let y: Double
        let acc: Double

        init(_ x: Double, _ y: Double, _ acc: Double) {
            self.x = x
            self.y = y
            self.acc = acc
        }

        init(x: Double, y: Double, acc: Double) {
            self.init(x, y, acc)
        }
    }

    /// `.myLocation(MyLocation(x, y, acc))`.
    static func myLocation(_ x: Double, _ y: Double, _ acc: Double) -> RouteFrom { .myLocation(MyLocation(x, y, acc)) }
}

/// Start of a "My location" route.
enum StartPoint: Sendable, Hashable {
    /// Inside: start at the nearest node.
    case inside(Inside)

    /// Outside: walk to the entrance first.
    case outside(Outside)

    struct Inside: Sendable, Hashable {
        let node: String
        let text: String

        var key: String { node }
    }

    /// Walk to `entrance` first (`distanceM` at `bearingDeg` true).
    struct Outside: Sendable, Hashable {
        let entrance: String
        let node: String
        let distanceM: Double
        let bearingDeg: Double
        let text: String

        var key: String { "o\(entrance)" }
    }

    /// Wayfinding node the walking graph starts from.
    var node: String {
        switch self {
        case .inside(let s): s.node
        case .outside(let s): s.node
        }
    }

    /// Text of the START step.
    var text: String {
        switch self {
        case .inside(let s): s.text
        case .outside(let s): s.text
        }
    }

    /// Changes when the start changes, so the screen knows to re-route (web: LV.key).
    var key: String {
        switch self {
        case .inside(let s): s.key
        case .outside(let s): s.key
        }
    }
}
