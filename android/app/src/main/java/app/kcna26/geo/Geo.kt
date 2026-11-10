package app.kcna26.geo

import android.hardware.GeomagneticField
import app.kcna26.data.Origin
import app.kcna26.data.PointXY
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max

/**
 * Pure geometry for Directions (distance, bearing, heading) and the router (owner: engine). Ports of
 * schedule_app.js: the LAT0/LON0/MY/MX conversion, `brgTo`, `dir8`, `r10`, and the
 * `LV.rot` accumulator in `lvPaint` (see [ArrowRotation]).
 *
 * Coordinates are local metres (x east, y north, true north) from wayfinding.json
 * "origin". Everything here is allocation-light and safe to call on the main thread
 * for every sensor or location update. No function throws, NaN in gives a harmless
 * value out.
 */
object Geo {
    /** Magnetic declination at Salt Lake City (web `DECL`), only a fallback for [declinationDeg]. */
    const val SLC_DECLINATION_DEG = 10.4

    /** lat/lng → local metres: x = (lng − lon0)·metersPerDegLon, y = (lat − lat0)·metersPerDegLat. */
    fun toLocal(lat: Double, lng: Double, origin: Origin): PointXY =
        PointXY((lng - origin.lon0) * origin.metersPerDegLon, (lat - origin.lat0) * origin.metersPerDegLat)

    /** Horizontal straight-line distance in metres. */
    fun distance(a: PointXY, b: PointXY): Double = hypot(b.x - a.x, b.y - a.y)

    /** True bearing from [from] to [to], degrees clockwise from north, in [0, 360). Web `brgTo`. */
    fun bearing(from: PointXY, to: PointXY): Double =
        (Math.toDegrees(atan2(to.x - from.x, to.y - from.y)) + 360.0) % 360.0

    /**
     * Eight-way direction word, web `dir8`: `[…][Math.round(b/45) % 8]`. 337.5° and up is
     * "north" again; half-way values round up like JavaScript (22.5° → "north-east").
     * Negative and ≥ 360 inputs are wrapped; NaN gives "north".
     */
    fun dir8(bearingDeg: Double): String {
        val i = Math.floorMod(jsRound(bearingDeg / 45.0), 8L).toInt()
        return DIRS[i]
    }

    /** Distance rounded to 10 m, at least 10 (web `r10`): max(10, round(m/10)·10). */
    fun r10(m: Double): Int = (jsRound(m / 10.0).toDouble() * 10.0).coerceIn(10.0, Int.MAX_VALUE.toDouble()).toInt()

    /** Rounds to the nearest 10 m with no minimum (the summary's `Math.round(m/10)*10`). */
    fun round10(m: Double): Long = jsRound(m / 10.0) * 10L

    /** "120 m north-east": the Directions distance line (web `${r10(dist)} m ${dir8(b)}`). */
    fun distanceLabel(distanceM: Double, bearingDeg: Double): String = "${r10(distanceM)} m ${dir8(bearingDeg)}"

    /** Radius within which Directions says "You’re about here": max(15 m, 0.6 × accuracy). */
    fun hereRadius(accuracyM: Double): Double = max(15.0, accuracyM * 0.6)

    /** Web `here = dist < max(15, acc·0.6)`. */
    fun isAboutHere(distanceM: Double, accuracyM: Double): Boolean = distanceM < hereRadius(accuracyM)

    /** trueHeading = (magneticAzimuth + declination + 360) % 360, in [0, 360). */
    fun trueHeading(magneticAzimuthDeg: Double, declinationDeg: Double): Double = norm360(magneticAzimuthDeg + declinationDeg)

    /**
     * Angle of a bearing relative to the top of the phone, in [0, 360): bearing − trueHeading
     * (the web's compass arrow; the app no longer draws one, but test_vectors.json checks it).
     * Feed it (or the raw difference) to [ArrowRotation.update] so a rotation turns the short way.
     */
    fun arrowDeg(trueHeadingDeg: Double, bearingDeg: Double): Double = norm360(bearingDeg - trueHeadingDeg)

    /** Wraps any angle into [0, 360). */
    fun norm360(deg: Double): Double = ((deg % 360.0) + 360.0) % 360.0

    /** Signed shortest turn from [fromDeg] to [toDeg], in [−180, 180) (web `((rot−LV.rot)%360+540)%360−180`). */
    fun shortestTurn(fromDeg: Double, toDeg: Double): Double = (((toDeg - fromDeg) % 360.0 + 540.0) % 360.0) - 180.0

    /**
     * Magnetic declination (degrees east) from [GeomagneticField] at a position and time.
     * Pass the app clock's time (`clock.now().toEpochMilli()`), never the system time.
     * Falls back to [SLC_DECLINATION_DEG] if the platform returns something unusable.
     */
    fun declinationDeg(lat: Double, lng: Double, altitudeM: Double, epochMillis: Long): Double = try {
        val d = GeomagneticField(lat.toFloat(), lng.toFloat(), altitudeM.toFloat(), epochMillis).declination.toDouble()
        if (d.isFinite() && abs(d) <= 180.0) d else SLC_DECLINATION_DEG
    } catch (e: RuntimeException) {
        SLC_DECLINATION_DEG
    }

    /** JavaScript Math.round: nearest integer, halves toward +∞; NaN → 0 (never throws, unlike roundToInt). */
    internal fun jsRound(x: Double): Long = Math.round(x)

    private val DIRS = arrayOf("north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west")
}

/**
 * Shortest-turn rotation accumulator, the web's compass-arrow smoothing
 * `LV.rot += ((rot − LV.rot) % 360 + 540) % 360 − 180`. The app uses it for the heading
 * cone on the Directions map.
 *
 * [value] is unbounded (it may go past 360 or below 0), so animating it (for example
 * with `animateFloatAsState` on the value) never spins the long way round: every
 * update moves by at most 180°. Heading 350° → bearing 10° moves +20°, not −340°.
 * Not thread-safe; keep one per rotating thing (in a ViewModel or `remember {}`).
 */
class ArrowRotation(initialDeg: Double = 0.0) {
    /** Current accumulated rotation in degrees (unbounded). */
    var value: Double = if (initialDeg.isFinite()) initialDeg else 0.0
        private set

    /** The change made by the last [update] or [ease], always in [−180, 180). */
    var lastDelta: Double = 0.0
        private set

    /**
     * Moves [value] to the equivalent of [targetDeg] (any angle, e.g. bearing − heading)
     * closest to the current value and returns it. A non-finite target is ignored.
     */
    fun update(targetDeg: Double): Double {
        if (!targetDeg.isFinite()) {
            lastDelta = 0.0
            return value
        }
        lastDelta = Geo.shortestTurn(value, targetDeg)
        value += lastDelta
        return value
    }

    /**
     * Like [update] but only moves [fraction] (0..1] of the shortest turn: a simple
     * low-pass filter for jittery sensors. `ease(t, 1.0)` equals `update(t)`.
     */
    fun ease(targetDeg: Double, fraction: Double): Double {
        if (!targetDeg.isFinite() || !fraction.isFinite()) {
            lastDelta = 0.0
            return value
        }
        lastDelta = Geo.shortestTurn(value, targetDeg) * fraction.coerceIn(0.0, 1.0)
        value += lastDelta
        return value
    }

    /** Jumps to [deg] (e.g. when the destination changes). */
    fun reset(deg: Double = 0.0) {
        value = if (deg.isFinite()) deg else 0.0
        lastDelta = 0.0
    }
}
