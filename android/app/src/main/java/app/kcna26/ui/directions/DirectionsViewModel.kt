package app.kcna26.ui.directions

import android.hardware.Sensor
import android.os.SystemClock
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.kcna26.data.PointXY
import app.kcna26.data.Repository
import app.kcna26.data.Room
import app.kcna26.data.Session
import app.kcna26.geo.Geo
import app.kcna26.route.Router
import app.kcna26.settings.SettingsStore
import app.kcna26.time.AppClock
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * State of one Directions screen. Activity-scoped and keyed per session ("dir-<id>"), so the last
 * fix, the heading and the route survive fold/unfold recreation without flashing "Finding you…".
 * The sensors and location updates themselves belong to the screen's lifecycle (they push into
 * this ViewModel through [onAzimuth], [onSensorAccuracy] and [onLocation]). The heading only
 * drives the heading cone on the map's "me" dot.
 */
class DirectionsViewModel(
    private val repo: Repository,
    router: Router,
    private val settings: SettingsStore,
    private val clock: AppClock,
    val sessionId: String,
    private val declinationOf: (lat: Double, lng: Double, altitudeM: Double, timeMs: Long) -> Double = Geo::declinationDeg,
    private val log: (String) -> Unit = { Log.d(CompassSensor.TAG, it) },
    /** Monotonic time for fix staleness only (never shown, so not the app clock). */
    private val elapsedMs: () -> Long = SystemClock::elapsedRealtime,
) : ViewModel() {

    val session: Session? = repo.session(sessionId)
    val room: Room? = session?.let { repo.roomOf(it) }

    /** The room's position, or null for OFF / unknown rooms (no live directions then). */
    val target: PointXY? = room?.takeIf { it.hasPosition && it.level != null }?.pos

    val options: FromOptions = FromOptions.from(router, repo.wayfinding)
    private val planner = RoutePlanner(router, options)

    private val _fix = MutableStateFlow<Fix?>(null)
    val fix: StateFlow<Fix?> = _fix.asStateFlow()

    private val _noFix = MutableStateFlow(false)

    /** True once tracking ran [NO_FIX_AFTER_MS] without a fix (or failed): "No GPS fix yet". */
    val noFix: StateFlow<Boolean> = _noFix.asStateFlow()

    private val _deviceLocationOff = MutableStateFlow(false)
    val deviceLocationOff: StateFlow<Boolean> = _deviceLocationOff.asStateFlow()

    private val _heading = MutableStateFlow<Double?>(null)

    /**
     * Smoothed true heading of the top of the phone (degrees clockwise from north, turning the
     * short way round), or null until the compass wakes up: the map hides the cone until then.
     */
    val heading: StateFlow<Double?> = _heading.asStateFlow()

    private val _calibrate = MutableStateFlow(false)

    /** Show the figure-8 hint (magnetometer or rotation vector accuracy low/unreliable for a moment). */
    val calibrate: StateFlow<Boolean> = _calibrate.asStateFlow()

    /** The route on screen; re-planned when From changes, or (My location) when the start point changes. */
    val plan: StateFlow<RoutePlan?> = run {
        val code = room?.code
        if (code == null || target == null) {
            MutableStateFlow<RoutePlan?>(null).asStateFlow()
        } else {
            combine(settings.directionsFrom, fix) { from, f -> from to f }
                .distinctUntilChanged { a, b -> planner.planKey(a.first, a.second) == planner.planKey(b.first, b.second) }
                .map<Pair<String, Fix?>, RoutePlan?> { (from, f) -> planner.plan(from, code, f) }
                .stateIn(
                    viewModelScope,
                    SharingStarted.Eagerly,
                    planner.plan(settings.directionsFrom.value, code, _fix.value),
                )
        }
    }

    val directionsFrom: StateFlow<String> get() = settings.directionsFrom

    private val smoother = HeadingSmoother(HEADING_ALPHA)
    private val logThrottle = Throttle(1000)
    /** Degrees east; the venue's until the first fix, then the fix's. */
    private var declinationDeg: Double = FALLBACK_DECLINATION
    private var magAccuracy: Int? = null
    private var rvAccuracy: Int? = null
    private var calibrateJob: Job? = null
    private var noFixJob: Job? = null
    private var fixAtMs = 0L

    fun setFrom(key: String) {
        if (options.contains(key)) settings.setDirectionsFrom(key)
    }

    /** A new fused-location fix. */
    fun onLocation(lat: Double, lng: Double, accuracyM: Double, altitudeM: Double?) {
        if (!lat.isFinite() || !lng.isFinite()) return
        val p = Geo.toLocal(lat, lng, repo.wayfinding.origin)
        declinationDeg = safeDeclination(lat, lng, altitudeM ?: VENUE_ALTITUDE_M)
        fixAtMs = elapsedMs()
        noFixJob?.cancel()
        _noFix.value = false
        _fix.value = Fix(lat, lng, p.x, p.y, if (accuracyM.isFinite()) accuracyM.coerceAtLeast(0.0) else 0.0, altitudeM)
    }

    /** A new magnetic azimuth from the rotation vector (already remapped for the display). */
    fun onAzimuth(magneticDeg: Double, displayId: Int, rotation: Int, timeMs: Long) {
        if (!magneticDeg.isFinite()) return
        val trueDeg = Geo.trueHeading(magneticDeg, declinationDeg)
        _heading.value = smoother.update(trueDeg)
        if (logThrottle.ready(timeMs)) {
            log(
                String.format(
                    Locale.ROOT,
                    "display=%d rotation=%d (%d°) rawAzimuth=%.1f declination=%.1f trueHeading=%.1f",
                    displayId, rotation, CompassMath.rotationDegrees(rotation), magneticDeg, declinationDeg, trueDeg,
                ),
            )
        }
    }

    /** Accuracy of TYPE_MAGNETIC_FIELD or TYPE_ROTATION_VECTOR changed. */
    fun onSensorAccuracy(sensorType: Int, accuracy: Int) {
        when (sensorType) {
            Sensor.TYPE_MAGNETIC_FIELD -> magAccuracy = accuracy
            Sensor.TYPE_ROTATION_VECTOR -> rvAccuracy = accuracy
            else -> return
        }
        if (!Calibration.needsHint(magAccuracy, rvAccuracy)) {
            calibrateJob?.cancel()
            calibrateJob = null
            _calibrate.value = false
        } else if (!_calibrate.value && calibrateJob?.isActive != true) {
            // Sensors often report "unreliable" for a moment right after registering: wait a little.
            calibrateJob = viewModelScope.launch {
                delay(CALIBRATE_AFTER_MS)
                _calibrate.value = true
            }
        }
    }

    /**
     * Location updates started (screen visible, permission granted). A fix kept from more than
     * [STALE_FIX_MS] ago is dropped, so returning to the screen later never shows an old position
     * (a fold/unfold takes about a second, so its fix survives).
     */
    fun trackingStarted() {
        noFixJob?.cancel()
        if (_fix.value != null && elapsedMs() - fixAtMs > STALE_FIX_MS) _fix.value = null
        if (_fix.value != null) return
        noFixJob = viewModelScope.launch {
            delay(NO_FIX_AFTER_MS)
            if (_fix.value == null) _noFix.value = true
        }
    }

    fun trackingStopped() {
        noFixJob?.cancel()
        noFixJob = null
    }

    /** Play services failed or the permission vanished: show "No GPS fix yet" rather than waiting. */
    fun onLocationFailure() {
        if (_fix.value == null) _noFix.value = true
    }

    fun setDeviceLocationOff(off: Boolean) {
        _deviceLocationOff.value = off
    }

    init {
        val o = repo.wayfinding.origin
        declinationDeg = safeDeclination(o.lat0, o.lon0, VENUE_ALTITUDE_M)
    }

    /** Declination at a point, or the last good value if the model can't answer. */
    private fun safeDeclination(lat: Double, lng: Double, altitudeM: Double): Double {
        val d = runCatching { declinationOf(lat, lng, altitudeM, clock.now().toEpochMilli()) }.getOrNull()
        return if (d != null && d.isFinite()) d else declinationDeg
    }

    /** Current declination in degrees east (for tests and logs). */
    val declination: Double get() = declinationDeg

    companion object {
        const val NO_FIX_AFTER_MS = 30_000L
        const val STALE_FIX_MS = 60_000L
        const val CALIBRATE_AFTER_MS = 1_500L
        const val HEADING_ALPHA = 0.5
        const val VENUE_ALTITUDE_M = 1300.0
        /** wayfinding.json: "About 10 degrees east at Salt Lake City" (the web's DECL). */
        const val FALLBACK_DECLINATION = Geo.SLC_DECLINATION_DEG
    }
}
