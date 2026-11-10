package app.kcna26.ui.directions

import app.kcna26.TestData
import app.kcna26.data.PointXY
import org.junit.Assert.assertEquals
import org.junit.Test

class MapGeometryTest {

    @Test
    fun viewBoxTransform() {
        assertEquals(492f, MapGeometry.svgX(0.0))
        assertEquals(492f, MapGeometry.svgY(0.0))
        // 251 A–C at (−73, 286) → (419, 206).
        assertEquals(419f, MapGeometry.svgX(-73.0))
        assertEquals(206f, MapGeometry.svgY(286.0))
    }

    @Test
    fun accuracyCircleClamped8To250() {
        assertEquals(8f, MapGeometry.accuracyRadius(3.0))
        assertEquals(12f, MapGeometry.accuracyRadius(12.0))
        assertEquals(250f, MapGeometry.accuracyRadius(400.0))
    }

    @Test
    fun levelText() {
        assertEquals("L2", MapGeometry.levelText(2))
        assertEquals("L4", MapGeometry.levelText(4))
    }

    @Test
    fun zoneLabelsMatchTheWeb() {
        val zones = TestData.repo.venue.zones.associateBy { it.name }
        fun check(name: String, text: String, x: Float, y: Float) {
            val l = MapGeometry.zoneLabel(zones.getValue(name))
            assertEquals(text, l.text)
            assertEquals(x, l.x)
            assertEquals(y, l.y)
        }
        check("Hall DE", "Hall DE", 310f, 352f)
        check("Halls A–C", "Halls A–C", 310f, 206f)
        check("Halls 1–5", "Halls 1–5", 37f, 107f)
        check("Grand Ballroom", "Ballroom", 412f, 302f)
        check("Rooms 155 / 255", "155·255", 282f, 42f)
        assertEquals(5, zones.size)
    }

    @Test
    fun streetAndHyattLabels() {
        val names = MapGeometry.streetLabels.map { it.text }
        assertEquals(listOf("West Temple", "200 South", "100 South", "South Temple", "200 West", "300 W"), names)
        assertEquals(90f, MapGeometry.streetLabels.first().rotateDeg)
        assertEquals(414f, MapGeometry.hyattLabel.x)
        assertEquals(462f, MapGeometry.hyattLabel.y)
    }

    @Test
    fun staticRouteDropsTheLivePoint() {
        val pts = listOf(PointXY(0.0, 0.0), PointXY(1.0, 1.0), PointXY(2.0, 2.0))
        assertEquals(pts, MapGeometry.staticRoute(pts, live = false))
        assertEquals(pts.drop(1), MapGeometry.staticRoute(pts, live = true))
    }
}
