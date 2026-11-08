package app.kcna26.route

import app.kcna26.TestData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FloorReminderTest {
    private val repo = TestData.repo
    private val router = Router(repo)

    private fun reminder(from: RouteFrom, to: String): FloorReminder {
        val room = repo.room(to)!!
        return FloorReminder.of(room, router.route(from, to))
    }

    @Test
    fun route251AC() {
        val f = reminder(RouteFrom.Entrance("E200S"), "251AC")
        assertEquals(FloorReminder(2, "Salt Palace", "251 A–C", "take the North Foyer escalator up", StepKind.UP, 1), f)
        assertEquals("Level 2 · Salt Palace · 251 A–C", f.headline)
        assertEquals("Room is on Level 2: take the North Foyer escalator up", f.instruction)
        assertEquals("Level 2", f.levelLabel)
        assertEquals("Salt Palace · 251 A–C", f.buildingAndRoom)
    }

    @Test
    fun routeRA() {
        val f = reminder(RouteFrom.Entrance("E200S"), "RA")
        assertEquals("Level 4 · Hyatt Regency · Regency Ballroom A", f.headline)
        assertEquals("Room is on Level 4: take the Hyatt escalators or an elevator up", f.instruction)
        assertEquals(StepKind.UP, f.direction)
        // The same from the live position in the Hyatt lobby (test vector).
        val v = TestData.vectors.compass[2]
        val live = FloorReminder.of(repo.room("RA")!!, router.route(router.myLocation(v.lat, v.lng, 12.0), "RA"))
        assertEquals(f, live)
    }

    @Test
    fun goingDown() {
        val f = reminder(RouteFrom.Room("251AC"), "GI")
        assertEquals("Room is on Level 1: take the escalator down to the North Foyer", f.instruction)
        assertEquals(StepKind.DOWN, f.direction)
        assertEquals("Level 1 · Salt Palace · Grand Ballroom GI", f.headline)
        assertEquals("Room is on Level 4: take a Hyatt elevator down", reminder(RouteFrom.Room("CR"), "RB").instruction)
        assertEquals("Room is on Level 1: take the Hyatt escalator down to the lobby", reminder(RouteFrom.Room("SLC"), "HL").instruction)
    }

    @Test
    fun noLevelChange() {
        // Level 1 room from street level.
        val de = reminder(RouteFrom.Entrance("E200S"), "DE")
        assertNull(de.action)
        assertNull(de.direction)
        assertEquals(0, de.hops)
        assertEquals("Room is on Level 1", de.instruction)
        assertEquals("Level 1 · Salt Palace · Hall DE", de.headline)
        // Already on the right level: the West Temple entrance is on Level 2.
        val ef = reminder(RouteFrom.Entrance("EWT"), "255EF")
        assertNull(ef.action)
        assertEquals("Room is on Level 2", ef.instruction)
        // Starting in the room itself.
        assertNull(reminder(RouteFrom.Room("RA"), "RA").action)
        // No route at all.
        assertEquals("Room is on Level 2", FloorReminder.of(repo.room("251AC")!!, null).instruction)
    }

    @Test
    fun multiHop() {
        // 200 South → Capitol Reef (Level 5): two hops up, joined.
        val cr = reminder(RouteFrom.Entrance("E200S"), "CR")
        assertEquals(
            "Room is on Level 5: take the Hyatt escalators or an elevator up, then take a Hyatt elevator up one level",
            cr.instruction,
        )
        assertEquals(2, cr.hops)
        // Capitol Reef → Salt Lake Ballroom C (Level 2): two hops down.
        val slc = reminder(RouteFrom.Room("CR"), "SLC")
        assertEquals("Room is on Level 2: take a Hyatt elevator down, then take the escalator down", slc.instruction)
        assertEquals(StepKind.DOWN, slc.direction)
        // Down then up (Park City → Regency A): only the hops that end on the room's level count.
        val ra = reminder(RouteFrom.Room("PC"), "RA")
        assertEquals("Room is on Level 4: take the Hyatt escalators or an elevator up", ra.instruction)
        assertEquals(1, ra.hops)
        // Hyatt Level 2 → Salt Palace Level 2: same level overall, but you go down and back up.
        val sp = reminder(RouteFrom.Room("SLC"), "251AC")
        assertEquals(0, router.route(RouteFrom.Room("SLC"), "251AC")!!.levelsChanged)
        assertEquals("Room is on Level 2: take the North Foyer escalator up", sp.instruction)
    }

    @Test
    fun offSiteAndHyattLobby() {
        val off = FloorReminder.of(repo.room("OFF")!!, null)
        assertNull(off.level)
        assertNull(off.building)
        assertNull(off.instruction)
        assertEquals("Off-site", off.headline)
        val hl = FloorReminder.of(repo.room("HL")!!, router.route(RouteFrom.Entrance("E200S"), "HL"))
        assertEquals("Level 1 · Hyatt Regency · Hyatt lobby", hl.headline)
        assertEquals("Room is on Level 1", hl.instruction)
    }

    @Test
    fun actionFromEveryUpDownEdgeText() {
        val expected = mapOf(
            "Take the North Foyer escalator up to Level 2. You arrive on the Upper Concourse." to "take the North Foyer escalator up",
            "Take the escalator down to the North Foyer on Level 1." to "take the escalator down to the North Foyer",
            "Take the escalator by Rooms 155 up to Level 2. You arrive on the Upper Mezzanine." to "take the escalator by Rooms 155 up",
            "Take the escalator by Rooms 255 down to Level 1, by the Secondary Entrance." to "take the escalator by Rooms 255 down, by the Secondary Entrance",
            "Take the Hyatt escalator up to Level 2." to "take the Hyatt escalator up",
            "Take the Hyatt escalator down to the lobby." to "take the Hyatt escalator down to the lobby",
            "Take a Hyatt elevator up to Level 3." to "take a Hyatt elevator up",
            "Take a Hyatt elevator down to the lobby." to "take a Hyatt elevator down to the lobby",
            "Take the escalator up two more levels to Level 4. You arrive in the Regency Foyer." to "take the escalator up two more levels",
            "Take the escalator down to Level 2." to "take the escalator down",
            "Take the Hyatt escalators or an elevator up to Level 4. You arrive in the Regency Foyer." to "take the Hyatt escalators or an elevator up",
            "Take the escalators or an elevator down to the Hyatt lobby." to "take the escalators or an elevator down to the Hyatt lobby",
            "Take a Hyatt elevator up one level to Level 5." to "take a Hyatt elevator up one level",
            "Take a Hyatt elevator down to Level 4." to "take a Hyatt elevator down",
        )
        // Every level-changing edge text in wayfinding.json is covered.
        val nodes = repo.wayfinding.nodes
        val texts = repo.wayfinding.edges.filter { nodes[it.a]!!.level != nodes[it.b]!!.level }.flatMap { listOf(it.textAB, it.textBA) }
        assertEquals(expected.keys, texts.toSet())
        for ((text, action) in expected) assertEquals(text, action, FloorReminder.actionOf(text))
        assertNull(FloorReminder.actionOf(""))
        assertNull(FloorReminder.actionOf(" . "))
        assertEquals("go up", FloorReminder.actionOf("Go up"))
    }

    @Test
    fun everyRouteGivesAReminderThatEndsOnTheRoomsLevel() {
        for (from in router.startEntrances.map { RouteFrom.Entrance(it.key) } + router.startRooms.map { RouteFrom.Room(it.code) }) {
            for (room in router.startRooms) {
                val route = router.route(from, room.code)!!
                val f = FloorReminder.of(room, route)
                assertEquals(room.level, f.level)
                assertNotNull(f.instruction)
                val changes = route.steps.any { it.kind.changesLevel }
                assertEquals("$from → ${room.code}", changes, f.action != null)
                f.action?.let {
                    assertTrue(it, it.first().isLowerCase())
                    assertTrue(it, !it.endsWith("."))
                    assertTrue(it, !it.contains("Level ${room.level}"))
                }
            }
        }
    }
}
