package app.kcna26.ui.directions

import app.kcna26.TestData
import app.kcna26.geo.Geo
import app.kcna26.route.FloorReminder
import app.kcna26.route.RouteFrom
import app.kcna26.route.Router
import app.kcna26.route.StepKind
import app.kcna26.settings.SettingsStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectionsLogicTest {

    private val repo = TestData.repo
    private val room251 = repo.room("251AC")!!
    private val target = room251.pos!!
    private val router = Router(repo)
    private val planner = RoutePlanner(router, FromOptions.from(router, repo.wayfinding))
    private val outside = TestData.vectors.compass.first().let {
        val p = Geo.toLocal(it.lat, it.lng, repo.wayfinding.origin)
        Fix(it.lat, it.lng, p.x, p.y, 8.0)
    }

    /** A fix [dist] metres due south of the room. */
    private fun southOf(dist: Double, acc: Double) = Fix(0.0, 0.0, target.x, target.y - dist, acc)

    // ---------------------------------------------------------------- readout

    @Test
    fun noFix_textsPerState() {
        val searching = DirectionsLogic.readout(target, 2, null, LocStatus.SEARCHING)
        assertEquals("Finding you…", searching.headline)
        assertEquals("Finding you…", searching.line)
        assertEquals("Hold on a moment.", searching.detail)
        assertFalse(searching.hasFix)
        assertNull(searching.accuracy)

        val noFix = DirectionsLogic.readout(target, 2, null, LocStatus.NO_FIX)
        assertEquals("No GPS fix yet", noFix.headline)
        assertEquals("Indoors this can take a minute. A window or doorway helps.", noFix.detail)

        val denied = DirectionsLogic.readout(target, 2, null, LocStatus.PERMISSION_DENIED)
        assertEquals("Location is off", denied.headline)
        assertEquals("Allow location for this app in Android Settings to see distance and direction.", denied.detail)

        val deviceOff = DirectionsLogic.readout(target, 2, null, LocStatus.DEVICE_OFF)
        assertEquals("Location is off", deviceOff.headline)
        assertNull(deviceOff.distance)
    }

    @Test
    fun farAway_distanceDirectionAccuracy() {
        val r = DirectionsLogic.readout(target, 2, southOf(123.0, 12.4), LocStatus.SEARCHING)
        assertEquals("120 m north", r.headline)
        assertEquals("120 m north · ±12 m", r.line)
        assertEquals("120 m", r.distance)
        assertEquals("north", r.direction)
        assertEquals("±12 m", r.accuracy)
        assertTrue(r.hasFix)
        // No compass-arrow sentence any more: the floor instruction and the map say the rest.
        assertNull(r.detail)
        assertNull(r.weakGps)
        assertFalse(r.here)
    }

    @Test
    fun northEastExample() {
        // 120 m away at a bearing of 45°: the redesign's "120 m north-east · ±12 m".
        val d = 120.0 / Math.sqrt(2.0)
        val fix = Fix(0.0, 0.0, target.x - d, target.y - d, 12.0)
        val r = DirectionsLogic.readout(target, 2, fix, LocStatus.SEARCHING)
        assertEquals("120 m north-east", r.headline)
        assertEquals("±12 m", r.accuracy)
        assertEquals("120 m north-east · ±12 m", r.line)
    }

    @Test
    fun here_withinMax15mOr60PercentOfAccuracy() {
        val r = DirectionsLogic.readout(target, 2, southOf(14.0, 10.0), LocStatus.SEARCHING)
        assertTrue(r.here)
        assertEquals("You’re about here", r.headline)
        assertEquals("You’re about here · ±10 m", r.line)
        assertEquals("The room is on Level 2; the steps below get you to the right floor.", r.detail)
        assertNull(r.distance)
        assertEquals("±10 m", r.accuracy)

        assertFalse(DirectionsLogic.readout(target, 2, southOf(16.0, 10.0), LocStatus.SEARCHING).here)
        // 0.6 × 40 m = 24 m.
        assertTrue(DirectionsLogic.readout(target, 2, southOf(20.0, 40.0), LocStatus.SEARCHING).here)
        assertFalse(DirectionsLogic.readout(target, 2, southOf(25.0, 40.0), LocStatus.SEARCHING).here)
    }

    @Test
    fun weakGps_above50m() {
        assertNull(DirectionsLogic.readout(target, 2, southOf(200.0, 50.0), LocStatus.SEARCHING).weakGps)
        val weak = DirectionsLogic.readout(target, 2, southOf(200.0, 65.0), LocStatus.SEARCHING)
        assertEquals("GPS is weak indoors: follow the steps.", weak.weakGps)
        assertEquals("±65 m", weak.accuracy)
    }

    @Test
    fun accuracyRounding() {
        assertEquals("±12 m", DirectionsLogic.accuracyText(12.4))
        assertEquals("±13 m", DirectionsLogic.accuracyText(12.5))
        assertEquals("±0 m", DirectionsLogic.accuracyText(-1.0))
    }

    @Test
    fun readoutDistancesFromTheTestVectors() {
        for (v in TestData.vectors.compass) {
            val room = repo.room(v.room)!!
            val p = Geo.toLocal(v.lat, v.lng, repo.wayfinding.origin)
            val r = DirectionsLogic.readout(room.pos!!, room.level!!, Fix(v.lat, v.lng, p.x, p.y, 10.0), LocStatus.SEARCHING)
            val expected = Geo.r10(v.expectDistanceM)
            val shown = r.distance!!.removeSuffix(" m").toInt()
            assertTrue("${v.where}: $shown vs $expected", kotlin.math.abs(shown - expected) <= 10)
        }
    }

    @Test
    fun noArrowOrGoogleMapsWording() {
        val texts = listOf(
            DirectionsLogic.readout(target, 2, null, LocStatus.SEARCHING),
            DirectionsLogic.readout(target, 2, southOf(123.0, 12.0), LocStatus.SEARCHING),
            DirectionsLogic.readout(target, 2, southOf(5.0, 12.0), LocStatus.SEARCHING),
            DirectionsLogic.readout(target, 2, southOf(300.0, 80.0), LocStatus.SEARCHING),
        ).flatMap { listOfNotNull(it.line, it.detail, it.weakGps) } +
            listOf(DirectionsText.MAP_NOTE, DirectionsText.REFIT, DirectionsText.mapDescription("SP", 2))
        for (t in texts) {
            assertFalse(t, t.contains("Arrow", ignoreCase = true))
            assertFalse(t, t.contains("Google", ignoreCase = true))
        }
        assertEquals("Map: destination on Hyatt level 4", DirectionsText.mapDescription("HY", 4))
    }

    // ---------------------------------------------------------------- floor (engine's FloorReminder)

    @Test
    fun floorReminder_promptExample() {
        // Spec: "Level 2 · Salt Palace · 251 A–C" and "Room is on Level 2: take the North Foyer escalator up".
        val r = router.route(RouteFrom.Entrance("E200S"), "251AC")
        val f = FloorReminder.of(room251, r)
        assertEquals("Level 2 · Salt Palace · 251 A–C", f.headline)
        assertEquals("Level 2", f.levelLabel)
        assertEquals("Salt Palace · 251 A–C", f.buildingAndRoom)
        assertEquals("Room is on Level 2: take the North Foyer escalator up", f.instruction)
        assertEquals(StepKind.UP, f.direction)
    }

    @Test
    fun floorReminder_withoutALevelChange() {
        // From the West Temple entrance you come in on Level 2 already.
        val f = FloorReminder.of(room251, router.route(RouteFrom.Entrance("EWT"), "251AC"))
        assertEquals("Room is on Level 2", f.instruction)
        assertNull(f.direction)
    }

    @Test
    fun floorReminder_followsTheLivePlan() {
        val p = planner.plan("LIVE", "RA", outside)
        val f = FloorReminder.of(repo.room("RA")!!, p.route)
        assertEquals("Level 4 · Hyatt Regency · Regency Ballroom A", f.headline)
        assertTrue(f.instruction!!.startsWith("Room is on Level 4"))
    }

    // ---------------------------------------------------------------- From picker

    @Test
    fun fromOptions_likeTheWeb() {
        val o = FromOptions.from(router, repo.wayfinding)
        assertEquals(SettingsStore.FROM_LIVE, o.live.key)
        assertEquals("My location (GPS)", o.live.label)
        assertEquals(listOf("E200S", "EWT", "EHY", "E200W"), o.entrances.map { it.key })
        assertEquals("200 South entrance (badge pick-up)", o.label("E200S"))
        assertEquals("Hyatt lobby", o.label("EHY"))
        // Sorted with String.localeCompare in the web; checked against node's output.
        val expected = listOf(
            "250 A–C", "250 D–F", "251 A–C", "251 D–F", "253 A", "253 B", "254", "255 A", "255 BC", "255 D",
            "255 EF", "Capitol Reef", "Cosmic Canyon stage, Hall 5", "Demo Theater, Hall 1", "Grand Ballroom ACE",
            "Grand Ballroom BDF", "Grand Ballroom GI", "Grand Ballroom H", "Grand Ballroom J", "Hall DE",
            "Hyatt lobby", "Network Nook, Hall 1", "North Grand Ballroom Foyer", "Park City",
            "Project Pavilion, Hall 5", "Regency Ballroom A", "Regency Ballroom B", "Regency Ballroom B–D",
            "Regency Ballroom CD", "Room 151", "Salt Lake Ballroom C", "Salt Lake Ballroom DE",
            "Salt Lake Foyer South", "Showcase halls", "Starlight Summit stage, Hall B", "Upper Concourse",
            "Upper Mezzanine",
        )
        assertEquals(expected, o.rooms.map { it.label })
        val codes = o.rooms.map { it.key }.toSet()
        assertFalse("OFF" in codes)
        assertFalse("REG" in codes)
        assertFalse("COAT" in codes)
    }

    @Test
    fun fromValidation() {
        val o = FromOptions.from(router, repo.wayfinding)
        assertEquals("LIVE", o.validate("LIVE"))
        assertEquals("EWT", o.validate("EWT"))
        assertEquals("251AC", o.validate("251AC"))
        assertEquals("E200S", o.validate("REG"))
        assertEquals("E200S", o.validate("OFF"))
        assertEquals("E200S", o.validate("nope"))
    }

    // ---------------------------------------------------------------- route plan


    @Test
    fun routeFrom_mapping() {
        assertEquals(RouteFrom.Entrance("E200S"), planner.routeFrom("LIVE", null))
        assertEquals(RouteFrom.MyLocation(outside.x, outside.y, 8.0), planner.routeFrom("LIVE", outside))
        assertEquals(RouteFrom.Entrance("EHY"), planner.routeFrom("EHY", outside))
        assertEquals(RouteFrom.Room("DE"), planner.routeFrom("DE", outside))
    }

    @Test
    fun plan_myLocationWithoutAFix_fallsBackTo200South() {
        val p = planner.plan("LIVE", "251AC", null)
        assertEquals("LIVE", p.from)
        assertTrue(p.showFallbackNote)
        assertFalse(p.route!!.live)
        assertNull(p.startKey)
    }

    @Test
    fun plan_myLocationWithAFix_isLive() {
        val p = planner.plan("LIVE", "251AC", outside)
        assertTrue(p.route!!.live)
        assertFalse(p.showFallbackNote)
        assertEquals(router.myLocationStart(outside.x, outside.y).key, p.startKey)
    }

    @Test
    fun plan_entranceAndInvalidFrom() {
        val ewt = planner.plan("EWT", "255EF", outside)
        assertEquals("EWT", ewt.from)
        assertFalse(ewt.route!!.live)
        assertFalse(ewt.showFallbackNote)
        assertEquals("E200S", planner.plan("REG", "251AC", null).from)
        assertNull(planner.plan("LIVE", "OFF", outside).route)
    }

    @Test
    fun planKey_onlyChangesWithTheStartPoint() {
        assertEquals("EWT", planner.planKey("EWT", outside))
        assertEquals("E200S", planner.planKey("bogus", outside))
        assertEquals("LIVE:none", planner.planKey("LIVE", null))
        val a = planner.planKey("LIVE", outside)
        val b = planner.planKey("LIVE", outside.copy(x = outside.x + 1.0))
        assertEquals(a, b)
        assertNotEquals("LIVE:none", a)
    }

}
