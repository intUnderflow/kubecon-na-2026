import Foundation
import XCTest
@testable import KCNA26Core

final class RouterTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var router = Router(repo)
    private var way: Wayfinding { repo.wayfinding }

    private func fromKey(_ key: String) -> RouteFrom {
        way.entrances.containsKey(key) ? .entrance(key) : .room(key)
    }

    private func live(_ lat: Double, _ lng: Double) -> RouteFrom.MyLocation { router.myLocation(lat, lng, 10.0) }

    /// Kotlin `assertEquals(List<String>, List<String>)`: the same UTF-16 units, not just
    /// canonically equivalent text.
    private func assertSameTexts(_ actual: [String], _ expected: [String], _ message: String, line: UInt = #line) {
        XCTAssertEqual(actual, expected, message, line: line)
        XCTAssertTrue(
            actual.count == expected.count && zip(actual, expected).allSatisfy { kotlinEquals($0, $1) },
            "\(message): not the same UTF-16 text", line: line
        )
    }

    // ---------------------------------------------------------------- test_vectors.json "routes"

    func testAllSevenTestRoutesMatchWordForWord() {
        let vectors = TestData.vectors.routes
        XCTAssertEqual(vectors.count, 7)
        for v in vectors {
            let r = router.route(fromKey(v.from), v.to)
            XCTAssertNotNil(r, "\(v.from) → \(v.to)")
            guard let r else { continue }
            XCTAssertEqual(r.steps.map(\.kind.wire), v.steps.map(\.kind), "\(v.from) → \(v.to) kinds")
            assertSameTexts(r.steps.map(\.text), v.steps.map(\.text), "\(v.from) → \(v.to) texts")
            XCTAssertEqual(r.totalM, v.totalM, accuracy: 1.0, "\(v.from) → \(v.to) totalM")
            XCTAssertEqual(r.levelsChanged, v.levelsChanged, "\(v.from) → \(v.to) levelsChanged")
            XCTAssertFalse(r.live)
            XCTAssertNil(r.start)
            XCTAssertEqual(r.totalM, Router.polylineLength(r.points), accuracy: 1e-9)
        }
    }

    func testMergedRunsUseStraightLineDistanceAndKeepIntermediateNodes() {
        // E200S → 251AC: S200 → LCS → LCM → NF merges into one step, measured S200 → NF (184 m → 180).
        let r = router.route(.entrance("E200S"), "251AC")!
        let n = way.nodes
        XCTAssertEqual(
            r.points,
            [n["S200"]!.pos, n["LCS"]!.pos, n["LCM"]!.pos, n["NF"]!.pos, n["UC"]!.pos, repo.room("251AC")!.pos!]
        )
        XCTAssertTrue(r.steps[1].text.kotlinEndsWith(" About 180 m."))
        XCTAssertEqual(r.steps.map(\.level), [1, 1, 2, 2])
        // 251AC → GI: NF → LCM → LCS heading south, measured NF → LCS (110 m), "where" of LCS.
        let g = router.route(.room("251AC"), "GI")!
        XCTAssertEqual(g.points.first, repo.room("251AC")!.pos)
        XCTAssertEqual(g.points[1], n["UC"]!.pos)
        XCTAssertEqual(Array(g.points[2..<5]), [n["NF"]!.pos, n["LCM"]!.pos, n["LCS"]!.pos])
        XCTAssertTrue(g.steps[2].text.kotlinStartsWith("Walk south down the Lower Concourse to the first Grand Ballroom doors."))
    }

    func testSingleConcourseLegUsesMergedWordingToo() {
        // E200S → DE is one S200 → LCS leg; the web still words it as a Lower Concourse walk.
        let r = router.route(.entrance("E200S"), "DE")!
        assertSameTexts(
            [r.steps[1].text],
            ["Walk north up the Lower Concourse to the first Grand Ballroom doors. Hall DE and the showcase are on your left, the Grand Ballroom on your right. About 80 m."],
            "E200S → DE"
        )
    }

    func testStepKindsFollowLevelChangesAndSuffixOnlyOnLongSameLevelSteps() {
        let starts: [RouteFrom] = router.startEntrances.map { .entrance($0.key) } + router.startRooms.map { .room($0.code) }
        for from in starts {
            for room in router.startRooms {
                guard let r = router.route(from, room.code) else {
                    XCTFail("no route \(from) → \(room.code)")
                    continue
                }
                var level = r.steps.first!.level!
                for s in r.steps.dropFirst().dropLast() {
                    let now = s.level!
                    let expected: StepKind = now > level ? .up : (now < level ? .down : .walk)
                    XCTAssertEqual(s.kind, expected, "\(from) → \(room.code): \(s.text)")
                    if s.kind.changesLevel { XCTAssertFalse(s.text.kotlinContains(" About "), s.text) }
                    level = now
                }
            }
        }
    }

    func testStartTexts() {
        XCTAssertEqual(router.route(.entrance("EHY"), "RA")!.steps.first!.text, "Start at the Hyatt lobby.")
        XCTAssertEqual(router.route(.room("DE"), "UC")!.steps.first!.text, "Start at Hall DE, then step out to the Lower Concourse.")
        // finalStep "You’re there: …" → "Start in the {node}."
        XCTAssertEqual(router.route(.room("UC"), "DE")!.steps.first!.text, "Start in the Upper Concourse.")
        XCTAssertEqual(router.route(.room("HL"), "DE")!.steps.first!.text, "Start in the Hyatt lobby.")
        XCTAssertEqual(router.route(.room("NGF"), "DE")!.steps.first!.text, "Start in the North Foyer.")
        XCTAssertEqual(router.route(.room("UM"), "DE")!.steps.first!.text, "Start in the Upper Mezzanine.")
    }

    func testSameRoomIsASingleEndStep() {
        let r = router.route(.room("251AC"), "251AC")!
        XCTAssertEqual(r.steps, [Step(.end, "You’re already in this room.", 2)])
        XCTAssertEqual(r.points, [repo.room("251AC")!.pos!])
        XCTAssertEqual(r.totalM, 0.0, accuracy: 0.0)
        XCTAssertEqual(r.levelsChanged, 0)
        XCTAssertEqual(router.summary(r), "")
    }

    func testSameAttachNodeHasNoWalkingSteps() {
        // 250AC and 251AC both open off UC.
        let r = router.route(.room("250AC"), "251AC")!
        XCTAssertEqual(r.steps.map(\.kind), [.start, .end])
        XCTAssertEqual(r.points.count, 3)
        let e = router.route(.entrance("EHY"), "HL")!
        assertSameTexts(e.steps.map(\.text), ["Start at the Hyatt lobby.", "You’re there: this is the Hyatt lobby."], "EHY → HL")
    }

    func testLevelsChangedIsSigned() {
        XCTAssertEqual(router.route(.entrance("E200S"), "RA")!.levelsChanged, 3)
        XCTAssertEqual(router.route(.room("251AC"), "GI")!.levelsChanged, -1)
        XCTAssertEqual(router.route(.room("CR"), "SLC")!.levelsChanged, -3)
        XCTAssertEqual(router.route(.room("SLC"), "251AC")!.levelsChanged, 0) // down and back up
        XCTAssertEqual(router.route(.entrance("E200S"), "CR")!.levelsChanged, 4) // Level 5 − Level 1
    }

    // ---------------------------------------------------------------- reachability

    func testEveryRoomExceptOffIsReachableFromEveryEntranceAndRoom() {
        let rooms = repo.rooms.values.filter { $0.code != "OFF" }
        XCTAssertEqual(rooms.count, 39)
        let starts: [RouteFrom] = way.entrances.keys.map { .entrance($0) } + rooms.map { .room($0.code) }
        for from in starts {
            for to in rooms {
                let r = router.route(from, to.code)
                XCTAssertNotNil(r, "\(from) → \(to.code)")
                guard let r else { continue }
                XCTAssertEqual(r.steps.last!.kind, .end, "\(from) → \(to.code)")
                if case .room(let code) = from, code == to.code {
                    XCTAssertEqual(r.steps.count, 1)
                    XCTAssertEqual(r.steps.first!.text, Router.ALREADY_HERE)
                } else {
                    XCTAssertEqual(r.steps.last!.text, to.finalStep, "\(from) → \(to.code)")
                    XCTAssertEqual(r.steps.first!.kind, .start)
                    // The walk really reaches the room's attach node.
                    XCTAssertEqual(r.points[r.points.count - 2], way.nodes[to.attachNode!]!.pos)
                }
                XCTAssertEqual(r.points.last, to.pos)
                let startLevel: Int
                switch from {
                case .room(let code): startLevel = code == to.code ? to.level! : repo.room(code)!.level!
                case .entrance(let key): startLevel = way.nodes[way.entrances[key]!.node]!.level
                case .myLocation: fatalError("not used here")
                }
                XCTAssertEqual(r.levelsChanged, to.level! - startLevel, "\(from) → \(to.code)")
                XCTAssertTrue(r.totalM >= 0.0)
            }
        }
    }

    func testOffAndUnknownRoomsHaveNoRoute() {
        XCTAssertNil(router.route(.entrance("E200S"), "OFF"))
        XCTAssertNil(router.route(.entrance("E200S"), "NOPE"))
        XCTAssertNil(router.route(.myLocation(-60.0, 250.0, 5.0), "OFF"))
        XCTAssertFalse(router.isRoutable("OFF"))
        XCTAssertTrue(router.isRoutable("251AC"))
    }

    func testBadStartsFallBackToTheBadgeEntrance() {
        let expected = router.route(.entrance("E200S"), "251AC")
        XCTAssertEqual(router.route(.entrance("NOPE"), "251AC"), expected)
        XCTAssertEqual(router.route(.room("OFF"), "251AC"), expected)
        XCTAssertEqual(router.route(.room("NOPE"), "251AC"), expected)
        let nan = router.route(.myLocation(Double.nan, 0.0, 5.0), "251AC")
        XCTAssertEqual(nan, expected)
        XCTAssertFalse(nan!.live)
    }

    func testGraphAndRoomDataAreConsistent() {
        for r in repo.rooms.values.filter({ $0.hasPosition }) {
            let node = r.attachNode.flatMap { way.nodes[$0] }
            XCTAssertNotNil(node, r.code)
            XCTAssertEqual(r.level, node?.level, "\(r.code) level = its attach node's")
            XCTAssertNotNil(r.finalStep, r.code)
        }
        for e in way.edges {
            XCTAssertTrue(way.nodes.containsKey(e.a), e.a)
            XCTAssertTrue(way.nodes.containsKey(e.b), e.b)
        }
        for e in way.entrances.values { XCTAssertTrue(way.nodes.containsKey(e.node), e.node) }
        // The prose rules in wayfinding.json carry the exact templates the router uses.
        let rules = way.routing
        XCTAssertTrue(rules.lowerConcourseMerge.rule.kotlinContains(Router.MERGE_NORTH))
        XCTAssertTrue(rules.lowerConcourseMerge.rule.kotlinContains(Router.MERGE_SOUTH))
        XCTAssertTrue(rules.startText.kotlinContains("'Start at the {entrance.name}.'"))
        XCTAssertTrue(rules.startText.kotlinContains("'Start at {room name}, then step out to the {node.name}.'"))
        XCTAssertTrue(rules.startText.kotlinContains("'\(Router.YOURE_THERE)'"))
        XCTAssertTrue(rules.startText.kotlinContains("'Start in the {node.name}.'"))
        XCTAssertTrue(rules.algorithm.kotlinContains("+ 40 per level changed"))
        XCTAssertTrue(rules.distanceSuffix.kotlinContains("40 m or more"))
        XCTAssertEqual(rules.lowerConcourseMerge.nodes, ["S200", "LCS", "LCM", "NF"])
    }

    func testDijkstraTakesTheCheapestPath() {
        let g = WalkGraph(way)
        let all = way.nodes.keys.map { g.indexOf($0)! }
        // Brute-force check against Floyd–Warshall on the same costs.
        let n = g.size
        var d = (0..<n).map { i in (0..<n).map { j in i == j ? 0.0 : Double.infinity } }
        for e in way.edges {
            let a = g.indexOf(e.a)!
            let b = g.indexOf(e.b)!
            d[a][b] = g.cost(a, b)
            d[b][a] = g.cost(a, b)
        }
        for k in 0..<n {
            for i in 0..<n {
                for j in 0..<n where d[i][k] + d[k][j] < d[i][j] { d[i][j] = d[i][k] + d[k][j] }
            }
        }
        for s in all {
            for t in all {
                let legs = g.path(s, t)!
                XCTAssertEqual(legs.reduce(0.0) { $0 + g.cost($1.from, $1.to) }, d[s][t], accuracy: 1e-9)
                if s == t {
                    XCTAssertTrue(legs.isEmpty)
                } else {
                    XCTAssertEqual(legs.first!.from, s)
                    XCTAssertEqual(legs.last!.to, t)
                    for (a, b) in legs.zipWithNext() { XCTAssertEqual(a.to, b.from) }
                }
            }
        }
        let nf = g.indexOf("NF")!, uc = g.indexOf("UC")!
        XCTAssertEqual(g.cost(nf, uc) - g.horizontal(nf, uc), 40.0, accuracy: 1e-9)
    }

    // ---------------------------------------------------------------- My location

    func testMyLocationStartVectors() {
        for v in TestData.vectors.compass {
            let p = Geo.toLocal(v.lat, v.lng, way.origin)
            let st = router.myLocationStart(p.x, p.y)
            let exp = v.myLocationStart
            XCTAssertEqual(st.node, exp.node, v.where)
            switch exp.mode {
            case "inside":
                guard case .inside = st else {
                    XCTFail(v.where)
                    continue
                }
                XCTAssertEqual(st.key, exp.node)
            case "outside":
                guard case .outside(let o) = st else {
                    XCTFail("\(v.where): \(st) is not Outside")
                    continue
                }
                XCTAssertEqual(o.entrance, exp.entrance, v.where)
                XCTAssertEqual(o.distanceM, exp.distanceM!, accuracy: 5.0, v.where)
                XCTAssertTrue(abs(Geo.shortestTurn(o.bearingDeg, exp.bearingDeg!)) <= 2.0, v.where)
                XCTAssertEqual(st.key, "o\(exp.entrance!)")
            default:
                XCTFail("mode \(exp.mode)")
            }
        }
    }

    func testMyLocationStartTexts() {
        // 200 South sidewalk: inside, near the 200 South entrance.
        let sidewalk = TestData.vectors.compass[0]
        let p = Geo.toLocal(sidewalk.lat, sidewalk.lng, way.origin)
        assertSameTexts(
            [router.myLocationStart(p.x, p.y).text],
            ["Start from where you are, near the 200 South entrance (Level 1). GPS can’t tell floors apart; if that’s wrong, pick a room or entrance above."],
            "sidewalk"
        )
        // Temple Square: outside, head to the West Temple entrance.
        let temple = TestData.vectors.compass[1]
        let q = Geo.toLocal(temple.lat, temple.lng, way.origin)
        guard case .outside(let st) = router.myLocationStart(q.x, q.y) else {
            XCTFail("Temple Square starts outside")
            return
        }
        XCTAssertEqual(st.text, "Head to the West Temple entrance at 100 South, about 390 m south-west of you.")
        // Spec: step 1 "Head to the {entrance}, about N m {direction}"
        XCTAssertTrue(st.text.kotlinStartsWith("Head to the West Temple entrance at 100 South, about \(Geo.r10(st.distanceM)) m \(Geo.dir8(st.bearingDeg))"))
    }

    func testMyLocationLevelPenaltyAndThreshold() {
        // Standing on UC (Level 2) picks UC, but 30% of the way towards NF (Level 1) the
        // 15 m/level penalty already prefers NF, although UC is still nearer in a straight line.
        let uc = way.nodes["UC"]!
        let nf = way.nodes["NF"]!
        XCTAssertEqual(router.myLocationStart(uc.x, uc.y).node, "UC")
        let px = uc.x + 0.3 * (nf.x - uc.x)
        let py = uc.y + 0.3 * (nf.y - uc.y)
        XCTAssertTrue(Geo.distance(PointXY(px, py), uc.pos) < Geo.distance(PointXY(px, py), nf.pos))
        XCTAssertEqual(router.myLocationStart(px, py).node, "NF")
        // Exactly 80 m from S200 (due south, nothing else nearer) is still inside; 80.5 m is outside.
        let s200 = way.nodes["S200"]!
        XCTAssertEqual(router.myLocationStart(s200.x, s200.y - 80.0).node, "S200")
        if case .inside = router.myLocationStart(s200.x, s200.y - 80.0) {} else { XCTFail("80 m is inside") }
        if case .outside = router.myLocationStart(s200.x, s200.y - 80.5) {} else { XCTFail("80.5 m is outside") }
    }

    func testLiveRoutes() {
        // Inside: 200 South sidewalk → 251AC starts at S200 and the polyline starts at the live position.
        let v = TestData.vectors.compass[0]
        let me = live(v.lat, v.lng)
        let r = router.route(.myLocation(me), "251AC")!
        XCTAssertTrue(r.live)
        if case .inside? = r.start {} else { XCTFail("\(String(describing: r.start)) is not Inside") }
        XCTAssertEqual(r.points[0], PointXY(me.x, me.y))
        XCTAssertEqual(r.points[1], way.nodes["S200"]!.pos)
        XCTAssertEqual(r.steps[0].text, router.myLocationStart(me.x, me.y).text)
        XCTAssertEqual(r.steps[0].kind, .start)
        let fromEntrance = router.route(.entrance("E200S"), "251AC")!
        XCTAssertEqual(Array(r.steps.dropFirst()), Array(fromEntrance.steps.dropFirst()))
        XCTAssertEqual(r.totalM, fromEntrance.totalM + Geo.distance(r.points[0], r.points[1]), accuracy: 1e-9)
        XCTAssertEqual(r.levelsChanged, 1)
        // Outside: Temple Square starts with the walk to EWT.
        let t = TestData.vectors.compass[1]
        let o = router.route(.myLocation(live(t.lat, t.lng)), "251AC")!
        XCTAssertTrue(o.live)
        XCTAssertEqual(o.start!.key, "oEWT")
        XCTAssertTrue(o.steps[0].text.kotlinStartsWith("Head to the West Temple entrance at 100 South"))
        XCTAssertEqual(o.levelsChanged, 0) // EWT is on Level 2, like 251AC
        // Hyatt lobby → RA: start at HYL, up 3.
        let h = TestData.vectors.compass[2]
        let hr = router.route(.myLocation(live(h.lat, h.lng)), "RA")!
        XCTAssertEqual(hr.start!.node, "HYL")
        XCTAssertEqual(hr.levelsChanged, 3)
        XCTAssertEqual(hr.steps[1].kind, .up)
    }

    func testFromSettingResolution() {
        let me = RouteFrom.MyLocation(-90.0, 50.0, 8.0)
        XCTAssertEqual(router.resolveFrom("LIVE", me), .myLocation(me))
        XCTAssertEqual(router.resolveFrom("LIVE", nil), .entrance("E200S"))
        XCTAssertEqual(router.resolveFrom("LIVE", RouteFrom.MyLocation(Double.nan, 1.0, 1.0)), .entrance("E200S"))
        XCTAssertEqual(router.resolveFrom("EHY", me), .entrance("EHY"))
        XCTAssertEqual(router.resolveFrom("DE", me), .room("DE"))
        XCTAssertEqual(router.resolveFrom("OFF", me), .entrance("E200S"))
        XCTAssertEqual(router.resolveFrom("garbage", me), .entrance("E200S"))
        // No fix yet: the web's fallback, a non-live route from the badge entrance.
        let waiting = router.routeFromSetting("LIVE", "251AC", nil)!
        XCTAssertFalse(waiting.live)
        XCTAssertEqual(waiting.steps.first!.text, "Start at the 200 South entrance (badge pick-up).")
        XCTAssertTrue(router.routeFromSetting("LIVE", "251AC", me)!.live)
        XCTAssertTrue(router.isValidFrom("LIVE"))
        XCTAssertTrue(router.isValidFrom("EWT"))
        XCTAssertTrue(router.isValidFrom("255EF"))
        XCTAssertFalse(router.isValidFrom("OFF"))
        XCTAssertFalse(router.isValidFrom(""))
        XCTAssertEqual(SettingsStore.FROM_LIVE, "LIVE")
        XCTAssertEqual(SettingsStore.FROM_LIVE, Router.FROM_LIVE)
    }

    func testFromPickerOptionsMatchTheWeb() {
        XCTAssertEqual(router.startEntrances.map(\.key), ["E200S", "EWT", "EHY", "E200W"])
        let expected: [String] = [
            "250 A–C", "250 D–F", "251 A–C", "251 D–F", "253 A", "253 B", "254", "255 A", "255 BC", "255 D", "255 EF",
            "Capitol Reef", "Cosmic Canyon stage, Hall 5", "Demo Theater, Hall 1", "Grand Ballroom ACE",
            "Grand Ballroom BDF", "Grand Ballroom GI", "Grand Ballroom H", "Grand Ballroom J", "Hall DE", "Hyatt lobby",
            "Network Nook, Hall 1", "North Grand Ballroom Foyer", "Park City", "Project Pavilion, Hall 5",
            "Regency Ballroom A", "Regency Ballroom B", "Regency Ballroom B–D", "Regency Ballroom CD", "Room 151",
            "Salt Lake Ballroom C", "Salt Lake Ballroom DE", "Salt Lake Foyer South", "Showcase halls",
            "Starlight Summit stage, Hall B", "Upper Concourse", "Upper Mezzanine",
        ]
        assertSameTexts(router.startRooms.map(\.name), expected, "startRooms")
    }

    // ---------------------------------------------------------------- summary

    func testSummaryFormatting() {
        func route(_ m: Double, _ dl: Int) -> Route { Route(steps: [], points: [], totalM: m, levelsChanged: dl, live: false) }
        XCTAssertEqual(router.summary(router.route(.entrance("E200S"), "251AC")!), "About 250 m · 4 min · up 1 level")
        // 92 m, 3 levels: round(92·1.15/75 + 1.8) = round(3.21) = 3
        XCTAssertEqual(router.summary(router.route(.entrance("E200S"), "RA")!), "About 90 m · 3 min · up 3 levels")
        XCTAssertEqual(router.summary(router.route(.entrance("EWT"), "255EF")!), "About 310 m · 5 min")
        XCTAssertEqual(router.summary(router.route(.room("251AC"), "GI")!), "About 230 m · 4 min · down 1 level")
        XCTAssertEqual(router.summary(route(5.0, 0)), "")
        XCTAssertEqual(router.summary(route(0.0, 2)), "")
        XCTAssertEqual(router.summary(route(Double.nan, 0)), "")
        XCTAssertEqual(router.summary(route(5.1, 0)), "About 10 m · 1 min")
        XCTAssertEqual(router.summary(route(40.0, -2)), "About 40 m · 2 min · down 2 levels") // 0.61 + 1.2 = 1.81 → 2
        // Minutes are at least 1, and level changes add 0.6 min each.
        XCTAssertEqual(router.summary(route(1000.0, 0)), "About 1000 m · 15 min") // 15.33
        XCTAssertEqual(router.summary(route(1000.0, 4)), "About 1000 m · 18 min · up 4 levels") // 17.73
        XCTAssertEqual(router.summary(route(20.0, 2)), "About 20 m · 2 min · up 2 levels") // 0.31 + 1.2 = 1.51 → 2
        XCTAssertEqual(router.summary(route(20.0, 1)), "About 20 m · 1 min · up 1 level") // 0.31 + 0.6 = 0.91 → 1
        XCTAssertEqual(router.summary(route(65.0, 0)), "About 70 m · 1 min") // round(6.5) = 7 → 70; JS halves up
    }

    func testAboutSuffix() {
        XCTAssertEqual(Router.aboutSuffix(39.99), "")
        XCTAssertEqual(Router.aboutSuffix(40.0), " About 40 m.")
        XCTAssertEqual(Router.aboutSuffix(45.0), " About 50 m.")
        XCTAssertEqual(Router.aboutSuffix(184.3), " About 180 m.")
    }
}
