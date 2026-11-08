package app.kcna26.ui.directions

import androidx.compose.animation.core.AnimationVector3D
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.TwoWayConverter
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.geometry.Offset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlin.math.exp
import kotlin.math.ln

/**
 * The Directions map's camera.
 *
 * - **Following** (the default): the map frames the route, me and the destination
 *   ([MapFraming.fit]), re-framing smoothly when the route changes or I walk out of frame.
 * - **Manual**: after a pinch or pan the camera stays where the user put it (the destination
 *   pin never leaves the view) until [refit].
 *
 * Saved with [Saver] so fold/unfold keeps the mode; a following camera re-fits the new
 * screen, a manual one keeps its centre and zoom (in dp per metre).
 */
@Stable
class MapCameraState internal constructor(follow: Boolean, camera: MapCamera?) {

    /** Auto-framing is on. */
    var follow: Boolean by mutableStateOf(follow)
        private set

    /** What the map shows; null until the map has been laid out once. */
    var camera: MapCamera? by mutableStateOf(camera)
        private set

    private var refits by mutableIntStateOf(0)
    private var job: Job? = null

    /** Where the running animation is heading (null when idle). */
    private var goal: MapCamera? = null

    /** The view size framing last ran for (dp); a change means snap, not animate. */
    private var viewport: Pair<Float, Float>? = null

    /** Back to auto-framing, animated (the re-fit button; also a new From choice). */
    fun refit() {
        follow = true
        refits++
    }

    /**
     * Runs while the map is on screen; restarted by the caller whenever the view size, the
     * route or the destination changes. [me] is my position in map units, or null.
     */
    internal suspend fun frame(width: Float, height: Float, route: List<Offset>, dest: Offset, me: State<Offset?>) = coroutineScope {
        val resized = viewport != (width to height)
        viewport = width to height
        var first = true
        var seenRefits = refits
        snapshotFlow { Triple(follow, me.value, refits) }.collect { (following, m, r) ->
            val start = first
            first = false
            val asked = r != seenRefits
            seenRefits = r
            val cam = camera
            if (!following) {
                stop()
                camera = MapFraming.keepInView(cam ?: fitFor(route, dest, m, width, height), width, height, dest)
                return@collect
            }
            val target = fitFor(route, dest, m, width, height)
            when {
                cam == null || (start && resized) -> {
                    stop()
                    camera = target
                }
                start || asked -> animateTo(this, target)
                m != null && !MapFraming.inFrame(goal ?: cam, width, height, m) -> animateTo(this, target)
            }
        }
    }

    /** One pinch/pan step in dp (see [MapFraming.gesture]); switches to manual. */
    internal fun onGesture(
        width: Float,
        height: Float,
        centroid: Offset,
        pan: Offset,
        zoom: Float,
        route: List<Offset>,
        dest: Offset,
        me: Offset?,
    ) {
        val cam = camera ?: return
        stop()
        follow = false
        val range = MapFraming.zoomRange(fitFor(route, dest, me, width, height).z, width, height)
        val moved = MapFraming.gesture(cam, width, height, centroid, pan, zoom, range)
        camera = MapFraming.keepInView(moved, width, height, dest)
    }

    private fun fitFor(route: List<Offset>, dest: Offset, me: Offset?, width: Float, height: Float): MapCamera =
        MapFraming.fit(MapFraming.frameBounds(route, dest, me), width, height)

    private fun animateTo(scope: CoroutineScope, target: MapCamera) {
        val from = camera ?: target
        job?.cancel()
        goal = target
        job = scope.launch {
            animate(CameraConverter, from, target, animationSpec = tween(FRAME_MS, easing = FastOutSlowInEasing)) { v, _ ->
                camera = v
            }
        }
    }

    private fun stop() {
        job?.cancel()
        job = null
        goal = null
    }

    companion object {
        const val FRAME_MS = 650

        /** Centre animates linearly and zoom on a log scale, so big zoom changes feel even. */
        private val CameraConverter: TwoWayConverter<MapCamera, AnimationVector3D> = TwoWayConverter(
            convertToVector = { AnimationVector3D(it.cx, it.cy, ln(it.z)) },
            convertFromVector = { MapCamera(it.v1, it.v2, exp(it.v3)) },
        )

        val Saver: Saver<MapCameraState, Any> = listSaver(
            save = { s ->
                val c = s.camera
                if (s.follow || c == null) listOf(true) else listOf(false, c.cx, c.cy, c.z)
            },
            restore = { l ->
                if (l[0] as Boolean) {
                    MapCameraState(true, null)
                } else {
                    MapCameraState(false, MapCamera(l[1] as Float, l[2] as Float, l[3] as Float))
                }
            },
        )
    }
}

/** The map camera, kept through fold/unfold and process death. */
@Composable
fun rememberMapCameraState(): MapCameraState = rememberSaveable(saver = MapCameraState.Saver) { MapCameraState(true, null) }
