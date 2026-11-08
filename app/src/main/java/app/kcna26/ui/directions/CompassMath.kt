package app.kcna26.ui.directions

import app.kcna26.geo.ArrowRotation
import app.kcna26.geo.Geo
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Pure compass maths, so it can be unit-tested on the JVM (android.hardware.SensorManager's
 * static helpers are stubs there). These are line-for-line ports of AOSP
 * `SensorManager.getRotationMatrixFromVector`, `remapCoordinateSystem` and `getOrientation`.
 *
 * Coordinate frames:
 * - Device frame: x to the right edge of the panel's natural orientation, y to its top edge, z out of the screen.
 * - World frame: x east, y north, z up.
 * - A rotation matrix R (row-major 3×3) maps device vectors to world vectors; its columns are the
 *   device axes expressed in world coordinates.
 */
object CompassMath {

    /** android.view.Surface.ROTATION_* values, as returned by Display.getRotation(). */
    const val ROTATION_0 = 0
    const val ROTATION_90 = 1
    const val ROTATION_180 = 2
    const val ROTATION_270 = 3

    // SensorManager.AXIS_* values.
    private const val AXIS_X = 1
    private const val AXIS_Y = 2
    private const val AXIS_MINUS_X = AXIS_X or 0x80
    private const val AXIS_MINUS_Y = AXIS_Y or 0x80

    /**
     * Magnetic heading in degrees [0, 360) of "the top of the phone as the user sees the screen",
     * from TYPE_ROTATION_VECTOR [values] (x, y, z[, w[, accuracy]]) and the rotation of the display
     * the activity is on ([displayRotation], Surface.ROTATION_*). Null for malformed input.
     *
     * Pipeline (as on Android): getRotationMatrixFromVector → remapCoordinateSystem for the display
     * rotation → getOrientation → azimuth.
     */
    fun azimuthDeg(values: FloatArray, displayRotation: Int): Double? {
        if (values.size < 3) return null
        val r = rotationMatrixFromVector(values)
        val out = remapForDisplay(r, displayRotation)
        val az = orientation(out)[0]
        if (az.isNaN()) return null
        return Geo.norm360(Math.toDegrees(az))
    }

    /** (X, Y) axis pair for SensorManager.remapCoordinateSystem, per display rotation. */
    fun remapAxes(displayRotation: Int): Pair<Int, Int> = when (((displayRotation % 4) + 4) % 4) {
        ROTATION_90 -> AXIS_Y to AXIS_MINUS_X
        ROTATION_180 -> AXIS_MINUS_X to AXIS_MINUS_Y
        ROTATION_270 -> AXIS_MINUS_Y to AXIS_X
        else -> AXIS_X to AXIS_Y
    }

    /** Remaps [r] so that its y axis is "up" on the screen for [displayRotation]. */
    fun remapForDisplay(r: DoubleArray, displayRotation: Int): DoubleArray {
        val (x, y) = remapAxes(displayRotation)
        return remapCoordinateSystem(r, x, y) ?: r.copyOf()
    }

    /** Port of SensorManager.getRotationMatrixFromVector for a 3×3 (9-element) matrix. */
    fun rotationMatrixFromVector(rv: FloatArray): DoubleArray {
        val q1 = rv[0].toDouble()
        val q2 = rv[1].toDouble()
        val q3 = rv[2].toDouble()
        val q0 = if (rv.size >= 4) {
            rv[3].toDouble()
        } else {
            val w = 1 - q1 * q1 - q2 * q2 - q3 * q3
            if (w > 0) sqrt(w) else 0.0
        }
        val sqQ1 = 2 * q1 * q1
        val sqQ2 = 2 * q2 * q2
        val sqQ3 = 2 * q3 * q3
        val q1q2 = 2 * q1 * q2
        val q3q0 = 2 * q3 * q0
        val q1q3 = 2 * q1 * q3
        val q2q0 = 2 * q2 * q0
        val q2q3 = 2 * q2 * q3
        val q1q0 = 2 * q1 * q0
        return doubleArrayOf(
            1 - sqQ2 - sqQ3, q1q2 - q3q0, q1q3 + q2q0,
            q1q2 + q3q0, 1 - sqQ1 - sqQ3, q2q3 - q1q0,
            q1q3 - q2q0, q2q3 + q1q0, 1 - sqQ1 - sqQ2,
        )
    }

    /** Port of SensorManager.remapCoordinateSystem (3×3). Null for an invalid axis pair. */
    fun remapCoordinateSystem(inR: DoubleArray, axisX: Int, axisY: Int): DoubleArray? {
        if ((axisX and 0x7C) != 0 || (axisY and 0x7C) != 0) return null
        if ((axisX and 0x3) == 0 || (axisY and 0x3) == 0) return null
        if ((axisX and 0x3) == (axisY and 0x3)) return null
        var axisZ = axisX xor axisY
        val x = (axisX and 0x3) - 1
        val y = (axisY and 0x3) - 1
        val z = (axisZ and 0x3) - 1
        val axisYi = (z + 1) % 3
        val axisZi = (z + 2) % 3
        if (((x xor axisYi) or (y xor axisZi)) != 0) axisZ = axisZ xor 0x80
        val sx = axisX >= 0x80
        val sy = axisY >= 0x80
        val sz = axisZ >= 0x80
        val out = DoubleArray(9)
        for (j in 0 until 3) {
            val offset = j * 3
            for (i in 0 until 3) {
                if (x == i) out[offset + i] = if (sx) -inR[offset] else inR[offset]
                if (y == i) out[offset + i] = if (sy) -inR[offset + 1] else inR[offset + 1]
                if (z == i) out[offset + i] = if (sz) -inR[offset + 2] else inR[offset + 2]
            }
        }
        return out
    }

    /** Port of SensorManager.getOrientation (3×3): [azimuth, pitch, roll] in radians. */
    fun orientation(r: DoubleArray): DoubleArray = doubleArrayOf(
        atan2(r[1], r[4]),
        asin((-r[7]).coerceIn(-1.0, 1.0)),
        atan2(-r[6], r[8]),
    )

    /** Rotation in degrees of a Surface.ROTATION_* value (for logs). */
    fun rotationDegrees(displayRotation: Int): Int = (((displayRotation % 4) + 4) % 4) * 90
}

/**
 * Exponential smoothing of a compass heading that always moves the short way round
 * (350° → 10° passes through 0°, never 180°), built on the engine's shortest-turn accumulator
 * ([ArrowRotation.ease]). [alpha] in (0, 1]: 1 = no smoothing. Output is in [0, 360).
 * Not thread-safe.
 */
class HeadingSmoother(private val alpha: Double = 0.5) {
    private val rot = ArrowRotation()
    private var started = false

    /** The smoothed heading, or null before the first sample. */
    val value: Double? get() = if (started) Geo.norm360(rot.value) else null

    fun update(rawDeg: Double): Double {
        if (!started) {
            rot.reset(Geo.norm360(rawDeg))
            started = true
        } else {
            rot.ease(rawDeg, alpha)
        }
        return Geo.norm360(rot.value)
    }

    fun reset() {
        started = false
        rot.reset()
    }
}

/**
 * Sensor accuracy bookkeeping for the figure-8 calibration hint: the hint shows when the
 * magnetometer or the rotation vector reports SENSOR_STATUS_UNRELIABLE (0) or
 * SENSOR_STATUS_ACCURACY_LOW (1). SENSOR_STATUS_NO_CONTACT (−1) and unknown are ignored.
 */
object Calibration {
    const val UNRELIABLE = 0 // SensorManager.SENSOR_STATUS_UNRELIABLE
    const val LOW = 1 // SensorManager.SENSOR_STATUS_ACCURACY_LOW

    fun isPoor(accuracy: Int?): Boolean = accuracy == UNRELIABLE || accuracy == LOW

    fun needsHint(magnetometerAccuracy: Int?, rotationVectorAccuracy: Int?): Boolean =
        isPoor(magnetometerAccuracy) || isPoor(rotationVectorAccuracy)
}

/** Lets something through at most once per [intervalMs] (for the KcnaCompass debug log). */
class Throttle(private val intervalMs: Long) {
    private var last = Long.MIN_VALUE

    fun ready(nowMs: Long): Boolean {
        if (last != Long.MIN_VALUE && nowMs - last < intervalMs) return false
        last = nowMs
        return true
    }
}
