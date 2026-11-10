package app.kcna26.ui.directions

import app.kcna26.data.PointXY
import app.kcna26.data.Wayfinding
import app.kcna26.geo.Geo
import app.kcna26.route.Route
import app.kcna26.route.RouteFrom
import app.kcna26.route.Router
import app.kcna26.settings.SettingsStore
import kotlin.math.roundToInt

/**
 * A location fix: raw [lat]/[lng] plus local metres ([x] east, [y] north of the
 * wayfinding origin) and the horizontal accuracy radius in metres.
 */
data class Fix(
    val lat: Double,
    val lng: Double,
    val x: Double,
    val y: Double,
    val accuracyM: Double,
    val altitudeM: Double? = null,
) {
    val pos: PointXY get() = PointXY(x, y)
}

/** Why there is no position yet (only used while [Fix] is null). */
enum class LocStatus {
    /** Asking / waiting for the first fix: "Finding you…". */
    SEARCHING,

    /** No fix after a while, or the location service failed: "No GPS fix yet". */
    NO_FIX,

    /** Permission denied: "Location is off". */
    PERMISSION_DENIED,

    /** Device-wide location switched off: "Location is off". */
    DEVICE_OFF,
}

/**
 * What the readout under the map shows (port of the web's lvPaint text states, without its
 * compass-arrow sentences: the app's Directions screen is a live map).
 *
 * @property headline "120 m north-east", "You’re about here", "Finding you…", ...
 * @property distance "120 m" when a distance is shown.
 * @property direction "north-east" when a distance is shown.
 * @property accuracy "±12 m" once there is a fix.
 * @property detail a sentence under the line: the floor reminder when [here], what to do when
 *   there is no fix yet, otherwise null.
 * @property weakGps set when accuracy is above [DirectionsText.WEAK_GPS_M].
 * @property here within max(15 m, 0.6 × accuracy) of the room.
 */
data class Readout(
    val headline: String,
    val distance: String?,
    val direction: String?,
    val accuracy: String?,
    val detail: String?,
    val weakGps: String?,
    val here: Boolean,
) {
    /** The line under the map: "120 m north-east · ±12 m", "You’re about here · ±10 m" or "Finding you…". */
    val line: String get() = listOfNotNull(headline, accuracy).joinToString(" · ")

    /** There is a position (so a distance or "You’re about here"). */
    val hasFix: Boolean get() = accuracy != null
}

/** UI strings. Wording follows the original web version where it has the same thing. */
object DirectionsText {
    const val FINDING = "Finding you…"
    const val FINDING_SUB = "Hold on a moment."
    const val NO_FIX = "No GPS fix yet"
    const val NO_FIX_SUB = "Indoors this can take a minute. A window or doorway helps."
    const val LOCATION_OFF = "Location is off"
    const val LOCATION_OFF_SUB = "Allow location for this app in Android Settings to see distance and direction."
    const val DEVICE_OFF_SUB = "Turn on location in Android Settings to see distance and direction."
    const val ALLOW_LOCATION = "Allow location"
    const val TURN_ON_LOCATION = "Turn on location"
    const val HERE = "You’re about here"
    const val WEAK_GPS = "GPS is weak indoors: follow the steps."
    const val FALLBACK_NOTE = Router.NO_FIX_NOTE
    const val MAP_NOTE =
        "Map is north-up; the dashed line is the walking route. Room positions come from the venue floor plans (about ±15 m)."
    const val OFF_SITE = "Off-site event. The official listing has the address and registration details."
    const val NO_POSITION = "No map position for this room."
    const val OFFICIAL_LISTING = "Official listing ↗"
    const val MY_LOCATION = "My location (GPS)"
    const val ENTRANCES = "Entrances"
    const val ROOMS = "Rooms"

    /** Header of the From menu's single list once there's a fix (not in the web, which has no fix-sorted list). */
    const val NEAREST = "Nearest first"

    /** Content descriptions of the From menu's kind icons. */
    const val ENTRANCE = "Entrance"
    const val ROOM = "Room"
    const val FROM = "From"
    const val TITLE = "Directions"
    const val UNKNOWN_SESSION = "Unknown session"
    const val CALIBRATE_TITLE = "Compass needs calibrating."
    const val CALIBRATE_BODY = "Move the phone in a figure 8 a few times, away from metal."

    /** Content description of the map's re-fit button (not in the web, which has no zoom). */
    const val REFIT = "Fit the route on the map"

    /** Accuracy above this many metres counts as weak indoor GPS. */
    const val WEAK_GPS_M = 50.0

    fun hereDetail(level: Int): String = "The room is on Level $level; the steps below get you to the right floor."

    /** The map's accessibility label (web mapSVG aria-label). */
    fun mapDescription(venueCode: String?, level: Int): String =
        "Map: destination on ${if (venueCode == "HY") "Hyatt" else "Salt Palace"} level $level"
}

/** Pure helpers behind the Directions screen. */
object DirectionsLogic {

    /** Fallback start when "My location" has no fix yet, or the stored From is invalid (web: 'E200S'). */
    const val DEFAULT_ENTRANCE = Router.DEFAULT_ENTRANCE

    /** Port of lvPaint's text selection. */
    fun readout(target: PointXY, level: Int, fix: Fix?, status: LocStatus): Readout {
        if (fix == null) {
            val (h, d) = when (status) {
                LocStatus.PERMISSION_DENIED -> DirectionsText.LOCATION_OFF to DirectionsText.LOCATION_OFF_SUB
                LocStatus.DEVICE_OFF -> DirectionsText.LOCATION_OFF to DirectionsText.DEVICE_OFF_SUB
                LocStatus.NO_FIX -> DirectionsText.NO_FIX to DirectionsText.NO_FIX_SUB
                LocStatus.SEARCHING -> DirectionsText.FINDING to DirectionsText.FINDING_SUB
            }
            return Readout(h, null, null, null, d, null, here = false)
        }
        val dist = Geo.distance(fix.pos, target)
        val bearing = Geo.bearing(fix.pos, target)
        val here = Geo.isAboutHere(dist, fix.accuracyM)
        return Readout(
            headline = if (here) DirectionsText.HERE else Geo.distanceLabel(dist, bearing),
            distance = if (here) null else "${Geo.r10(dist)} m",
            direction = if (here) null else Geo.dir8(bearing),
            accuracy = accuracyText(fix.accuracyM),
            detail = if (here) DirectionsText.hereDetail(level) else null,
            weakGps = if (fix.accuracyM > DirectionsText.WEAK_GPS_M) DirectionsText.WEAK_GPS else null,
            here = here,
        )
    }

    /** "±12 m" (web: Math.round(p.acc)). */
    fun accuracyText(accuracyM: Double): String = "±${accuracyM.coerceAtLeast(0.0).roundToInt()} m"
}

/**
 * One entry of the From picker.
 * @property pos where it is in local metres (an entrance's node, a room's x/y); null for "My location".
 * @property level its floor (the entrance node's level, the room's level); null for "My location".
 */
data class FromOption(
    val key: String,
    val label: String,
    val kind: FromKind,
    val pos: PointXY? = null,
    val level: Int? = null,
)

/**
 * The From picker's options (web wayHTML): "My location (GPS)", then the entrances in file order,
 * then the rooms sorted by name, as the engine lists them ([Router.startEntrances],
 * [Router.startRooms]: so not OFF, REG or COAT). The open menu shows them through [menu]: nearest
 * first once there is a fix, grouped like this otherwise.
 */
data class FromOptions(val entrances: List<FromOption>, val rooms: List<FromOption>) {
    val live: FromOption = FromOption(SettingsStore.FROM_LIVE, DirectionsText.MY_LOCATION, FromKind.LIVE)
    private val byKey: Map<String, FromOption> = (listOf(live) + entrances + rooms).associateBy { it.key }

    fun contains(key: String): Boolean = key in byKey
    fun label(key: String): String = byKey[key]?.label ?: key

    /** The stored From value, or the 200 South entrance when it is no longer valid (web: fk='E200S'). */
    fun validate(key: String): String = if (contains(key)) key else DirectionsLogic.DEFAULT_ENTRANCE

    /** The open menu, sorted from [at] (local metres) or grouped when there's no fix; see [FromMenu]. */
    fun menu(at: PointXY?): FromMenu = FromMenu.of(this, at)

    companion object {
        /** The engine's start options, with positions and levels from [wayfinding]'s nodes and the rooms. */
        fun from(router: Router, wayfinding: Wayfinding): FromOptions = FromOptions(
            entrances = router.startEntrances.map {
                val node = wayfinding.nodes[it.node]
                FromOption(it.key, it.name, FromKind.ENTRANCE, node?.pos, node?.level)
            },
            rooms = router.startRooms.map { FromOption(it.code, it.name, FromKind.ROOM, it.pos, it.level) },
        )
    }
}

/**
 * The route shown on screen.
 * @property from the validated From choice.
 * @property startKey for "My location": which start the live position resolved to (web LV.key).
 * @property showFallbackNote "Until GPS finds you, the steps start at the 200 South entrance."
 */
data class RoutePlan(
    val from: String,
    val route: Route?,
    val summary: String,
    val showFallbackNote: Boolean,
    val startKey: String?,
)

/** Port of the route choice in the web's wayHTML/route and the re-route rule in lvPaint. */
class RoutePlanner(private val router: Router, private val options: FromOptions) {

    fun routeFrom(from: String, fix: Fix?): RouteFrom =
        router.resolveFrom(options.validate(from), fix?.let { RouteFrom.MyLocation(it.x, it.y, it.accuracyM) })

    /**
     * When this key changes the route must be recomputed. For "My location" it follows the start
     * point the live position resolves to (so the steps don't churn on every fix); otherwise it is
     * just the From choice.
     */
    fun planKey(fromSetting: String, fix: Fix?): String {
        val from = options.validate(fromSetting)
        if (from != SettingsStore.FROM_LIVE) return from
        return "${SettingsStore.FROM_LIVE}:" + (fix?.let { router.myLocationStart(it.x, it.y).key } ?: "none")
    }

    fun plan(fromSetting: String, roomCode: String, fix: Fix?): RoutePlan {
        val from = options.validate(fromSetting)
        val route = router.route(routeFrom(from, fix), roomCode)
        val live = from == SettingsStore.FROM_LIVE
        return RoutePlan(
            from = from,
            route = route,
            summary = route?.let { router.summary(it) }.orEmpty(),
            showFallbackNote = live && route != null && !route.live,
            startKey = if (live) route?.start?.key else null,
        )
    }
}
