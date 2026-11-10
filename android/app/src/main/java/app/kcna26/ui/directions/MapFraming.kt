package app.kcna26.ui.directions

import androidx.compose.runtime.Immutable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import kotlin.math.max
import kotlin.math.min

/**
 * Where the map is looking. [cx], [cy] is the point (map units, see [MapGeometry]: x east,
 * y south, 1 unit ≈ 1 m) shown at the centre of the view, and [z] is the zoom in dp per map
 * unit. Working in dp keeps a saved camera meaningful on either fold screen.
 */
@Immutable
data class MapCamera(val cx: Float, val cy: Float, val z: Float) {
    /** Screen x (dp) of map x [u] in a view [width] dp wide. */
    fun screenX(u: Float, width: Float): Float = (u - cx) * z + width / 2f

    /** Screen y (dp) of map y [v] in a view [height] dp high. */
    fun screenY(v: Float, height: Float): Float = (v - cy) * z + height / 2f

    /** Map x of screen x [sx] (dp). */
    fun mapX(sx: Float, width: Float): Float = (sx - width / 2f) / z + cx

    /** Map y of screen y [sy] (dp). */
    fun mapY(sy: Float, height: Float): Float = (sy - height / 2f) / z + cy
}

/** Space (dp) kept clear on each side of the framed content, for the pin label and the map's buttons. */
@Immutable
data class MapInsets(val left: Float, val top: Float, val right: Float, val bottom: Float)

/**
 * Framing for the Directions map. Pure, so it is unit-tested.
 *
 * - [fit] auto-frames the route, me and the destination, so being far outside the venue fits
 *   both me and the room.
 * - [inFrame] decides when me has walked out of frame (then the map re-frames).
 * - [gesture] and [keepInView] handle pinch-zoom and pan, which never push the destination
 *   off the screen.
 */
object MapFraming {
    /** Auto-framing never shows less than this many map units (≈ m) across the padded area. */
    const val MIN_SPAN = 140f

    /** Pinch-zoom stops at this many map units across the smaller side of the view. */
    const val MIN_ZOOM_SPAN = 30f

    /** Me closer than this to the view's edge (dp) counts as out of frame. */
    const val EDGE = 20f

    /** The destination pin's centre always stays at least this far (dp) inside the view. */
    const val PIN_EDGE = 18f

    /**
     * Padding (dp) around auto-framed content: the "L2" label fits right of a pin at the
     * right padding, the north rose sits in the top padding, the re-fit button in the bottom.
     */
    val PADDING = MapInsets(left = 40f, top = 46f, right = 60f, bottom = 62f)

    /** The whole venue drawing (the web's 512×510 viewBox). */
    val VENUE = Rect(0f, 0f, MapGeometry.VIEW_W, MapGeometry.VIEW_H)

    /** Bounds of the finite [points], or null if there are none. */
    fun bounds(points: Iterable<Offset>): Rect? {
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        for (p in points) {
            if (!p.x.isFinite() || !p.y.isFinite()) continue
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return if (minX > maxX) null else Rect(minX, minY, maxX, maxY)
    }

    /** What the map frames: the route, the destination and me (when there is a fix). */
    fun frameBounds(route: List<Offset>, dest: Offset, me: Offset?): Rect =
        bounds(route + listOfNotNull(dest, me)) ?: Rect(dest, dest)

    /**
     * The camera that shows [b] as large as it fits inside a [width] × [height] dp view with
     * [pad] kept clear, but never closer than [minSpan] map units across the smaller side of
     * the padded area. [b] is centred in the padded area.
     */
    fun fit(b: Rect, width: Float, height: Float, pad: MapInsets = PADDING, minSpan: Float = MIN_SPAN): MapCamera {
        val aw = max(1f, width - pad.left - pad.right)
        val ah = max(1f, height - pad.top - pad.bottom)
        val zMax = min(aw, ah) / minSpan
        val zx = if (b.width > 0f) aw / b.width else Float.POSITIVE_INFINITY
        val zy = if (b.height > 0f) ah / b.height else Float.POSITIVE_INFINITY
        val z = minOf(zx, zy, zMax)
        val dx = pad.left + aw / 2f - width / 2f
        val dy = pad.top + ah / 2f - height / 2f
        return MapCamera(b.center.x - dx / z, b.center.y - dy / z, z)
    }

    /** True when map point [p] is on screen at least [edge] dp inside the view. */
    fun inFrame(cam: MapCamera, width: Float, height: Float, p: Offset, edge: Float = EDGE): Boolean {
        val sx = cam.screenX(p.x, width)
        val sy = cam.screenY(p.y, height)
        return sx >= edge && sx <= width - edge && sy >= edge && sy <= height - edge
    }

    /** Moves [cam] as little as possible so map point [p] is at least [edge] dp inside the view. */
    fun keepInView(cam: MapCamera, width: Float, height: Float, p: Offset, edge: Float = PIN_EDGE): MapCamera {
        val hx = max(0f, width / 2f - edge) / cam.z
        val hy = max(0f, height / 2f - edge) / cam.z
        return cam.copy(cx = cam.cx.coerceIn(p.x - hx, p.x + hx), cy = cam.cy.coerceIn(p.y - hy, p.y + hy))
    }

    /**
     * One pinch/pan step: the fingers' centre is at [centroid] (dp) after moving [pan] dp, and
     * they spread by [zoom]. The map point that was under them stays under them; the zoom is
     * clamped to [zoomRange].
     */
    fun gesture(
        cam: MapCamera,
        width: Float,
        height: Float,
        centroid: Offset,
        pan: Offset,
        zoom: Float,
        zoomRange: ClosedFloatingPointRange<Float>,
    ): MapCamera {
        val factor = if (zoom.isFinite() && zoom > 0f) zoom else 1f
        val z = (cam.z * factor).coerceIn(zoomRange)
        val ax = cam.mapX(centroid.x - pan.x, width)
        val ay = cam.mapY(centroid.y - pan.y, height)
        return MapCamera(ax - (centroid.x - width / 2f) / z, ay - (centroid.y - height / 2f) / z, z)
    }

    /**
     * Pinch-zoom range: out to half the zoom that fits the framed content or the whole venue
     * (whichever is further out), in to [MIN_ZOOM_SPAN] map units across.
     */
    fun zoomRange(fitZ: Float, width: Float, height: Float): ClosedFloatingPointRange<Float> {
        val venueZ = fit(VENUE, width, height).z
        val zMin = min(fitZ, venueZ) / 2f
        val zMax = max(zMin, min(width, height) / MIN_ZOOM_SPAN)
        return zMin..zMax
    }

    /** The pin's level label goes left of the pin when it would not fit on the right. */
    fun labelOnLeft(pinX: Float, width: Float, gap: Float, labelWidth: Float, margin: Float = 4f): Boolean =
        pinX + gap + labelWidth > width - margin
}
