package app.kcna26.ui.directions

import app.kcna26.geo.ArrowRotation
import app.kcna26.geo.Geo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

/**
 * The rotation-vector → heading pipeline, for all four display rotations, against hand-computed
 * expectations. Conventions: device x = right edge, y = top edge, z = out of the screen (natural
 * orientation); world x = east, y = north, z = up. A rotation of the phone flat on a table by yaw
 * α (counter-clockwise seen from above) is the quaternion (0, 0, sin(α/2), cos(α/2)).
 */
class CompassMathTest {

    private val tol = 0.01

    /** Quaternion (x, y, z, w) for a rotation of [deg] degrees about the unit [axis] (world frame). */
    private fun quat(axis: DoubleArray, deg: Double): DoubleArray {
        val h = Math.toRadians(deg) / 2
        return doubleArrayOf(axis[0] * sin(h), axis[1] * sin(h), axis[2] * sin(h), cos(h))
    }

    /** Hamilton product a ⊗ b (apply b first, then a). */
    private fun mul(a: DoubleArray, b: DoubleArray): DoubleArray {
        val (ax, ay, az, aw) = a.toList()
        val (bx, by, bz, bw) = b.toList()
        return doubleArrayOf(
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz,
        )
    }

    private fun rv(q: DoubleArray) = floatArrayOf(q[0].toFloat(), q[1].toFloat(), q[2].toFloat(), q[3].toFloat())

    /** Phone flat, screen up, yawed so that the device's top edge points at compass heading [heading]. */
    private fun flat(heading: Double) = rv(quat(doubleArrayOf(0.0, 0.0, 1.0), -heading))

    private fun assertDeg(expected: Double, actual: Double?, message: String) {
        assertNotNull(message, actual)
        val d = Geo.shortestTurn(expected, actual!!)
        assertEquals("$message: expected $expected got $actual", 0.0, d, tol)
    }

    @Test
    fun flatNorthUp_eachRotationReportsTheScreenTop() {
        // Top edge north, right edge east. The screen's "up" is: rot0 top edge (N), rot90 the right
        // edge (E), rot180 the bottom edge (S), rot270 the left edge (W).
        val v = flat(0.0)
        assertDeg(0.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(180.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    @Test
    fun flatTopEdgeEast() {
        // Top edge east → right edge south, bottom edge west, left edge north.
        val v = flat(90.0)
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(180.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(0.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    @Test
    fun flatTopEdgeNorthEast() {
        val v = flat(45.0)
        assertDeg(45.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(135.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(225.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(315.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    @Test
    fun tiltedTowardsTheUser_headingUnchanged() {
        // Top edge east, then tilted 40° about the device's x axis (top edge raised), as when
        // holding the phone while walking. Horizontal projections are unchanged.
        val yaw = quat(doubleArrayOf(0.0, 0.0, 1.0), -90.0)
        val pitch = quat(doubleArrayOf(1.0, 0.0, 0.0), 40.0)
        val v = rv(mul(yaw, pitch))
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(180.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(0.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    @Test
    fun landscapeHeldUpright_rot90UsesTheRightEdge() {
        // Phone turned 90° counter-clockwise into landscape (right edge up on screen), lying flat,
        // right edge pointing west → the user's screen-up faces west.
        // Right edge (device x) west means top edge (device y) south → flat(180).
        val v = flat(180.0)
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    @Test
    fun threeAndFiveElementVectors() {
        val q = quat(doubleArrayOf(0.0, 0.0, 1.0), -90.0)
        val three = floatArrayOf(q[0].toFloat(), q[1].toFloat(), q[2].toFloat())
        val five = floatArrayOf(q[0].toFloat(), q[1].toFloat(), q[2].toFloat(), q[3].toFloat(), 0.1f)
        assertDeg(90.0, CompassMath.azimuthDeg(three, CompassMath.ROTATION_0), "w derived")
        assertDeg(90.0, CompassMath.azimuthDeg(five, CompassMath.ROTATION_0), "with accuracy")
        assertNull(CompassMath.azimuthDeg(floatArrayOf(0f, 0f), CompassMath.ROTATION_0))
    }

    @Test
    fun resultIsInRange() {
        for (h in 0 until 360 step 15) for (r in 0..3) {
            val az = CompassMath.azimuthDeg(flat(h.toDouble()), r)!!
            assertTrue("$h/$r → $az", az >= 0.0 && az < 360.0)
        }
    }

    @Test
    fun remapAxes_matchTheAndroidTable() {
        // SensorManager.AXIS_X = 1, AXIS_Y = 2, AXIS_MINUS_X = 0x81, AXIS_MINUS_Y = 0x82.
        assertEquals(1 to 2, CompassMath.remapAxes(0))
        assertEquals(2 to 0x81, CompassMath.remapAxes(1))
        assertEquals(0x81 to 0x82, CompassMath.remapAxes(2))
        assertEquals(0x82 to 1, CompassMath.remapAxes(3))
        assertEquals(1 to 2, CompassMath.remapAxes(4))
    }

    @Test
    fun remapCoordinateSystem_rot90SwapsColumns() {
        // Columns of the output are the new axes: new x = −old y, new y = old x, new z = old z.
        val r = doubleArrayOf(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0)
        val out = CompassMath.remapCoordinateSystem(r, 2, 0x81)!!
        assertEquals(listOf(-2.0, 1.0, 3.0, -5.0, 4.0, 6.0, -8.0, 7.0, 9.0), out.toList())
        assertNull(CompassMath.remapCoordinateSystem(r, 1, 1))
        assertNull(CompassMath.remapCoordinateSystem(r, 0, 2))
    }

    @Test
    fun rotationMatrix_identity() {
        val r = CompassMath.rotationMatrixFromVector(floatArrayOf(0f, 0f, 0f, 1f))
        assertEquals(listOf(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0), r.toList())
    }

    @Test
    fun headingSmoother_turnsTheShortWay() {
        val s = HeadingSmoother(0.5)
        assertEquals(350.0, s.update(350.0), tol) // first sample passes through
        assertEquals(0.0, s.update(10.0), tol) // half way along +20°, not via 180°
        assertEquals(5.0, s.update(10.0), tol)
        val noSmoothing = HeadingSmoother(1.0)
        noSmoothing.update(90.0)
        assertEquals(270.0, noSmoothing.update(270.0), tol)
        s.reset()
        assertNull(s.value)
    }

    @Test
    fun arrowAccumulator_neverSpinsTheLongWay() {
        // The map's heading cone animates to the accumulator's unbounded value: 350° → 10° is +20°, not −340°.
        val rot = ArrowRotation()
        val a = rot.update(350.0)
        val b = rot.update(10.0)
        assertEquals(20.0, b - a, tol)
        val c = rot.update(190.0)
        assertTrue(kotlin.math.abs(c - b) <= 180.0 + tol)
    }

    @Test
    fun calibrationHint() {
        assertFalse(Calibration.needsHint(null, null))
        assertTrue(Calibration.needsHint(0, 3)) // magnetometer unreliable
        assertTrue(Calibration.needsHint(1, 3)) // magnetometer low
        assertTrue(Calibration.needsHint(3, 0)) // rotation vector unreliable
        assertFalse(Calibration.needsHint(2, 3)) // medium is fine
        assertFalse(Calibration.needsHint(-1, 3)) // no contact is not a calibration problem
    }

    @Test
    fun throttle_atMostOncePerInterval() {
        val t = Throttle(1000)
        assertTrue(t.ready(0))
        assertFalse(t.ready(500))
        assertTrue(t.ready(1000))
        assertFalse(t.ready(1999))
        assertTrue(t.ready(2000))
    }
}
