package app.kcna26.geo

import app.kcna26.TestData
import app.kcna26.data.PointXY
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.random.Random

class GeoTest {
    private val repo = TestData.repo
    private val origin = repo.wayfinding.origin

    private fun angleDiff(a: Double, b: Double): Double = abs(Geo.shortestTurn(a, b))

    // ---------------------------------------------------------------- test_vectors.json "compass"

    @Test
    fun compassVectorsDistanceAndBearing() {
        val vectors = TestData.vectors.compass
        assertEquals(4, vectors.size)
        for (v in vectors) {
            val room = repo.room(v.room)
            assertNotNull(v.where, room)
            room!!
            assertEquals(v.where, v.roomLevel, room.level)
            val me = Geo.toLocal(v.lat, v.lng, origin)
            val dest = room.pos!!
            assertEquals("${v.where}: distance", v.expectDistanceM, Geo.distance(me, dest), 3.0)
            val b = Geo.bearing(me, dest)
            assertTrue("${v.where}: bearing $b vs ${v.expectBearingTrueDeg}", angleDiff(b, v.expectBearingTrueDeg) <= 2.0)
        }
    }

    @Test
    fun toLocalUsesWayfindingOrigin() {
        assertEquals(84300.0, origin.metersPerDegLon, 0.0)
        assertEquals(111000.0, origin.metersPerDegLat, 0.0)
        val p = Geo.toLocal(origin.lat0 + 0.001, origin.lon0 - 0.001, origin)
        assertEquals(-84.3, p.x, 1e-9)
        assertEquals(111.0, p.y, 1e-9)
        // rooms.json x/y agree with their lat/lng under this formula (to the rounding of x/y).
        for (r in repo.rooms.values.filter { it.hasPosition }) {
            val q = Geo.toLocal(r.lat!!, r.lng!!, origin)
            assertEquals(r.code, r.x!!, q.x, 1.5)
            assertEquals(r.code, r.y!!, q.y, 1.5)
        }
    }

    @Test
    fun bearingIsTrueAndInRange() {
        val o = PointXY(0.0, 0.0)
        assertEquals(0.0, Geo.bearing(o, PointXY(0.0, 10.0)), 1e-9)
        assertEquals(90.0, Geo.bearing(o, PointXY(10.0, 0.0)), 1e-9)
        assertEquals(180.0, Geo.bearing(o, PointXY(0.0, -10.0)), 1e-9)
        assertEquals(270.0, Geo.bearing(o, PointXY(-10.0, 0.0)), 1e-9)
        assertEquals(45.0, Geo.bearing(o, PointXY(5.0, 5.0)), 1e-9)
        assertEquals(0.0, Geo.bearing(o, o), 0.0) // same point: north, not NaN
        val rnd = Random(7)
        repeat(2000) {
            val b = Geo.bearing(PointXY(rnd.nextDouble(-500.0, 500.0), rnd.nextDouble(-500.0, 500.0)),
                PointXY(rnd.nextDouble(-500.0, 500.0), rnd.nextDouble(-500.0, 500.0)))
            assertTrue("$b", b >= 0.0 && b < 360.0)
        }
        assertEquals(5.0, Geo.distance(PointXY(1.0, 1.0), PointXY(4.0, 5.0)), 1e-12)
    }

    // ---------------------------------------------------------------- dir8, r10

    @Test
    fun dir8Words() {
        val words = listOf("north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west")
        words.forEachIndexed { i, w -> assertEquals(w, Geo.dir8(i * 45.0)) }
        assertEquals("north", Geo.dir8(22.4))
        assertEquals("north-east", Geo.dir8(22.5)) // JS Math.round rounds halves up
        assertEquals("north-east", Geo.dir8(67.4))
        assertEquals("east", Geo.dir8(67.5))
        assertEquals("north-west", Geo.dir8(337.4))
        assertEquals("north", Geo.dir8(337.5)) // round(7.5) = 8, % 8 = 0
        assertEquals("north", Geo.dir8(359.9))
        assertEquals("north", Geo.dir8(360.0))
        assertEquals("east", Geo.dir8(450.0))
        assertEquals("north-west", Geo.dir8(-45.0))
        assertEquals("north", Geo.dir8(Double.NaN)) // never throws
        assertEquals("south-west", Geo.dir8(214.0)) // test vector: EWT from Temple Square
    }

    @Test
    fun r10Rounding() {
        assertEquals(10, Geo.r10(0.0))
        assertEquals(10, Geo.r10(3.0))
        assertEquals(10, Geo.r10(14.9))
        assertEquals(20, Geo.r10(15.0)) // halves round up, like Math.round
        assertEquals(20, Geo.r10(24.99))
        assertEquals(380, Geo.r10(383.0))
        assertEquals(390, Geo.r10(386.0))
        assertEquals(10, Geo.r10(-50.0))
        assertEquals(10, Geo.r10(Double.NaN)) // never throws
        assertEquals(0L, Geo.round10(4.0))
        assertEquals(250L, Geo.round10(253.6))
        assertEquals(180L, Geo.round10(184.3))
        assertEquals("120 m north-east", Geo.distanceLabel(118.0, 40.0))
        assertEquals("10 m north", Geo.distanceLabel(2.0, 0.0))
    }

    @Test
    fun hereRadius() {
        assertEquals(15.0, Geo.hereRadius(5.0), 0.0)
        assertEquals(15.0, Geo.hereRadius(25.0), 0.0)
        assertEquals(30.0, Geo.hereRadius(50.0), 1e-9)
        assertTrue(Geo.isAboutHere(14.9, 0.0))
        assertFalse(Geo.isAboutHere(15.0, 0.0)) // strict <, as in the web
        assertTrue(Geo.isAboutHere(29.0, 50.0))
        assertFalse(Geo.isAboutHere(10.0, Double.NaN))
    }

    // ---------------------------------------------------------------- heading and arrow

    @Test
    fun trueHeadingAddsDeclination() {
        assertEquals(10.0, Geo.trueHeading(0.0, 10.0), 1e-9)
        assertEquals(5.0, Geo.trueHeading(355.0, 10.0), 1e-9)
        assertEquals(350.0, Geo.trueHeading(-20.0, 10.0), 1e-9)
        assertEquals(0.0, Geo.trueHeading(350.0, 10.0), 1e-9)
        assertEquals(359.0, Geo.trueHeading(1.0, -2.0), 1e-9)
        assertTrue(Geo.declinationDeg(40.767, -111.895, 1300.0, 1_794_000_000_000L).isFinite())
    }

    @Test
    fun arrowRotationVectors() {
        val vectors = TestData.vectors.arrowRotation
        assertEquals(3, vectors.size)
        for (v in vectors) {
            val a = Geo.arrowDeg(v.trueHeadingDeg, v.bearingDeg)
            assertTrue("arrowDeg $a", a >= 0.0 && a < 360.0)
            assertEquals("arrowDeg $v", 0.0, Geo.shortestTurn(a, v.arrowDeg), 1e-9) // mod-360 equivalent

            // From an arrow at rest pointing up, the accumulator turns the short way.
            val acc = ArrowRotation()
            val value = acc.update(v.bearingDeg - v.trueHeadingDeg)
            assertEquals("accumulated $v", 0.0, Geo.shortestTurn(value, v.arrowDeg), 1e-9)
            assertTrue("delta ${acc.lastDelta} for $v", abs(acc.lastDelta) <= 180.0)
            assertEquals(value, acc.value, 0.0)
        }
        // Exact values: 45, −135 (≡ 225), and +20 (not −340).
        assertEquals(45.0, ArrowRotation().update(45.0 - 0.0), 1e-9)
        assertEquals(-135.0, ArrowRotation().update(315.0 - 90.0), 1e-9)
        assertEquals(20.0, ArrowRotation().update(10.0 - 350.0), 1e-9)
        assertEquals(20.0, ArrowRotation().update(Geo.arrowDeg(350.0, 10.0)), 1e-9)
    }

    @Test
    fun arrowRotationAlwaysTurnsTheShortWay() {
        val rnd = Random(42)
        val acc = ArrowRotation(rnd.nextDouble(-720.0, 720.0))
        repeat(5000) {
            val target = rnd.nextDouble(-1080.0, 1080.0)
            val before = acc.value
            val after = acc.update(target)
            val delta = after - before
            assertTrue("delta $delta", abs(delta) <= 180.0)
            assertEquals(delta, acc.lastDelta, 1e-9)
            assertEquals("lands on the target mod 360", 0.0, Geo.shortestTurn(after, target), 1e-6)
        }
        // Spinning steadily clockwise keeps accumulating instead of snapping back at 360.
        val spin = ArrowRotation()
        for (deg in 0..1080 step 10) spin.update((deg % 360).toDouble())
        assertEquals(1080.0, spin.value, 1e-9)
    }

    @Test
    fun arrowRotationEaseAndGuards() {
        val acc = ArrowRotation(350.0)
        acc.ease(10.0, 0.5) // shortest turn is +20, half of it
        assertEquals(360.0, acc.value, 1e-9)
        assertEquals(10.0, acc.lastDelta, 1e-9)
        acc.update(Double.NaN)
        assertEquals(360.0, acc.value, 0.0)
        assertEquals(0.0, acc.lastDelta, 0.0)
        acc.ease(Double.POSITIVE_INFINITY, 1.0)
        assertEquals(360.0, acc.value, 0.0)
        acc.reset(90.0)
        assertEquals(90.0, acc.value, 0.0)
        assertEquals(0.0, ArrowRotation(Double.NaN).value, 0.0)
        // ease(t, 1.0) behaves like update(t)
        val a = ArrowRotation(10.0)
        val b = ArrowRotation(10.0)
        assertEquals(a.update(250.0), b.ease(250.0, 1.0), 1e-9)
    }
}
