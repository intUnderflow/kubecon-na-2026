package app.kcna26.nav

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.ui.adaptive.LocalWidthClass
import app.kcna26.ui.adaptive.currentWindowWidth
import app.kcna26.ui.directions.DirectionsScreen
import app.kcna26.ui.schedule.ScheduleScreen
import app.kcna26.ui.session.SessionDetails
import app.kcna26.ui.session.SessionSheet
import app.kcna26.ui.settings.SettingsScreen

/**
 * The navigation shell. Shows the top of [NavViewModel.stack] full screen; the
 * Schedule screen also hosts session details (sheet on compact, pane on wide).
 *
 * Every screen sits inside its own SaveableStateProvider keyed by [Screen.key],
 * so its rememberSaveable state survives going to another screen and back, and
 * fold/unfold. The ScheduleScreen call is at the same composition position in
 * the compact and wide layouts, so its rememberSaveable state also survives
 * switching between them.
 */
@Composable
fun AppNav(nav: NavViewModel) {
    val stack by nav.stack.collectAsStateWithLifecycle()
    val openSession by nav.openSessionId.collectAsStateWithLifecycle()
    val top = stack.last()

    BackHandler(enabled = stack.size > 1) { nav.pop() }

    val holder = rememberSaveableStateHolder()
    AnimatedContent(
        targetState = top,
        contentKey = { it.key },
        transitionSpec = { fadeIn(tween(140)) togetherWith fadeOut(tween(110)) },
        label = "screen",
    ) { screen ->
        holder.SaveableStateProvider(screen.key) {
            when (screen) {
                Screen.Schedule -> ScheduleLayer(nav, openSession)
                Screen.Settings -> SettingsScreen(onBack = { nav.pop() })
                is Screen.Directions -> DirectionsScreen(sessionId = screen.sessionId, onBack = { nav.pop() })
            }
        }
    }
}

/** Width of the schedule list pane in list–detail mode. */
private fun listPaneWidth(windowWidth: Dp): Dp = (windowWidth * 0.47f).coerceIn(360.dp, 480.dp)

@Composable
private fun ScheduleLayer(nav: NavViewModel, openSession: String?) {
    val repo = LocalAppGraph.current.repository
    val wide = LocalWidthClass.current.isWide
    val session = openSession?.takeIf { repo.session(it) != null }

    // Drop a stale id (e.g. restored from an older data set).
    if (openSession != null && session == null) {
        LaunchedEffect(openSession) { nav.closeSession() }
    }
    // Wide: back clears the selected session. Compact: the sheet handles back itself.
    BackHandler(enabled = wide && session != null) { nav.closeSession() }

    val windowWidth = currentWindowWidth()
    Row(Modifier.fillMaxSize()) {
        Box(
            if (wide) Modifier.width(listPaneWidth(windowWidth)).fillMaxHeight() else Modifier.fillMaxSize(),
        ) {
            ScheduleScreen(
                selectedSessionId = session,
                onOpenSession = nav::openSession,
                onOpenDirections = nav::openDirections,
                onOpenSettings = nav::openSettings,
                twoPane = wide,
            )
        }
        if (wide) {
            VerticalDivider(color = AppTheme.colors.line)
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .background(AppTheme.colors.surface),
            ) {
                if (session != null) {
                    key(session) {
                        SessionDetails(
                            sessionId = session,
                            onDirections = nav::openDirections,
                            contentPadding = WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical).asPaddingValues(),
                            onClose = nav::closeSession,
                        )
                    }
                } else {
                    EmptyDetailsHint()
                }
            }
        }
    }

    if (!wide && session != null) {
        SessionSheet(
            sessionId = session,
            onDismiss = nav::closeSession,
            onDirections = nav::openDirections,
        )
    }
}

@Composable
private fun EmptyDetailsHint() {
    Column(
        Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CapsText("Pick a session", AppTheme.type.dayHeading, color = AppTheme.colors.ink)
        Text(
            "Its details, speakers and directions show up here.",
            style = AppTheme.type.body,
            color = AppTheme.colors.muted,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(top = 8.dp)
                .widthIn(max = 360.dp),
        )
    }
}
