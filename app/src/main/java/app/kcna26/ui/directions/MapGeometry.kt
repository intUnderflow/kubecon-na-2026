package app.kcna26.ui.directions

import app.kcna26.data.PointXY
import app.kcna26.data.Zone

/**
 * Geometry of the web's mapSVG, in its 512×510 viewBox units (1 unit ≈ 1 m):
 * svgX = x + 492, svgY = 492 − y (north up). These "map units" are what the zoomable
 * [VenueMap] and [MapFraming] work in. Pure, so it is unit-tested.
 */
object MapGeometry {
    const val VIEW_W = 512f
    const val VIEW_H = 510f
    private const val OFFSET = 492.0

    fun svgX(x: Double): Float = (x + OFFSET).toFloat()
    fun svgY(y: Double): Float = (OFFSET - y).toFloat()

    /** Accuracy circle radius in map units, clamped like the web: min(250, max(8, acc)). */
    fun accuracyRadius(accuracyM: Double): Float = accuracyM.coerceIn(8.0, 250.0).toFloat()

    enum class Anchor { START, MIDDLE, END }

    /** A text label at a baseline point in view units. [rotateDeg] rotates around (x, y). */
    data class Label(val text: String, val x: Float, val y: Float, val anchor: Anchor = Anchor.START, val rotateDeg: Float = 0f)

    /** The destination pin's level label (web: "L2"). */
    fun levelText(level: Int): String = "L$level"

    /** Street names, placed as in the web's mapSVG. */
    val streetLabels: List<Label> = listOf(
        Label("West Temple", 498f, 250f, Anchor.MIDDLE, rotateDeg = 90f),
        Label("200 South", 292f, 505f),
        Label("100 South", 140f, (OFFSET - 246).toFloat()),
        Label("South Temple", 270f, 12f),
        Label("200 West", 240f, 60f, rotateDeg = 90f),
        Label("300 W", 2f, 20f),
    )

    /** The web's short zone labels and positions (local metres), keyed by venue.json zone name. */
    private val zoneLabels: Map<String, Triple<String, Double, Double>> = mapOf(
        "Hall DE" to Triple("Hall DE", -182.0, 140.0),
        "Halls A–C" to Triple("Halls A–C", -182.0, 286.0),
        "Halls 1–5" to Triple("Halls 1–5", -455.0, 385.0),
        "Grand Ballroom" to Triple("Ballroom", -80.0, 190.0),
        "Rooms 155 / 255" to Triple("155·255", -210.0, 450.0),
    )

    /** Label for a hall zone; unknown zones get the web's default spot (x0 + 4, y1 − 14). */
    fun zoneLabel(zone: Zone): Label {
        val (text, lx, ly) = zoneLabels[zone.name] ?: Triple(zone.name, zone.x0 + 4, zone.y1 - 14)
        return Label(text, svgX(lx), svgY(ly))
    }

    /** The "Hyatt" label inside the Hyatt outline. */
    val hyattLabel: Label = Label("Hyatt", svgX(-78.0), svgY(30.0))

    /**
     * The polyline drawn by the static map layer. For a live route the first point is "me" and is
     * drawn by the live layer from the current fix to [points][1]; so the static part starts at 1.
     */
    fun staticRoute(points: List<PointXY>, live: Boolean): List<PointXY> =
        if (live) points.drop(1) else points

    // SVG path data from the web (24×24 icon box unless noted).
    const val CONE_PATH = "M0 0-11-30A32 32 0 0 1 11-30z" // heading cone around "me", 32 units long
    const val ROSE_PATH = "M0-12 5 4 0 1-5 4z" // north rose around its centre, in a 34-unit disc
    const val ICON_WALK = "M5 12h12M13 7l5 5-5 5"
    const val ICON_UP = "M4 19h5l7-12h4M15 7h5v5"
    const val ICON_DOWN = "M4 7h5l7 12h4M15 19h5v-5"
    const val ICON_END = "M12 21s-6-5.6-6-10a6 6 0 1 1 12 0c0 4.4-6 10-6 10z"
}
