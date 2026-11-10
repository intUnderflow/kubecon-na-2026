package app.kcna26.ui.directions

import androidx.compose.runtime.saveable.SaverScope
import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MapCameraStateTest {

    private val scope = object : SaverScope {
        override fun canBeSaved(value: Any): Boolean = true
    }

    private fun roundTrip(state: MapCameraState): MapCameraState {
        val saved = with(MapCameraState.Saver) { scope.save(state) }!!
        return MapCameraState.Saver.restore(saved)!!
    }

    private val dest = Offset(419f, 206f) // 251 A–C

    @Test
    fun followsByDefault_andARestoredFollowingCameraRefitsTheNewScreen() {
        val s = MapCameraState(true, null)
        assertTrue(s.follow)
        assertNull(s.camera)
        val r = roundTrip(s)
        assertTrue(r.follow)
        assertNull(r.camera) // re-fitted to whichever fold screen comes next
    }

    @Test
    fun aManualCameraSurvivesFoldUnfold() {
        val cam = MapCamera(300f, 250f, 1.7f)
        val r = roundTrip(MapCameraState(false, cam))
        assertFalse(r.follow)
        assertEquals(cam, r.camera)
    }

    @Test
    fun pinchOrPanSwitchesToManual_keepsTheDestinationOnScreen_andRefitFollowsAgain() {
        val s = MapCameraState(false, MapCamera(256f, 255f, 1f))
        s.onGesture(411f, 485f, Offset(200f, 200f), Offset(0f, 0f), 2f, emptyList(), dest, null)
        assertFalse(s.follow)
        assertEquals(2f, s.camera!!.z, 1e-4f)
        // A huge drag would push the pin off screen: it stops at the edge instead.
        repeat(5) { s.onGesture(411f, 485f, Offset(200f, 200f), Offset(-2000f, -2000f), 1f, emptyList(), dest, null) }
        val c = s.camera!!
        assertTrue(MapFraming.inFrame(c, 411f, 485f, dest, MapFraming.PIN_EDGE - 0.01f))
        s.refit()
        assertTrue(s.follow)
    }

    @Test
    fun gestureBeforeTheFirstLayoutIsIgnored() {
        val s = MapCameraState(true, null)
        s.onGesture(411f, 485f, Offset(200f, 200f), Offset(10f, 0f), 1.5f, emptyList(), dest, null)
        assertTrue(s.follow)
        assertNull(s.camera)
    }
}
