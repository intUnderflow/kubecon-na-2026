package app.kcna26.ui.directions

import app.kcna26.TestData
import app.kcna26.data.PointXY
import app.kcna26.geo.Geo
import app.kcna26.route.Router
import app.kcna26.settings.SettingsStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The From menu's order: nearest first with a fix, grouped like the web without one. */
class FromMenuTest {

    private val repo = TestData.repo
    private val options = FromOptions.from(Router(repo), repo.wayfinding)

    private fun at(lat: Double, lng: Double): PointXY = Geo.toLocal(lat, lng, repo.wayfinding.origin)

    /** test_vectors.json compass points. */
    private val sidewalk200South = at(40.76538, -111.89509)
    private val hyattLobby = at(40.765558, -111.894474)
    private val grandBallroomGI = at(40.76628, -111.89505)
    private val templeSquare = at(40.77005, -111.8917)

    /** The Utah State Capitol, about 1.1–1.5 km from the venue. */
    private val capitol = at(40.7774, -111.8882)

    private val allKeys: Set<String> = (options.entrances + options.rooms).map { it.key }.toSet()

    // ---------------------------------------------------------------- options

    @Test
    fun options_carryKindPositionAndLevel() {
        val e200s = options.entrances.first { it.key == "E200S" }
        assertEquals(FromKind.ENTRANCE, e200s.kind)
        assertEquals(PointXY(-92.0, 45.0), e200s.pos) // node S200
        assertEquals(1, e200s.level)
        assertEquals(2, options.entrances.first { it.key == "EWT" }.level) // the West Temple doors are on Level 2

        val r251 = options.rooms.first { it.key == "251AC" }
        assertEquals(FromKind.ROOM, r251.kind)
        assertEquals(PointXY(-73.0, 286.0), r251.pos)
        assertEquals(2, r251.level)

        assertEquals(FromKind.LIVE, options.live.kind)
        assertNull(options.live.pos)
        assertTrue(options.entrances.all { it.pos != null && it.level != null })
        assertTrue(options.rooms.all { it.pos != null && it.level != null })
    }

    // ---------------------------------------------------------------- nearest first

    @Test
    fun fixAt200South_200SouthFirst() {
        val menu = options.menu(sidewalk200South)
        assertTrue(menu.byDistance)
        assertEquals(SettingsStore.FROM_LIVE, menu.live.key)
        assertEquals(listOf(DirectionsText.NEAREST), menu.sections.map { it.title })
        val top = menu.items.take(12)
        assertEquals(
            listOf("E200S", "SLF", "RA", "SLC", "RB", "RBD", "EHY", "HL", "SLDE", "RCD", "PC", "CR"),
            top.map { it.key },
        )
        assertEquals(
            listOf("10 m", "30 m", "40 m", "50 m", "50 m", "50 m", "60 m", "60 m", "60 m", "60 m", "70 m", "70 m"),
            top.map { it.distance },
        )
        assertEquals(listOf("L1", "L2", "L4", "L2", "L4", "L4", "L1", "L1", "L2", "L4", "L3", "L5"), top.map { it.level })
        assertEquals("200 South entrance (badge pick-up)", top.first().option.label)
    }

    @Test
    fun fixOnThe200SouthEntranceNode_200SouthFirst() {
        val first = options.menu(PointXY(-92.0, 45.0)).items.first()
        assertEquals("E200S", first.key)
        assertEquals(0.0, first.distanceM!!, 1e-9)
        assertEquals("10 m", first.distance) // r10: never under 10 m, like the readout
    }

    @Test
    fun fixInTheGrandBallroom_nearestRoomsFirst() {
        val keys = options.menu(grandBallroomGI).items.take(5).map { it.key }
        assertEquals(listOf("H", "J", "BDF", "GI", "ACE"), keys)
    }

    @Test
    fun everyEntranceAndRoomOnce_inOneList() {
        for (p in listOf(sidewalk200South, hyattLobby, grandBallroomGI, templeSquare, capitol)) {
            val menu = options.menu(p)
            assertEquals(1, menu.sections.size)
            val keys = menu.items.map { it.key }
            assertEquals(41, keys.size)
            assertEquals(allKeys, keys.toSet())
            assertFalse(SettingsStore.FROM_LIVE in keys) // "My location" is apart, always first
            assertTrue(menu.items.all { it.distanceM != null && it.distance != null && it.level != null })
        }
    }

    @Test
    fun shownDistancesNeverDecrease() {
        for (p in listOf(sidewalk200South, hyattLobby, grandBallroomGI, templeSquare, capitol)) {
            val shown = options.menu(p).items.map { FromMenu.shownMetres(it.distanceM!!) }
            assertEquals(shown.sorted(), shown)
        }
    }

    @Test
    fun distancesAreStraightLineFromTheFix() {
        val item = options.menu(templeSquare).items.first { it.key == "EWT" }
        // test_vectors.json: the West Temple entrance is 386 m from Temple Square's south gate.
        assertEquals(386.0, item.distanceM!!, 3.0)
        assertEquals("390 m", item.distance)
        val room = options.menu(templeSquare).items.first { it.key == "251AC" }
        assertEquals(Geo.distance(templeSquare, PointXY(-73.0, 286.0)), room.distanceM!!, 1e-9)
    }

    @Test
    fun tiesBreakByLevelThenName() {
        // From the Hyatt lobby five options show "20 m". Regency Ballroom B is nearest (16 m) but
        // Salt Lake Ballroom C (L2) comes first; the three L4 ballrooms follow by name, then L5.
        val items = options.menu(hyattLobby).items
        val twenty = items.filter { it.distance == "20 m" }
        assertEquals(listOf("SLC", "RA", "RB", "RBD", "CR"), twenty.map { it.key })
        assertEquals(listOf("L2", "L4", "L4", "L4", "L5"), twenty.map { it.level })
        val rb = twenty.first { it.key == "RB" }
        assertTrue(twenty.all { it.distanceM!! >= rb.distanceM!! })

        // The Hyatt lobby is both an entrance and a room, at the same spot: the entrance first.
        assertEquals(listOf("EHY", "HL"), items.take(2).map { it.key })
        assertEquals(listOf(FromKind.ENTRANCE, FromKind.ROOM), items.take(2).map { it.option.kind })
    }

    @Test
    fun tiesBreakByLevelThenName_synthetic() {
        val o = FromOptions(
            entrances = listOf(FromOption("E", "Zeta doors", FromKind.ENTRANCE, PointXY(0.0, 41.0), 2)),
            rooms = listOf(
                FromOption("b", "Beta", FromKind.ROOM, PointXY(38.0, 0.0), 1),
                FromOption("a", "alpha", FromKind.ROOM, PointXY(0.0, -44.0), 1),
                FromOption("c", "Gamma", FromKind.ROOM, PointXY(-36.0, 0.0), 3),
                FromOption("n", "Near", FromKind.ROOM, PointXY(0.0, 20.0), 5),
            ),
        )
        val items = o.menu(PointXY(0.0, 0.0)).items
        // 20 m first; then the four "40 m" options: L1 by name (case-insensitive), then L2, then L3.
        assertEquals(listOf("n", "a", "b", "E", "c"), items.map { it.key })
        assertTrue(items.drop(1).all { it.distance == "40 m" })
    }

    @Test
    fun farAway_kilometres() {
        val items = options.menu(capitol).items
        assertEquals("255BC", items.first().key)
        assertEquals("1.1 km", items.first().distance)
        assertEquals("E200S", items.last().key)
        assertEquals("1.5 km", items.last().distance)
        assertTrue(items.all { it.distance!!.endsWith(" km") })
    }

    @Test
    fun distanceLabel_r10ThenKilometres() {
        assertEquals("10 m", FromMenu.distanceLabel(0.0))
        assertEquals("10 m", FromMenu.distanceLabel(14.9))
        assertEquals("20 m", FromMenu.distanceLabel(15.0))
        assertEquals("30 m", FromMenu.distanceLabel(34.0))
        assertEquals("40 m", FromMenu.distanceLabel(35.0)) // halves round up, like the web's Math.round
        assertEquals("120 m", FromMenu.distanceLabel(123.0))
        assertEquals("990 m", FromMenu.distanceLabel(994.9))
        assertEquals("1.0 km", FromMenu.distanceLabel(995.0))
        assertEquals("1.0 km", FromMenu.distanceLabel(1000.0))
        assertEquals("1.0 km", FromMenu.distanceLabel(1049.0))
        assertEquals("1.1 km", FromMenu.distanceLabel(1050.0))
        assertEquals("1.2 km", FromMenu.distanceLabel(1234.0))
        assertEquals("12.3 km", FromMenu.distanceLabel(12_345.0))
        assertEquals("7.0 km", FromMenu.distanceLabel(7_012.0))
        assertEquals("10 m", FromMenu.distanceLabel(Double.NaN)) // never throws
        assertEquals(990L, FromMenu.shownMetres(994.9))
        assertEquals(1200L, FromMenu.shownMetres(1234.0))
    }

    @Test
    fun levelLabel() {
        assertEquals("L1", FromMenu.levelLabel(1))
        assertEquals("L5", FromMenu.levelLabel(5))
        assertNull(FromMenu.levelLabel(null))
    }

    // ---------------------------------------------------------------- no fix

    @Test
    fun noFix_groupedLikeBefore() {
        for (menu in listOf(options.menu(null), options.menu(PointXY(Double.NaN, 3.0)), options.menu(PointXY(1.0, Double.POSITIVE_INFINITY)))) {
            assertFalse(menu.byDistance)
            assertEquals(SettingsStore.FROM_LIVE, menu.live.key)
            assertEquals(listOf(DirectionsText.ENTRANCES, DirectionsText.ROOMS), menu.sections.map { it.title })
            assertEquals(listOf("E200S", "EWT", "EHY", "E200W"), menu.sections[0].items.map { it.key })
            assertEquals(options.rooms, menu.sections[1].items.map { it.option }) // by name, as the engine lists them
            assertEquals(37, menu.sections[1].items.size)
            assertTrue(menu.items.all { it.distanceM == null && it.distance == null })
        }
        assertEquals("250 A–C", options.menu(null).sections[1].items.first().option.label)
    }

    // ---------------------------------------------------------------- exclusions

    @Test
    fun offAndRoomsWithoutAPositionAreLeftOut() {
        for (menu in listOf(options.menu(null), options.menu(sidewalk200South))) {
            val keys = menu.items.map { it.key }
            assertFalse("OFF" in keys)
            assertFalse("REG" in keys) // no sessions use them, so the web leaves them out too
            assertFalse("COAT" in keys)
        }

        val off = repo.room("OFF")!!
        assertFalse(off.hasPosition)
        val o = FromOptions(
            entrances = listOf(FromOption("E", "Doors", FromKind.ENTRANCE, PointXY(0.0, 0.0), 1)),
            rooms = listOf(
                FromOption(off.code, off.name, FromKind.ROOM, off.pos, off.level),
                FromOption("nan", "Broken", FromKind.ROOM, PointXY(Double.NaN, 0.0), 1),
                FromOption("r", "Room", FromKind.ROOM, PointXY(30.0, 0.0), 2),
            ),
        )
        assertEquals(listOf("E", "r"), o.menu(PointXY(0.0, 0.0)).items.map { it.key })
        assertEquals(listOf("E", "r"), o.menu(null).items.map { it.key })
    }

    @Test
    fun anEntranceWithoutAPositionStaysSelectable_atTheEnd() {
        val o = FromOptions(
            entrances = listOf(
                FromOption("lost", "Lost doors", FromKind.ENTRANCE, null, null),
                FromOption("E", "Doors", FromKind.ENTRANCE, PointXY(500.0, 0.0), 1),
            ),
            rooms = listOf(FromOption("r", "Room", FromKind.ROOM, PointXY(30.0, 0.0), 2)),
        )
        val items = o.menu(PointXY(0.0, 0.0)).items
        assertEquals(listOf("r", "E", "lost"), items.map { it.key })
        assertNull(items.last().distance)
        assertNull(items.last().level)
    }

    // ---------------------------------------------------------------- stability

    @Test
    fun sameFix_sameOrder_newFix_reSorted() {
        // The screen freezes the point when the menu opens; the same point always gives the same menu.
        assertEquals(options.menu(sidewalk200South), options.menu(sidewalk200South))
        val other = options.menu(grandBallroomGI).items.map { it.key }
        assertFalse(other == options.menu(sidewalk200South).items.map { it.key })
    }
}
