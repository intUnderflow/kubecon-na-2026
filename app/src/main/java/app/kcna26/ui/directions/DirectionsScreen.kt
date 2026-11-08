package app.kcna26.ui.directions

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.location.Location
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.net.toUri
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.LifecycleStartEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.kcna26.LocalAppGraph
import app.kcna26.data.PointXY
import app.kcna26.data.Room
import app.kcna26.data.Session
import app.kcna26.data.Venue
import app.kcna26.route.FloorReminder
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.time.TimeFormat
import app.kcna26.ui.adaptive.LocalWidthClass

/**
 * Directions to a session's room (redesigned as a live map, no compass
 * arrow and no Google Maps button; web: wayHTML, lvPaint, mapSVG).
 *
 * - Header: the room's level, building and name in large type ("LEVEL 2 · SALT PALACE · 251 A–C").
 * - A big live north-up [VenueMap]: route, me (dot, accuracy circle, heading cone), destination.
 * - Under it: the live distance and accuracy, the floor instruction, "You’re about here",
 *   weak-GPS and permission / no-fix states, the figure-8 hint.
 * - Then the From picker, the route summary and the turn-by-turn steps. With a fix, the From menu
 *   lists the entrances and rooms nearest first, frozen from the moment it opens ([FromMenu]).
 * - Location (fused, 1 s) and the compass (for the heading cone only) run only while this screen
 *   is started; the screen is kept on while it is open. Location permission is requested here.
 * - Compact (cover screen): one scrolling column, the map about half the screen high. Wide
 *   (inner screen): the map fills the left column; header, readout, From picker and steps scroll
 *   on the right. Either way the From picker sits above the steps, as the route texts say
 *   ("pick a room or entrance above").
 * - State survives fold/unfold: the ViewModel is activity-scoped per session; the open From
 *   picker and the map camera (auto-framing, or the user's pan and zoom) are saveable and hoisted
 *   above the compact/wide branch; the From choice is persisted in settings.
 */
@Composable
fun DirectionsScreen(sessionId: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val graph = LocalAppGraph.current
    val repo = graph.repository
    // Keyed by the data set too: after a live data update (room change) it routes with the new data.
    val vm: DirectionsViewModel = viewModel(key = "dir-$sessionId-${System.identityHashCode(repo)}") {
        DirectionsViewModel(repo, graph.router, graph.settings, graph.clock, sessionId)
    }
    val session = vm.session
    val room = vm.room
    Column(modifier.fillMaxSize()) {
        TopBar(session, onBack)
        if (session != null && room != null && vm.target != null) {
            LiveDirections(vm, room, repo.venue, LocalWidthClass.current.isWide)
        } else {
            Unavailable(session)
        }
    }
}

@Composable
private fun TopBar(session: Session?, onBack: () -> Unit) {
    val colors = AppTheme.colors
    val type = AppTheme.type
    val repo = LocalAppGraph.current.repository
    val label = remember(session) {
        val s = session ?: return@remember DirectionsText.TITLE
        listOfNotNull(DirectionsText.TITLE, repo.dayOf(s)?.dow?.let { "$it ${TimeFormat.range(s)}" }).joinToString(" · ")
    }
    Row(
        Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))
            .padding(start = 4.dp, end = Dimens.pagePadding, top = 4.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack, modifier = Modifier.size(Dimens.touchTarget)) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = colors.ink)
        }
        Spacer(Modifier.width(4.dp))
        Column(Modifier.weight(1f)) {
            CapsText(label, type.sectionLabel, color = colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(4.dp))
            Text(
                session?.title ?: DirectionsText.UNKNOWN_SESSION,
                style = type.cardTitle,
                color = colors.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** OFF ("Off-site") and rooms without a position: just the explanation and the official listing. */
@Composable
private fun Unavailable(session: Session?) {
    val context = LocalContext.current
    val bottom = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePadding)
            .padding(top = 8.dp, bottom = bottom + 24.dp),
    ) {
        Column(Modifier.widthIn(max = Dimens.maxTextWidth)) {
            if (session != null) {
                Text(
                    if (session.room == "OFF") DirectionsText.OFF_SITE else DirectionsText.NO_POSITION,
                    style = AppTheme.type.body.copy(fontSize = 17.sp),
                    color = AppTheme.colors.ink,
                )
                Spacer(Modifier.height(16.dp))
                OutlinedButton(
                    onClick = { openUrl(context, session.officialUrl) },
                    modifier = Modifier.heightIn(min = Dimens.touchTarget),
                    shape = RoundedCornerShape(10.dp),
                    border = BorderStroke(1.dp, AppTheme.colors.line),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = AppTheme.colors.ink),
                ) {
                    CapsText(DirectionsText.OFFICIAL_LISTING, AppTheme.type.button)
                }
            }
        }
    }
}

@Composable
private fun LiveDirections(vm: DirectionsViewModel, room: Room, venue: Venue, wide: Boolean) {
    val context = LocalContext.current
    val view = LocalView.current
    val target = vm.target ?: return
    val level = room.level ?: return

    KeepScreenOn()
    val permission = rememberLocationPermission()

    // Location: only while this screen is started and location is allowed.
    val tracker = remember(vm) {
        LocationTracker(
            context,
            onLocation = { loc: Location ->
                vm.onLocation(
                    loc.latitude,
                    loc.longitude,
                    if (loc.hasAccuracy()) loc.accuracy.toDouble() else 0.0,
                    if (loc.hasAltitude()) loc.altitude else null,
                )
                vm.setDeviceLocationOff(false)
            },
            onAvailability = { available ->
                vm.setDeviceLocationOff(!available && !LocationTracker.isLocationEnabled(context))
            },
            onFailure = vm::onLocationFailure,
        )
    }
    LifecycleStartEffect(tracker, permission.granted) {
        if (permission.granted) {
            vm.trackingStarted()
            tracker.start()
        }
        onStopOrDispose {
            tracker.stop()
            vm.trackingStopped()
        }
    }
    LifecycleResumeEffect(vm) {
        vm.setDeviceLocationOff(!LocationTracker.isLocationEnabled(context))
        onPauseOrDispose { }
    }

    // Compass, for the heading cone: only while started; follows the display the activity is on now.
    val compass = remember(view) { CompassSensor(context, view, vm::onAzimuth, vm::onSensorAccuracy) }
    LifecycleStartEffect(compass) {
        compass.start()
        onStopOrDispose { compass.stop() }
    }
    val configuration = LocalConfiguration.current
    LaunchedEffect(configuration) { compass.refreshDisplay() }

    val fixState = vm.fix.collectAsStateWithLifecycle()
    val noFix by vm.noFix.collectAsStateWithLifecycle()
    val deviceOff by vm.deviceLocationOff.collectAsStateWithLifecycle()
    val calibrate by vm.calibrate.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val from by vm.directionsFrom.collectAsStateWithLifecycle()

    val status = when {
        !permission.granted && permission.denied -> LocStatus.PERMISSION_DENIED
        permission.granted && deviceOff -> LocStatus.DEVICE_OFF
        noFix -> LocStatus.NO_FIX
        else -> LocStatus.SEARCHING
    }
    val statusState = rememberUpdatedState(status)
    // Recomputed per fix, but only recomposes readers when the text actually changes.
    val readout by remember(target, level) {
        derivedStateOf { DirectionsLogic.readout(target, level, fixState.value, statusState.value) }
    }
    val action: Pair<String, () -> Unit>? = when {
        readout.hasFix -> null
        status == LocStatus.PERMISSION_DENIED -> DirectionsText.ALLOW_LOCATION to permission.request
        status == LocStatus.DEVICE_OFF -> DirectionsText.TURN_ON_LOCATION to { openLocationSettings(context) }
        else -> null
    }
    val route = plan?.route
    val floor = remember(room, route) { FloorReminder.of(room, route) }
    val points = remember(route, room) { route?.points ?: listOfNotNull(room.pos) }

    // Hoisted above the compact/wide branch so they survive fold/unfold.
    var fromOpen by rememberSaveable { mutableStateOf(false) }
    // Where the open From menu is sorted from: the fix as it opened (null: none, so grouped). Kept
    // while it's open so new fixes don't move items; taken again on every opening.
    var fromAt by rememberSaveable(stateSaver = PointSaver) { mutableStateOf<PointXY?>(null) }
    val fromMenu = remember(vm.options, fromAt) { vm.options.menu(fromAt) }
    val fromPicker = FromPickerState(fromOpen, fromMenu) { open ->
        if (open && !fromOpen) fromAt = fixState.value?.pos
        fromOpen = open
    }
    val camera = rememberMapCameraState()
    val onFrom: (String) -> Unit = remember(vm, camera) {
        { key ->
            vm.setFrom(key)
            camera.refit() // a new route: show all of it
        }
    }

    val map: @Composable (Modifier) -> Unit = { m ->
        VenueMap(venue, room, points, route?.live == true, readout.here, fixState, vm.heading, camera, m)
    }
    val bottom = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()

    if (wide) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Row(
                Modifier
                    .fillMaxHeight()
                    .widthIn(max = 1180.dp)
                    .padding(horizontal = 8.dp),
            ) {
                Box(
                    Modifier
                        .weight(0.56f)
                        .fillMaxHeight()
                        .padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = bottom + 12.dp),
                ) {
                    map(Modifier.fillMaxSize())
                }
                Column(
                    Modifier
                        .weight(0.44f)
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState())
                        .padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = bottom + 24.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Column(Modifier.widthIn(max = Dimens.maxTextWidth), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        FloorHeadline(floor)
                        LiveReadout(readout, floor, action, calibrate)
                        RouteCard(plan, vm.options, from, onFrom, fromPicker)
                        MapNote()
                    }
                }
            }
        }
    } else {
        // About half the screen high, whatever the window (PROMPT redesign: 45–55 %).
        val mapHeight = (LocalWindowInfo.current.containerDpSize.height * 0.5f).coerceIn(240.dp, 640.dp)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Dimens.pagePadding)
                .padding(top = 4.dp, bottom = bottom + 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            FloorHeadline(floor)
            map(
                Modifier
                    .fillMaxWidth()
                    .height(mapHeight),
            )
            LiveReadout(readout, floor, action, calibrate)
            RouteCard(plan, vm.options, from, onFrom, fromPicker)
            MapNote()
        }
    }
}

/** Open state of the From picker and its (frozen) menu, owned by the screen. */
private class FromPickerState(val open: Boolean, val menu: FromMenu, val onOpenChange: (Boolean) -> Unit)

/** Saves the From menu's sort point across recreation (a fold/unfold with the menu open). */
private val PointSaver: Saver<PointXY?, DoubleArray> = Saver(
    save = { p -> p?.let { doubleArrayOf(it.x, it.y) } },
    restore = { a -> if (a.size == 2) PointXY(a[0], a[1]) else null },
)

private val CardShape = RoundedCornerShape(Dimens.bannerRadius)

/** From picker, summary, fallback note and the steps. */
@Composable
private fun RouteCard(
    plan: RoutePlan?,
    options: FromOptions,
    from: String,
    onSelect: (String) -> Unit,
    picker: FromPickerState,
) {
    val colors = AppTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.surface, CardShape)
            .border(1.dp, colors.line, CardShape)
            .padding(16.dp),
    ) {
        FromPicker(options, picker.menu, plan?.from ?: options.validate(from), onSelect, picker.open, picker.onOpenChange)
        if (plan != null) {
            if (plan.summary.isNotEmpty()) {
                CapsText(plan.summary, AppTheme.type.routeSummary, color = colors.ink, modifier = Modifier.padding(top = 14.dp))
            }
            if (plan.showFallbackNote) {
                Text(
                    DirectionsText.FALLBACK_NOTE,
                    style = AppTheme.type.tiny,
                    color = colors.muted,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            plan.route?.let { StepsList(it.steps, Modifier.padding(top = 8.dp)) }
        }
    }
}

/** The web's note under its map (without its Google Maps pin link). */
@Composable
private fun MapNote() {
    Text(
        DirectionsText.MAP_NOTE,
        style = AppTheme.type.tiny,
        color = AppTheme.colors.muted,
        modifier = Modifier.padding(horizontal = 2.dp),
    )
}

@Composable
private fun KeepScreenOn() {
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
}

/** Location permission for this screen: asked once on open, re-asked or sent to Settings on demand. */
private class LocationPermission(val granted: Boolean, val denied: Boolean, val request: () -> Unit)

@Composable
private fun rememberLocationPermission(): LocationPermission {
    val context = LocalContext.current
    val activity = LocalActivity.current
    var granted by remember { mutableStateOf(LocationTracker.hasLocationPermission(context)) }
    var asked by rememberSaveable { mutableStateOf(false) }
    var denied by rememberSaveable { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        granted = LocationTracker.hasLocationPermission(context)
        denied = !granted
    }
    LifecycleResumeEffect(Unit) {
        // Also catches a grant made in Android Settings while we were away.
        granted = LocationTracker.hasLocationPermission(context)
        if (granted) denied = false else if (asked) denied = true
        onPauseOrDispose { }
    }
    LaunchedEffect(Unit) {
        if (!granted && !asked) {
            asked = true
            launcher.launch(LocationTracker.PERMISSIONS)
        }
    }
    val request = remember(activity, launcher) {
        {
            val canAsk = activity != null &&
                LocationTracker.PERMISSIONS.any { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }
            if (canAsk) launcher.launch(LocationTracker.PERMISSIONS) else openAppSettings(context)
        }
    }
    return LocationPermission(granted, denied, request)
}

private fun openUrl(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
    } catch (_: ActivityNotFoundException) {
    } catch (_: SecurityException) {
    }
}

private fun openAppSettings(context: Context) {
    try {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
        )
    } catch (_: ActivityNotFoundException) {
    }
}

private fun openLocationSettings(context: Context) {
    try {
        context.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
    } catch (_: ActivityNotFoundException) {
    }
}
