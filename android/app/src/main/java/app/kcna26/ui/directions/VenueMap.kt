package app.kcna26.ui.directions

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FitScreen
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.kcna26.data.PointXY
import app.kcna26.data.Room
import app.kcna26.data.Venue
import app.kcna26.geo.ArrowRotation
import app.kcna26.theme.AppColors
import app.kcna26.theme.AppTheme
import app.kcna26.theme.Barlow
import app.kcna26.theme.caps
import app.kcna26.ui.directions.MapGeometry.Anchor
import app.kcna26.ui.directions.MapGeometry.svgX
import app.kcna26.ui.directions.MapGeometry.svgY
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlin.math.max

/**
 * The live north-up venue map, the headline of the Directions screen (a zoomable port of
 * the web's mapSVG): streets, building outlines, hall zones, the dashed walking route (on a
 * live route its first point is me), me (dot, accuracy circle, heading cone) and the
 * destination pin labelled with its level.
 *
 * - [camera] auto-frames the route, me and the destination; pinch-zoom and pan switch to
 *   manual until the re-fit button. The destination is never pushed off the view.
 * - Lines and labels keep a constant on-screen size at any zoom; labels have a halo in the
 *   page colour so they read in light and dark, and hide when their zone is too small.
 * - Three graphics layers, so the 1 Hz fix, the heading cone and the pin's pulse each redraw
 *   only their own layer. [fix] and [heading] are read in the draw phase only.
 *
 * @param points route polyline in local metres; for a [live] route the first point is me.
 * @param here within "You’re about here" range: the destination pin is highlighted.
 */
@Composable
fun VenueMap(
    venue: Venue,
    room: Room,
    points: List<PointXY>,
    live: Boolean,
    here: Boolean,
    fix: State<Fix?>,
    heading: StateFlow<Double?>,
    camera: MapCameraState,
    modifier: Modifier = Modifier,
) {
    val pos = room.pos ?: return
    val level = room.level ?: return
    val colors = AppTheme.colors
    val measurer = rememberTextMeasurer(cacheSize = 24)
    val dest = remember(pos) { Offset(svgX(pos.x), svgY(pos.y)) }
    // The drawn polyline; for a live route the leg from me is drawn from the current fix.
    val route = remember(points, live) { MapGeometry.staticRoute(points, live).map { Offset(svgX(it.x), svgY(it.y)) } }
    val start = if (!live) route.firstOrNull() else null
    val me = remember(fix) { derivedStateOf { fix.value?.let { Offset(svgX(it.x), svgY(it.y)) } } }
    val cone = rememberConeAngle(heading)
    val reduceMotion = rememberReduceMotion()
    val pulse = if (reduceMotion) null else rememberInfiniteTransition(label = "pulse").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(if (here) 1200 else 1800, easing = LinearOutSlowInEasing), RepeatMode.Restart),
        label = "pulse",
    )
    val description = DirectionsText.mapDescription(room.venueCode, level)
    val shape = RoundedCornerShape(14.dp)
    val latestRoute by rememberUpdatedState(route)
    val latestDest by rememberUpdatedState(dest)

    BoxWithConstraints(
        modifier
            .clip(shape)
            .background(colors.bg)
            .border(1.dp, colors.line, shape)
            .semantics { contentDescription = description },
    ) {
        val w = maxWidth.value
        val h = maxHeight.value
        // Used only until the camera has run once (the first frame).
        val initial = remember(w, h, route, dest) {
            MapFraming.fit(MapFraming.frameBounds(route, dest, Snapshot.withoutReadObservation { me.value }), w, h)
        }
        LaunchedEffect(camera, w, h, route, dest) { camera.frame(w, h, route, dest, me) }
        val cam = { camera.camera ?: initial }

        Box(
            Modifier
                .matchParentSize()
                .pointerInput(camera) {
                    detectTransformGestures { centroid, pan, zoom, _ ->
                        val d = density
                        camera.onGesture(
                            size.width / d, size.height / d, centroid / d, pan / d, zoom,
                            latestRoute, latestDest, me.value,
                        )
                    }
                },
        ) {
            // 1. Base: streets, buildings, zones, labels, the route and (live) the leg from me.
            Spacer(
                Modifier
                    .matchParentSize()
                    .graphicsLayer()
                    .drawWithCache {
                        val base = MapBase(venue, route, start, colors, measurer, this)
                        onDrawBehind { with(base) { draw(cam(), if (live && route.isNotEmpty()) me.value else null) } }
                    },
            )
            // 2. The destination: pulse, pin and its level label.
            Spacer(
                Modifier
                    .matchParentSize()
                    .graphicsLayer()
                    .drawWithCache {
                        val label = measurer.measure(MapGeometry.levelText(level), pinLabelStyle(), density = this)
                        onDrawBehind { drawDestination(cam(), dest, label, here, pulse?.value, colors) }
                    },
            )
            // 3. Me: accuracy circle, heading cone, dot.
            Spacer(
                Modifier
                    .matchParentSize()
                    .graphicsLayer()
                    .drawWithCache {
                        val conePath = parsePath(MapGeometry.CONE_PATH)
                        onDrawBehind {
                            val f = fix.value ?: return@onDrawBehind
                            drawMe(cam(), f, cone.value, conePath, colors)
                        }
                    },
            )
        }
        NorthRose(colors, measurer, Modifier.align(Alignment.TopEnd).padding(8.dp))
        RefitButton(onClick = camera::refit, Modifier.align(Alignment.BottomEnd).padding(6.dp))
    }
}

/** The small "N" rose in the top-right corner (the map is always north-up). */
@Composable
private fun NorthRose(colors: AppColors, measurer: TextMeasurer, modifier: Modifier = Modifier) {
    val rose = remember { parsePath(MapGeometry.ROSE_PATH) }
    Canvas(modifier.size(34.dp)) {
        val c = Offset(size.width / 2f, size.height / 2f)
        val r = size.minDimension / 2f
        drawCircle(colors.surface, radius = r, center = c)
        drawCircle(colors.line, radius = r - 0.5.dp.toPx(), center = c, style = Stroke(1.dp.toPx()))
        val k = size.minDimension / 34f
        translate(c.x, c.y - 2.dp.toPx()) { scale(k, k, pivot = Offset.Zero) { drawPath(rose, colors.you) } }
        val n = measurer.measure("N", mapLabelStyle(10.sp, FontWeight.Bold), density = this)
        drawText(n, colors.ink, topLeft = Offset(c.x - n.size.width / 2f, c.y + 13.dp.toPx() - n.firstBaseline))
    }
}

/** Back to auto-framing (48 dp). */
@Composable
private fun RefitButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Surface(
        shape = CircleShape,
        color = colors.surface,
        contentColor = colors.ink,
        border = BorderStroke(1.dp, colors.line),
        shadowElevation = 2.dp,
        modifier = modifier.size(48.dp),
    ) {
        IconButton(onClick = onClick, colors = IconButtonDefaults.iconButtonColors(contentColor = colors.ink)) {
            Icon(Icons.Filled.FitScreen, contentDescription = DirectionsText.REFIT, modifier = Modifier.size(22.dp))
        }
    }
}

/**
 * The heading cone's angle (degrees clockwise from north), or null until the compass has a
 * heading. Always turns the short way round (the engine's [ArrowRotation]) and is animated
 * with a critically damped spring; read in the draw phase only.
 */
@Composable
private fun rememberConeAngle(heading: StateFlow<Double?>): State<Float?> {
    val angle = remember { Animatable(0f) }
    val visible = remember { mutableStateOf(false) }
    LaunchedEffect(heading) {
        val turns = ArrowRotation()
        heading.collectLatest { h ->
            if (h == null) {
                visible.value = false
                return@collectLatest
            }
            val v = turns.update(h).toFloat()
            if (!visible.value) {
                angle.snapTo(v)
                visible.value = true
            } else {
                angle.animateTo(v, spring(dampingRatio = 1f, stiffness = 300f))
            }
        }
    }
    return remember { derivedStateOf { if (visible.value) angle.value else null } }
}

private fun parsePath(d: String): Path = PathParser().parsePathString(d).toPath()

/** Map text: Barlow, .04em, upper-cased by the caller (web `.map text`). */
private fun mapLabelStyle(size: androidx.compose.ui.unit.TextUnit, weight: FontWeight = FontWeight.SemiBold) = TextStyle(
    fontFamily = Barlow,
    fontWeight = weight,
    fontSize = size,
    letterSpacing = 0.04.em,
)

/** The pin's "L2": white on pink, big enough to read at a glance in light and dark. */
private fun pinLabelStyle() = mapLabelStyle(16.sp, FontWeight.Bold).copy(letterSpacing = 0.06.em)

/** Draws [layout] with its baseline at screen point [at] (px), with a halo of [halo] behind it. */
private fun DrawScope.drawHaloText(
    layout: TextLayoutResult,
    at: Offset,
    anchor: Anchor,
    rotateDeg: Float,
    color: Color,
    halo: Color,
) {
    val w = layout.size.width.toFloat()
    val left = when (anchor) {
        Anchor.START -> at.x
        Anchor.MIDDLE -> at.x - w / 2f
        Anchor.END -> at.x - w
    }
    val topLeft = Offset(left, at.y - layout.firstBaseline)
    val haloStroke = Stroke(width = 3.dp.toPx(), join = StrokeJoin.Round)
    withTransform({ if (rotateDeg != 0f) rotate(rotateDeg, pivot = at) }) {
        drawText(layout, color = halo, topLeft = topLeft, drawStyle = haloStroke)
        // Fill must be explicit: a null drawStyle leaves the layout's paint on the halo's
        // Stroke, which drew every label as a thick unreadable outline on the phone.
        drawText(layout, color = color, topLeft = topLeft, drawStyle = Fill)
    }
}

/** Screen position (px) of map point [p] under [cam] in this draw scope. */
private fun DrawScope.screen(cam: MapCamera, p: Offset): Offset {
    val k = cam.z * density
    return Offset((p.x - cam.cx) * k + size.width / 2f, (p.y - cam.cy) * k + size.height / 2f)
}

/** Cached geometry and labels for the base layer; [draw] places them for a camera. */
private class MapBase(
    venue: Venue,
    route: List<Offset>,
    private val start: Offset?,
    private val colors: AppColors,
    measurer: TextMeasurer,
    density: androidx.compose.ui.unit.Density,
) {
    private val streets = venue.streets.map { Offset(svgX(it.from.x), svgY(it.from.y)) to Offset(svgX(it.to.x), svgY(it.to.y)) }
    private val sp = venue.buildings["SP"]?.let { polygon(it.outline) }
    private val hy = venue.buildings["HY"]?.let { b -> polygon(b.outline) to (b.outline.maxOf { it.x } - b.outline.minOf { it.x }).toFloat() }
    private val streetStyle = mapLabelStyle(12.sp)
    private val zoneStyle = mapLabelStyle(12.5.sp)
    private val streetLabels = MapGeometry.streetLabels.map { it to measurer.measure(it.text.caps(), streetStyle, density = density) }
    private val zones = venue.zones.map { z ->
        val rect = Rect(svgX(z.x0), svgY(z.y1), svgX(z.x1), svgY(z.y0))
        val label = MapGeometry.zoneLabel(z)
        Triple(rect, label, measurer.measure(label.text.caps(), zoneStyle, density = density))
    }
    private val hyattLabel = MapGeometry.hyattLabel.let { it to measurer.measure(it.text.caps(), zoneStyle, density = density) }
    private val routePath: Path? = if (route.size >= 2) {
        Path().apply {
            moveTo(route[0].x, route[0].y)
            for (i in 1 until route.size) lineTo(route[i].x, route[i].y)
        }
    } else {
        null
    }
    private val routeFirst: Offset? = route.firstOrNull()

    private fun polygon(points: List<PointXY>): Path = Path().apply {
        points.forEachIndexed { i, p -> if (i == 0) moveTo(svgX(p.x), svgY(p.y)) else lineTo(svgX(p.x), svgY(p.y)) }
        close()
    }

    /** [me] is set for a live route: the dashed leg from me to the route's first node. */
    fun DrawScope.draw(cam: MapCamera, me: Offset?) {
        val k = cam.z * density
        val dp = density
        withTransform({
            translate(size.width / 2f - cam.cx * k, size.height / 2f - cam.cy * k)
            scale(k, k, pivot = Offset.Zero)
        }) {
            // Strokes are given in map units, so divide on-screen sizes by k.
            val streetW = max(6f * k, 3f * dp) / k
            for ((a, b) in streets) drawLine(colors.line, a, b, strokeWidth = streetW, cap = StrokeCap.Round)
            val outline = Stroke(1.5f * dp / k)
            sp?.let {
                drawPath(it, colors.surface)
                drawPath(it, colors.muted, style = outline)
            }
            hy?.let { (p, _) ->
                drawPath(p, colors.mapHyatt)
                drawPath(p, colors.muted, style = outline)
            }
            val zoneStroke = Stroke(1.2f * dp / k, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f * dp / k, 3f * dp / k)))
            for ((rect, _, _) in zones) drawRect(colors.line, topLeft = rect.topLeft, size = rect.size, style = zoneStroke)

            // The route: a light casing, then the dashed ink line (web .ln).
            val casing = Stroke(7f * dp / k, cap = StrokeCap.Round, join = StrokeJoin.Round)
            val dash = PathEffect.dashPathEffect(floatArrayOf(7f * dp / k, 5f * dp / k))
            val line = Stroke(3f * dp / k, cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = dash)
            val leg = if (me != null && routeFirst != null) me to routeFirst else null
            leg?.let { (a, b) ->
                drawLine(colors.surface, a, b, strokeWidth = casing.width, cap = StrokeCap.Round, alpha = 0.85f)
            }
            routePath?.let { drawPath(it, colors.surface, style = casing, alpha = 0.85f) }
            leg?.let { (a, b) ->
                drawLine(colors.ink, a, b, strokeWidth = line.width, cap = StrokeCap.Round, pathEffect = dash)
            }
            routePath?.let { drawPath(it, colors.ink, style = line) }
            start?.let {
                drawCircle(colors.ink, radius = 7f * dp / k, center = it)
                drawCircle(colors.surface, radius = 7f * dp / k, center = it, style = Stroke(3f * dp / k))
            }
        }
        // Labels: constant size, hidden when there is no room for them.
        val zoomedOut = cam.z < STREET_LABEL_MIN_Z
        if (!zoomedOut) {
            for ((label, layout) in streetLabels) {
                drawHaloText(layout, screen(cam, Offset(label.x, label.y)), label.anchor, label.rotateDeg, colors.muted, colors.bg)
            }
        }
        val gap = 6f * dp
        for ((rect, label, layout) in zones) {
            if (rect.width * k < layout.size.width + gap || rect.height * k < layout.size.height + gap) continue
            drawHaloText(layout, screen(cam, Offset(label.x, label.y)), label.anchor, 0f, colors.muted, colors.surface)
        }
        hy?.let { (_, width) ->
            val (label, layout) = hyattLabel
            if (width * k >= layout.size.width + gap) {
                drawHaloText(layout, screen(cam, Offset(label.x, label.y)), label.anchor, 0f, colors.muted, colors.mapHyatt)
            }
        }
    }

    companion object {
        /** Below this zoom (dp per metre) the street names would crowd a tiny venue. */
        const val STREET_LABEL_MIN_Z = 0.45f
    }
}

/** The destination pin (web .dst), its pulse (.pulse) and the "L2" label pill. */
private fun DrawScope.drawDestination(
    cam: MapCamera,
    dest: Offset,
    label: TextLayoutResult,
    here: Boolean,
    pulse: Float?,
    colors: AppColors,
) {
    val c = screen(cam, dest)
    val dp = density
    if (here) drawCircle(colors.you, radius = 26f * dp, center = c, alpha = 0.18f)
    if (pulse != null) {
        // Web ping: scale .6 → 2.2 and fade out; stronger while "You’re about here".
        val k = 0.6f + (if (here) 2.6f else 1.6f) * pulse
        drawCircle(
            colors.you,
            radius = 11f * dp * k,
            center = c,
            alpha = (if (here) 0.95f else 0.8f) * (1f - pulse),
            style = Stroke((if (here) 3f else 2f) * dp),
        )
    } else {
        drawCircle(colors.you, radius = (if (here) 20f else 15f) * dp, center = c, alpha = 0.6f, style = Stroke(2f * dp))
    }
    val r = (if (here) 12f else 10f) * dp
    drawCircle(colors.you, radius = r, center = c)
    drawCircle(colors.surface, radius = r, center = c, style = Stroke(3f * dp))

    val padX = 6f * dp
    val padY = 3f * dp
    val pillW = label.size.width + 2 * padX
    val pillH = label.size.height + 2 * padY
    val gap = r + 6f * dp
    val left = if (MapFraming.labelOnLeft(c.x, size.width, gap, pillW, 4f * dp)) c.x - gap - pillW else c.x + gap
    val top = c.y - pillH / 2f
    drawRoundRect(colors.surface, topLeft = Offset(left - 1.5f * dp, top - 1.5f * dp), size = Size(pillW + 3f * dp, pillH + 3f * dp), cornerRadius = CornerRadius(7.5f * dp))
    drawRoundRect(colors.you, topLeft = Offset(left, top), size = Size(pillW, pillH), cornerRadius = CornerRadius(6f * dp))
    drawText(label, colors.onYou, topLeft = Offset(left + padX, top + padY))
}

/** Me (web #me): accuracy circle in metres, heading cone (once there is a heading), dot. */
private fun DrawScope.drawMe(cam: MapCamera, f: Fix, cone: Float?, conePath: Path, colors: AppColors) {
    val c = screen(cam, Offset(svgX(f.x), svgY(f.y)))
    val dp = density
    val me = colors.mapMe
    val r = MapGeometry.accuracyRadius(f.accuracyM) * cam.z * dp
    drawCircle(me, radius = r, center = c, alpha = 0.14f)
    drawCircle(me, radius = r, center = c, alpha = 0.45f, style = Stroke(1.5f * dp))
    if (cone != null) {
        val k = 40f * dp / 32f
        translate(c.x, c.y) {
            rotate(cone, pivot = Offset.Zero) { scale(k, k, pivot = Offset.Zero) { drawPath(conePath, me, alpha = 0.4f) } }
        }
    }
    drawCircle(me, radius = 8f * dp, center = c)
    drawCircle(colors.surface, radius = 8f * dp, center = c, style = Stroke(3f * dp))
}

/** True when the system "Remove animations" setting is on (the web honours prefers-reduced-motion). */
@Composable
private fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
}
