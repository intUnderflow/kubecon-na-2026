package app.kcna26.ui.directions

import app.kcna26.TestData
import app.kcna26.data.PointXY
import app.kcna26.geo.Geo
import app.kcna26.route.RouteFrom
import app.kcna26.route.Router
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MapFramingTest {

    private val repo = TestData.repo
    private val router = Router(repo)
    private val pad = MapFraming.PADDING
    private val tol = 0.01f

    /** The two Pixel 10 Pro Fold map viewports (dp): cover-screen column and inner-screen left column. */
    private val cover = 411f to 485f
    private val inner = 460f to 760f

    private fun map(p: PointXY) = Offset(MapGeometry.svgX(p.x), MapGeometry.svgY(p.y))

    private fun assertInPaddedArea(cam: MapCamera, w: Float, h: Float, p: Offset, what: String) {
        val sx = cam.screenX(p.x, w)
        val sy = cam.screenY(p.y, h)
        assertTrue("$what x=$sx", sx >= pad.left - tol && sx <= w - pad.right + tol)
        assertTrue("$what y=$sy", sy >= pad.top - tol && sy <= h - pad.bottom + tol)
    }

    @Test
    fun cameraRoundTrip() {
        val cam = MapCamera(200f, 300f, 0.8f)
        assertEquals(205.5f, cam.screenX(200f, 411f), tol)
        assertEquals(200f, cam.mapX(cam.screenX(200f, 411f), 411f), tol)
        assertEquals(123f, cam.mapY(cam.screenY(123f, 485f), 485f), tol)
    }

    @Test
    fun fit_framesTheRouteAndTheDestination() {
        val route = router.route(RouteFrom.Entrance("E200S"), "251AC")!!
        val points = route.points.map(::map)
        val dest = map(repo.room("251AC")!!.pos!!)
        for ((w, h) in listOf(cover, inner)) {
            val cam = MapFraming.fit(MapFraming.frameBounds(points, dest, null), w, h)
            for (p in points) assertInPaddedArea(cam, w, h, p, "route point at ${w}x$h")
            assertInPaddedArea(cam, w, h, dest, "destination at ${w}x$h")
            // As large as fits: some framed point touches the padded area's edge.
            val xs = (points + dest).map { cam.screenX(it.x, w) }
            val ys = (points + dest).map { cam.screenY(it.y, h) }
            val touches = kotlin.math.abs(xs.min() - pad.left) < 0.5f || kotlin.math.abs(xs.max() - (w - pad.right)) < 0.5f ||
                kotlin.math.abs(ys.min() - pad.top) < 0.5f || kotlin.math.abs(ys.max() - (h - pad.bottom)) < 0.5f
            // ...unless the minimum span (140 m across the padded area's smaller side) caps the zoom.
            val capped = kotlin.math.abs(cam.z - minOf(w - pad.left - pad.right, h - pad.top - pad.bottom) / MapFraming.MIN_SPAN) < 1e-4f
            assertTrue("${w}x$h z=${cam.z}", touches || capped)
        }
    }

    @Test
    fun fit_neverZoomsInPastTheMinimumSpan() {
        val dest = map(repo.room("251AC")!!.pos!!)
        val (w, h) = cover
        val cam = MapFraming.fit(MapFraming.frameBounds(emptyList(), dest, dest.copy(x = dest.x + 3f)), w, h)
        val aw = w - pad.left - pad.right
        val ah = h - pad.top - pad.bottom
        assertEquals(minOf(aw, ah) / MapFraming.MIN_SPAN, cam.z, 1e-4f)
        assertInPaddedArea(cam, w, h, dest, "destination")
    }

    @Test
    fun fit_farOutsideTheVenue_fitsMeAndTheDestination() {
        val dest = map(repo.room("251AC")!!.pos!!)
        // Temple Square (a test vector), then 3 km north of the venue.
        val temple = TestData.vectors.compass[1].let { Geo.toLocal(it.lat, it.lng, repo.wayfinding.origin) }
        for (meLocal in listOf(temple, PointXY(0.0, 3000.0))) {
            val me = map(meLocal)
            val live = router.route(RouteFrom.MyLocation(meLocal.x, meLocal.y, 10.0), "251AC")!!
            assertTrue(live.live)
            val drawn = MapGeometry.staticRoute(live.points, live = true).map(::map)
            for ((w, h) in listOf(cover, inner)) {
                val cam = MapFraming.fit(MapFraming.frameBounds(drawn, dest, me), w, h)
                assertInPaddedArea(cam, w, h, me, "me")
                assertInPaddedArea(cam, w, h, dest, "destination")
            }
        }
    }

    @Test
    fun fit_neverCropsTheDestinationOrItsLabel_forEveryRouteAndStart() {
        val labelW = 34f // "L4" pill, dp
        val gap = 16f
        val starts = router.startEntrances.map { RouteFrom.Entrance(it.key) } + RouteFrom.MyLocation(0.0, 3000.0, 10.0)
        for (room in repo.rooms.values.filter { router.isRoutable(it.code) }) {
            val dest = map(room.pos!!)
            for (from in starts) {
                val r = router.route(from, room.code)!!
                val me = (from as? RouteFrom.MyLocation)?.let { map(PointXY(it.x, it.y)) }
                val drawn = MapGeometry.staticRoute(r.points, r.live).map(::map)
                for ((w, h) in listOf(cover, inner, 300f to 260f)) {
                    val cam = MapFraming.fit(MapFraming.frameBounds(drawn, dest, me), w, h)
                    val sx = cam.screenX(dest.x, w)
                    val sy = cam.screenY(dest.y, h)
                    val left = MapFraming.labelOnLeft(sx, w, gap, labelW)
                    val l = if (left) sx - gap - labelW else sx + gap
                    val what = "${room.code} from $from at ${w}x$h"
                    assertTrue("$what label $l", l >= 0f && l + labelW <= w)
                    assertTrue("$what pin $sx,$sy", sx in 12f..(w - 12f) && sy in 12f..(h - 12f))
                }
            }
        }
    }

    @Test
    fun inFrame_meWalkingOutOfFrameTriggersAReframe() {
        val (w, h) = cover
        val cam = MapCamera(256f, 255f, 0.8f)
        assertTrue(MapFraming.inFrame(cam, w, h, Offset(256f, 255f)))
        // The view is 411 / 0.8 ≈ 514 map units wide: 250 units east of centre is near the edge.
        assertTrue(MapFraming.inFrame(cam, w, h, Offset(256f + 230f, 255f)))
        assertFalse(MapFraming.inFrame(cam, w, h, Offset(256f + 250f, 255f)))
        assertFalse(MapFraming.inFrame(cam, w, h, Offset(256f, 255f - 400f)))
    }

    @Test
    fun keepInView_pullsTheDestinationBackOnScreen() {
        val (w, h) = cover
        val dest = Offset(100f, 100f)
        val far = MapCamera(2000f, 2000f, 2f)
        val kept = MapFraming.keepInView(far, w, h, dest)
        assertEquals(MapFraming.PIN_EDGE, kept.screenX(dest.x, w), tol + 1e-3f * w)
        assertEquals(MapFraming.PIN_EDGE, kept.screenY(dest.y, h), tol + 1e-3f * h)
        assertEquals(far.z, kept.z, 0f)
        // Already in view: unchanged.
        val near = MapCamera(110f, 90f, 1f)
        assertEquals(near, MapFraming.keepInView(near, w, h, dest))
    }

    @Test
    fun gesture_zoomsAboutTheFingersAndPans() {
        val (w, h) = cover
        val cam = MapCamera(256f, 255f, 1f)
        val centroid = Offset(300f, 200f)
        val under = Offset(cam.mapX(centroid.x, w), cam.mapY(centroid.y, h))
        val zoomed = MapFraming.gesture(cam, w, h, centroid, Offset.Zero, 2f, 0.1f..10f)
        assertEquals(2f, zoomed.z, tol)
        assertEquals(under.x, zoomed.mapX(centroid.x, w), tol)
        assertEquals(under.y, zoomed.mapY(centroid.y, h), tol)

        // A 40 dp drag to the right moves the map with the finger.
        val panned = MapFraming.gesture(cam, w, h, Offset(240f, 200f), Offset(40f, 0f), 1f, 0.1f..10f)
        assertEquals(cam.cx - 40f, panned.cx, tol)
        assertEquals(cam.cy, panned.cy, tol)

        // Zoom is clamped; nonsense zoom factors are ignored.
        assertEquals(3f, MapFraming.gesture(cam, w, h, centroid, Offset.Zero, 50f, 0.5f..3f).z, tol)
        assertEquals(1f, MapFraming.gesture(cam, w, h, centroid, Offset.Zero, Float.NaN, 0.5f..3f).z, tol)
    }

    @Test
    fun zoomRange_fromHalfTheFitTo30MetresAcross() {
        val (w, h) = cover
        val venueZ = MapFraming.fit(MapFraming.VENUE, w, h).z
        val r = MapFraming.zoomRange(fitZ = 2f, width = w, height = h)
        assertEquals(venueZ / 2f, r.start, 1e-4f)
        assertEquals(minOf(w, h) / MapFraming.MIN_ZOOM_SPAN, r.endInclusive, 1e-4f)
        // Far away (tiny fit zoom): can zoom out to half of that.
        assertEquals(0.01f, MapFraming.zoomRange(0.02f, w, h).start, 1e-6f)
    }

    @Test
    fun boundsAndLabelSide() {
        assertEquals(null, MapFraming.bounds(listOf(Offset(Float.NaN, 1f))))
        assertEquals(Rect(1f, 2f, 5f, 8f), MapFraming.bounds(listOf(Offset(5f, 2f), Offset(1f, 8f))))
        assertFalse(MapFraming.labelOnLeft(pinX = 100f, width = 411f, gap = 16f, labelWidth = 34f))
        assertTrue(MapFraming.labelOnLeft(pinX = 380f, width = 411f, gap = 16f, labelWidth = 34f))
    }
}
