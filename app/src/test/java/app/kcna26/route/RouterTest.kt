package app.kcna26.route

import app.kcna26.TestData
import app.kcna26.data.PointXY
import app.kcna26.geo.Geo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class RouterTest {
    private val repo = TestData.repo
    private val router = Router(repo)
    private val way = repo.wayfinding

    private fun fromKey(key: String): RouteFrom =
        if (way.entrances.containsKey(key)) RouteFrom.Entrance(key) else RouteFrom.Room(key)

    private fun live(lat: Double, lng: Double): RouteFrom.MyLocation = router.myLocation(lat, lng, 10.0)

    // ---------------------------------------------------------------- test_vectors.json "routes"

    @Test
    fun allSevenTestRoutesMatchWordForWord() {
        val vectors = TestData.vectors.routes
        assertEquals(7, vectors.size)
        for (v in vectors) {
            val r = router.route(fromKey(v.from), v.to)
            assertNotNull("${v.from} → ${v.to}", r)
            r!!
            assertEquals("${v.from} → ${v.to} kinds", v.steps.map { it.kind }, r.steps.map { it.kind.wire })
            assertEquals("${v.from} → ${v.to} texts", v.steps.map { it.text }, r.steps.map { it.text })
            assertEquals("${v.from} → ${v.to} totalM", v.totalM, r.totalM, 1.0)
            assertEquals("${v.from} → ${v.to} levelsChanged", v.levelsChanged, r.levelsChanged)
            assertFalse(r.live)
            assertNull(r.start)
            assertEquals(Router.polylineLength(r.points), r.totalM, 1e-9)
        }
    }

    @Test
    fun mergedRunsUseStraightLineDistanceAndKeepIntermediateNodes() {
        // E200S → 251AC: S200 → LCS → LCM → NF merges into one step, measured S200 → NF (184 m → 180).
        val r = router.route(RouteFrom.Entrance("E200S"), "251AC")!!
        val n = way.nodes
        assertEquals(
            listOf(n["S200"]!!.pos, n["LCS"]!!.pos, n["LCM"]!!.pos, n["NF"]!!.pos, n["UC"]!!.pos, repo.room("251AC")!!.pos),
            r.points,
        )
        assertTrue(r.steps[1].text.endsWith(" About 180 m."))
        assertEquals(listOf(1, 1, 2, 2), r.steps.map { it.level })
        // 251AC → GI: NF → LCM → LCS heading south, measured NF → LCS (110 m), "where" of LCS.
        val g = router.route(RouteFrom.Room("251AC"), "GI")!!
        assertEquals(repo.room("251AC")!!.pos, g.points.first())
        assertEquals(n["UC"]!!.pos, g.points[1])
        assertEquals(listOf(n["NF"]!!.pos, n["LCM"]!!.pos, n["LCS"]!!.pos), g.points.subList(2, 5))
        assertTrue(g.steps[2].text.startsWith("Walk south down the Lower Concourse to the first Grand Ballroom doors."))
    }

    @Test
    fun singleConcourseLegUsesMergedWordingToo() {
        // E200S → DE is one S200 → LCS leg; the web still words it as a Lower Concourse walk.
        val r = router.route(RouteFrom.Entrance("E200S"), "DE")!!
        assertEquals(
            "Walk north up the Lower Concourse to the first Grand Ballroom doors. Hall DE and the showcase are on your left, the Grand Ballroom on your right. About 80 m.",
            r.steps[1].text,
        )
    }

    @Test
    fun stepKindsFollowLevelChangesAndSuffixOnlyOnLongSameLevelSteps() {
        for (from in router.startEntrances.map { RouteFrom.Entrance(it.key) } + router.startRooms.map { RouteFrom.Room(it.code) }) {
            for (room in router.startRooms) {
                val r = router.route(from, room.code) ?: error("no route $from → ${room.code}")
                var level = r.steps.first().level!!
                for (s in r.steps.drop(1).dropLast(1)) {
                    val now = s.level!!
                    val expected = when {
                        now > level -> StepKind.UP
                        now < level -> StepKind.DOWN
                        else -> StepKind.WALK
                    }
                    assertEquals("$from → ${room.code}: ${s.text}", expected, s.kind)
                    if (s.kind.changesLevel) assertFalse(s.text, s.text.contains(" About "))
                    level = now
                }
            }
        }
    }

    @Test
    fun startTexts() {
        assertEquals("Start at the Hyatt lobby.", router.route(RouteFrom.Entrance("EHY"), "RA")!!.steps.first().text)
        assertEquals("Start at Hall DE, then step out to the Lower Concourse.", router.route(RouteFrom.Room("DE"), "UC")!!.steps.first().text)
        // finalStep "You’re there: …" → "Start in the {node}."
        assertEquals("Start in the Upper Concourse.", router.route(RouteFrom.Room("UC"), "DE")!!.steps.first().text)
        assertEquals("Start in the Hyatt lobby.", router.route(RouteFrom.Room("HL"), "DE")!!.steps.first().text)
        assertEquals("Start in the North Foyer.", router.route(RouteFrom.Room("NGF"), "DE")!!.steps.first().text)
        assertEquals("Start in the Upper Mezzanine.", router.route(RouteFrom.Room("UM"), "DE")!!.steps.first().text)
    }

    @Test
    fun sameRoomIsASingleEndStep() {
        val r = router.route(RouteFrom.Room("251AC"), "251AC")!!
        assertEquals(listOf(Step(StepKind.END, "You’re already in this room.", 2)), r.steps)
        assertEquals(listOf(repo.room("251AC")!!.pos), r.points)
        assertEquals(0.0, r.totalM, 0.0)
        assertEquals(0, r.levelsChanged)
        assertEquals("", router.summary(r))
    }

    @Test
    fun sameAttachNodeHasNoWalkingSteps() {
        // 250AC and 251AC both open off UC.
        val r = router.route(RouteFrom.Room("250AC"), "251AC")!!
        assertEquals(listOf(StepKind.START, StepKind.END), r.steps.map { it.kind })
        assertEquals(3, r.points.size)
        val e = router.route(RouteFrom.Entrance("EHY"), "HL")!!
        assertEquals(listOf("Start at the Hyatt lobby.", "You’re there: this is the Hyatt lobby."), e.steps.map { it.text })
    }

    @Test
    fun levelsChangedIsSigned() {
        assertEquals(3, router.route(RouteFrom.Entrance("E200S"), "RA")!!.levelsChanged)
        assertEquals(-1, router.route(RouteFrom.Room("251AC"), "GI")!!.levelsChanged)
        assertEquals(-3, router.route(RouteFrom.Room("CR"), "SLC")!!.levelsChanged)
        assertEquals(0, router.route(RouteFrom.Room("SLC"), "251AC")!!.levelsChanged) // down and back up
        assertEquals(4, router.route(RouteFrom.Entrance("E200S"), "CR")!!.levelsChanged) // Level 5 − Level 1
    }

    // ---------------------------------------------------------------- reachability

    @Test
    fun everyRoomExceptOffIsReachableFromEveryEntranceAndRoom() {
        val rooms = repo.rooms.values.filter { it.code != "OFF" }
        assertEquals(39, rooms.size)
        val starts = way.entrances.keys.map { RouteFrom.Entrance(it) } + rooms.map { RouteFrom.Room(it.code) }
        for (from in starts) {
            for (to in rooms) {
                val r = router.route(from, to.code)
                assertNotNull("$from → ${to.code}", r)
                r!!
                assertEquals("$from → ${to.code}", StepKind.END, r.steps.last().kind)
                if (from is RouteFrom.Room && from.code == to.code) {
                    assertEquals(Router.ALREADY_HERE, r.steps.single().text)
                } else {
                    assertEquals("$from → ${to.code}", to.finalStep, r.steps.last().text)
                    assertEquals(StepKind.START, r.steps.first().kind)
                    // The walk really reaches the room's attach node.
                    assertEquals(way.nodes[to.attachNode]!!.pos, r.points[r.points.size - 2])
                }
                assertEquals(to.pos, r.points.last())
                val startLevel = when (from) {
                    is RouteFrom.Room -> if (from.code == to.code) to.level!! else repo.room(from.code)!!.level!!
                    is RouteFrom.Entrance -> way.nodes[way.entrances[from.key]!!.node]!!.level
                    is RouteFrom.MyLocation -> error("not used here")
                }
                assertEquals("$from → ${to.code}", to.level!! - startLevel, r.levelsChanged)
                assertTrue(r.totalM >= 0.0)
            }
        }
    }

    @Test
    fun offAndUnknownRoomsHaveNoRoute() {
        assertNull(router.route(RouteFrom.Entrance("E200S"), "OFF"))
        assertNull(router.route(RouteFrom.Entrance("E200S"), "NOPE"))
        assertNull(router.route(RouteFrom.MyLocation(-60.0, 250.0, 5.0), "OFF"))
        assertFalse(router.isRoutable("OFF"))
        assertTrue(router.isRoutable("251AC"))
    }

    @Test
    fun badStartsFallBackToTheBadgeEntrance() {
        val expected = router.route(RouteFrom.Entrance("E200S"), "251AC")
        assertEquals(expected, router.route(RouteFrom.Entrance("NOPE"), "251AC"))
        assertEquals(expected, router.route(RouteFrom.Room("OFF"), "251AC"))
        assertEquals(expected, router.route(RouteFrom.Room("NOPE"), "251AC"))
        val nan = router.route(RouteFrom.MyLocation(Double.NaN, 0.0, 5.0), "251AC")
        assertEquals(expected, nan)
        assertFalse(nan!!.live)
    }

    @Test
    fun graphAndRoomDataAreConsistent() {
        for (r in repo.rooms.values.filter { it.hasPosition }) {
            val node = way.nodes[r.attachNode]
            assertNotNull(r.code, node)
            assertEquals("${r.code} level = its attach node's", node!!.level, r.level)
            assertNotNull(r.code, r.finalStep)
        }
        for (e in way.edges) {
            assertTrue(e.a, way.nodes.containsKey(e.a))
            assertTrue(e.b, way.nodes.containsKey(e.b))
        }
        for (e in way.entrances.values) assertTrue(e.node, way.nodes.containsKey(e.node))
        // The prose rules in wayfinding.json carry the exact templates the router uses.
        val rules = way.routing
        assertTrue(rules.lowerConcourseMerge.rule.contains(Router.MERGE_NORTH))
        assertTrue(rules.lowerConcourseMerge.rule.contains(Router.MERGE_SOUTH))
        assertTrue(rules.startText.contains("'Start at the {entrance.name}.'"))
        assertTrue(rules.startText.contains("'Start at {room name}, then step out to the {node.name}.'"))
        assertTrue(rules.startText.contains("'${Router.YOURE_THERE}'"))
        assertTrue(rules.startText.contains("'Start in the {node.name}.'"))
        assertTrue(rules.algorithm.contains("+ 40 per level changed"))
        assertTrue(rules.distanceSuffix.contains("40 m or more"))
        assertEquals(listOf("S200", "LCS", "LCM", "NF"), rules.lowerConcourseMerge.nodes)
    }

    @Test
    fun dijkstraTakesTheCheapestPath() {
        val g = WalkGraph(way)
        val all = way.nodes.keys.map { g.indexOf(it)!! }
        // Brute-force check against Floyd–Warshall on the same costs.
        val n = g.size
        val d = Array(n) { i -> DoubleArray(n) { j -> if (i == j) 0.0 else Double.POSITIVE_INFINITY } }
        for (e in way.edges) {
            val a = g.indexOf(e.a)!!
            val b = g.indexOf(e.b)!!
            d[a][b] = g.cost(a, b); d[b][a] = g.cost(a, b)
        }
        for (k in 0 until n) for (i in 0 until n) for (j in 0 until n) if (d[i][k] + d[k][j] < d[i][j]) d[i][j] = d[i][k] + d[k][j]
        for (s in all) for (t in all) {
            val legs = g.path(s, t)!!
            assertEquals(d[s][t], legs.sumOf { g.cost(it.from, it.to) }, 1e-9)
            if (s == t) assertTrue(legs.isEmpty()) else {
                assertEquals(s, legs.first().from); assertEquals(t, legs.last().to)
                legs.zipWithNext().forEach { (a, b) -> assertEquals(a.to, b.from) }
            }
        }
        assertEquals(40.0, g.cost(g.indexOf("NF")!!, g.indexOf("UC")!!) - g.horizontal(g.indexOf("NF")!!, g.indexOf("UC")!!), 1e-9)
    }

    // ---------------------------------------------------------------- My location

    @Test
    fun myLocationStartVectors() {
        for (v in TestData.vectors.compass) {
            val p = Geo.toLocal(v.lat, v.lng, way.origin)
            val st = router.myLocationStart(p.x, p.y)
            val exp = v.myLocationStart
            assertEquals(v.where, exp.node, st.node)
            when (exp.mode) {
                "inside" -> {
                    assertTrue(v.where, st is StartPoint.Inside)
                    assertEquals(exp.node, st.key)
                }
                "outside" -> {
                    st as StartPoint.Outside
                    assertEquals(v.where, exp.entrance, st.entrance)
                    assertEquals(v.where, exp.distanceM!!, st.distanceM, 5.0)
                    assertTrue(v.where, abs(Geo.shortestTurn(st.bearingDeg, exp.bearingDeg!!)) <= 2.0)
                    assertEquals("o${exp.entrance}", st.key)
                }
                else -> error("mode ${exp.mode}")
            }
        }
    }

    @Test
    fun myLocationStartTexts() {
        // 200 South sidewalk: inside, near the 200 South entrance.
        val sidewalk = TestData.vectors.compass[0]
        val p = Geo.toLocal(sidewalk.lat, sidewalk.lng, way.origin)
        assertEquals(
            "Start from where you are, near the 200 South entrance (Level 1). GPS can’t tell floors apart; if that’s wrong, pick a room or entrance above.",
            router.myLocationStart(p.x, p.y).text,
        )
        // Temple Square: outside, head to the West Temple entrance.
        val temple = TestData.vectors.compass[1]
        val q = Geo.toLocal(temple.lat, temple.lng, way.origin)
        val st = router.myLocationStart(q.x, q.y) as StartPoint.Outside
        assertEquals(
            "Head to the West Temple entrance at 100 South, about 390 m south-west of you.",
            st.text,
        )
        // Spec: step 1 "Head to the {entrance}, about N m {direction}"
        assertTrue(st.text.startsWith("Head to the West Temple entrance at 100 South, about ${Geo.r10(st.distanceM)} m ${Geo.dir8(st.bearingDeg)}"))
    }

    @Test
    fun myLocationLevelPenaltyAndThreshold() {
        // Standing on UC (Level 2) picks UC, but 30% of the way towards NF (Level 1) the
        // 15 m/level penalty already prefers NF, although UC is still nearer in a straight line.
        val uc = way.nodes["UC"]!!
        val nf = way.nodes["NF"]!!
        assertEquals("UC", router.myLocationStart(uc.x, uc.y).node)
        val px = uc.x + 0.3 * (nf.x - uc.x)
        val py = uc.y + 0.3 * (nf.y - uc.y)
        assertTrue(Geo.distance(PointXY(px, py), uc.pos) < Geo.distance(PointXY(px, py), nf.pos))
        assertEquals("NF", router.myLocationStart(px, py).node)
        // Exactly 80 m from S200 (due south, nothing else nearer) is still inside; 80.5 m is outside.
        val s200 = way.nodes["S200"]!!
        assertEquals("S200", router.myLocationStart(s200.x, s200.y - 80.0).node)
        assertTrue(router.myLocationStart(s200.x, s200.y - 80.0) is StartPoint.Inside)
        assertTrue(router.myLocationStart(s200.x, s200.y - 80.5) is StartPoint.Outside)
    }

    @Test
    fun liveRoutes() {
        // Inside: 200 South sidewalk → 251AC starts at S200 and the polyline starts at the live position.
        val v = TestData.vectors.compass[0]
        val me = live(v.lat, v.lng)
        val r = router.route(me, "251AC")!!
        assertTrue(r.live)
        assertEquals(StartPoint.Inside::class, r.start!!::class)
        assertEquals(PointXY(me.x, me.y), r.points[0])
        assertEquals(way.nodes["S200"]!!.pos, r.points[1])
        assertEquals(router.myLocationStart(me.x, me.y).text, r.steps[0].text)
        assertEquals(StepKind.START, r.steps[0].kind)
        val fromEntrance = router.route(RouteFrom.Entrance("E200S"), "251AC")!!
        assertEquals(fromEntrance.steps.drop(1), r.steps.drop(1))
        assertEquals(fromEntrance.totalM + Geo.distance(r.points[0], r.points[1]), r.totalM, 1e-9)
        assertEquals(1, r.levelsChanged)
        // Outside: Temple Square starts with the walk to EWT.
        val t = TestData.vectors.compass[1]
        val o = router.route(live(t.lat, t.lng), "251AC")!!
        assertTrue(o.live)
        assertEquals("oEWT", o.start!!.key)
        assertTrue(o.steps[0].text.startsWith("Head to the West Temple entrance at 100 South"))
        assertEquals(0, o.levelsChanged) // EWT is on Level 2, like 251AC
        // Hyatt lobby → RA: start at HYL, up 3.
        val h = TestData.vectors.compass[2]
        val hr = router.route(live(h.lat, h.lng), "RA")!!
        assertEquals("HYL", hr.start!!.node)
        assertEquals(3, hr.levelsChanged)
        assertEquals(StepKind.UP, hr.steps[1].kind)
    }

    @Test
    fun fromSettingResolution() {
        val me = RouteFrom.MyLocation(-90.0, 50.0, 8.0)
        assertEquals(me, router.resolveFrom("LIVE", me))
        assertEquals(RouteFrom.Entrance("E200S"), router.resolveFrom("LIVE", null))
        assertEquals(RouteFrom.Entrance("E200S"), router.resolveFrom("LIVE", RouteFrom.MyLocation(Double.NaN, 1.0, 1.0)))
        assertEquals(RouteFrom.Entrance("EHY"), router.resolveFrom("EHY", me))
        assertEquals(RouteFrom.Room("DE"), router.resolveFrom("DE", me))
        assertEquals(RouteFrom.Entrance("E200S"), router.resolveFrom("OFF", me))
        assertEquals(RouteFrom.Entrance("E200S"), router.resolveFrom("garbage", me))
        // No fix yet: the web's fallback, a non-live route from the badge entrance.
        val waiting = router.routeFromSetting("LIVE", "251AC", null)!!
        assertFalse(waiting.live)
        assertEquals("Start at the 200 South entrance (badge pick-up).", waiting.steps.first().text)
        assertTrue(router.routeFromSetting("LIVE", "251AC", me)!!.live)
        assertTrue(router.isValidFrom("LIVE"))
        assertTrue(router.isValidFrom("EWT"))
        assertTrue(router.isValidFrom("255EF"))
        assertFalse(router.isValidFrom("OFF"))
        assertFalse(router.isValidFrom(""))
        assertEquals("LIVE", app.kcna26.settings.SettingsStore.FROM_LIVE)
        assertEquals(Router.FROM_LIVE, app.kcna26.settings.SettingsStore.FROM_LIVE)
    }

    @Test
    fun fromPickerOptionsMatchTheWeb() {
        assertEquals(listOf("E200S", "EWT", "EHY", "E200W"), router.startEntrances.map { it.key })
        assertEquals(
            listOf(
                "250 A–C", "250 D–F", "251 A–C", "251 D–F", "253 A", "253 B", "254", "255 A", "255 BC", "255 D", "255 EF",
                "Capitol Reef", "Cosmic Canyon stage, Hall 5", "Demo Theater, Hall 1", "Grand Ballroom ACE",
                "Grand Ballroom BDF", "Grand Ballroom GI", "Grand Ballroom H", "Grand Ballroom J", "Hall DE", "Hyatt lobby",
                "Network Nook, Hall 1", "North Grand Ballroom Foyer", "Park City", "Project Pavilion, Hall 5",
                "Regency Ballroom A", "Regency Ballroom B", "Regency Ballroom B–D", "Regency Ballroom CD", "Room 151",
                "Salt Lake Ballroom C", "Salt Lake Ballroom DE", "Salt Lake Foyer South", "Showcase halls",
                "Starlight Summit stage, Hall B", "Upper Concourse", "Upper Mezzanine",
            ),
            router.startRooms.map { it.name },
        )
    }

    // ---------------------------------------------------------------- summary

    @Test
    fun summaryFormatting() {
        fun route(m: Double, dl: Int) = Route(emptyList(), emptyList(), m, dl, false)
        assertEquals("About 250 m · 4 min · up 1 level", router.summary(router.route(RouteFrom.Entrance("E200S"), "251AC")!!))
        // 92 m, 3 levels: round(92·1.15/75 + 1.8) = round(3.21) = 3
        assertEquals("About 90 m · 3 min · up 3 levels", router.summary(router.route(RouteFrom.Entrance("E200S"), "RA")!!))
        assertEquals("About 310 m · 5 min", router.summary(router.route(RouteFrom.Entrance("EWT"), "255EF")!!))
        assertEquals("About 230 m · 4 min · down 1 level", router.summary(router.route(RouteFrom.Room("251AC"), "GI")!!))
        assertEquals("", router.summary(route(5.0, 0)))
        assertEquals("", router.summary(route(0.0, 2)))
        assertEquals("", router.summary(route(Double.NaN, 0)))
        assertEquals("About 10 m · 1 min", router.summary(route(5.1, 0)))
        assertEquals("About 40 m · 2 min · down 2 levels", router.summary(route(40.0, -2))) // 0.61 + 1.2 = 1.81 → 2
        // Minutes are at least 1, and level changes add 0.6 min each.
        assertEquals("About 1000 m · 15 min", router.summary(route(1000.0, 0))) // 15.33
        assertEquals("About 1000 m · 18 min · up 4 levels", router.summary(route(1000.0, 4))) // 17.73
        assertEquals("About 20 m · 2 min · up 2 levels", router.summary(route(20.0, 2))) // 0.31 + 1.2 = 1.51 → 2
        assertEquals("About 20 m · 1 min · up 1 level", router.summary(route(20.0, 1))) // 0.31 + 0.6 = 0.91 → 1
        assertEquals("About 70 m · 1 min", router.summary(route(65.0, 0))) // round(6.5) = 7 → 70; JS halves up
    }

    @Test
    fun aboutSuffix() {
        assertEquals("", Router.aboutSuffix(39.99))
        assertEquals(" About 40 m.", Router.aboutSuffix(40.0))
        assertEquals(" About 50 m.", Router.aboutSuffix(45.0))
        assertEquals(" About 180 m.", Router.aboutSuffix(184.3))
    }
}
