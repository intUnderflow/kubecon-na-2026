package app.kcna26.ui.session

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.details.DetailsResult
import app.kcna26.theme.AppTheme
import app.kcna26.theme.Dimens
import app.kcna26.ui.adaptive.LocalWidthClass
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/*
 * OWNER: details. Port of schedule_app.js sheetHTML. The web's inline wayfinding is the
 * full-screen Directions screen now, opened with the pinned Directions button.
 */

/**
 * The session details content. Used as the right-hand pane on wide screens (unfolded) and
 * inside [SessionSheet] on compact screens. Scrolls on its own; the Directions button stays
 * pinned at the bottom, within thumb reach.
 *
 * @param sessionId session to show (the shell only passes known ids).
 * @param onDirections open the full-screen Directions for this session.
 * @param contentPadding window-inset padding the container wants applied inside the scroll
 *   (the pane passes status/navigation bar insets; the sheet passes none).
 * @param onClose when non-null (pane), show a close button that clears the selection.
 */
@Composable
fun SessionDetails(
    sessionId: String,
    onDirections: (sessionId: String) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(),
    onClose: (() -> Unit)? = null,
) {
    SessionDetailsContent(
        sessionId = sessionId,
        onDirections = onDirections,
        modifier = modifier.fillMaxSize(),
        contentPadding = contentPadding,
        onClose = onClose,
        inSheet = false,
    )
}

/**
 * Compact (cover screen) wrapper: shows [SessionDetails] in a ModalBottomSheet over the
 * schedule. [onDismiss] is called on swipe-down, scrim tap, back, or the × button.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionSheet(
    sessionId: String,
    onDismiss: () -> Unit,
    onDirections: (sessionId: String) -> Unit,
) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val colors = AppTheme.colors
    val close: () -> Unit = {
        scope.launch { state.hide() }.invokeOnCompletion { if (!state.isVisible) onDismiss() }
    }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        shape = RoundedCornerShape(topStart = Dimens.sheetRadius, topEnd = Dimens.sheetRadius),
        containerColor = colors.surface,
        contentColor = colors.ink,
        scrimColor = colors.scrim,
        // Our own grab bar sits beside the × button, like the web's .grab / .x.
        dragHandle = null,
    ) {
        key(sessionId) {
            SessionDetailsContent(
                sessionId = sessionId,
                onDirections = onDirections,
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(),
                onClose = close,
                inSheet = true,
            )
        }
    }
}

/** Shared by the pane and the sheet. [inSheet]: wrap content height (the sheet sizes itself). */
@Composable
private fun SessionDetailsContent(
    sessionId: String,
    onDirections: (String) -> Unit,
    modifier: Modifier,
    contentPadding: PaddingValues,
    onClose: (() -> Unit)?,
    inSheet: Boolean,
) {
    val graph = LocalAppGraph.current
    val repo = graph.repository
    val session = repo.session(sessionId)
    val colors = AppTheme.colors
    if (session == null) {
        Box(modifier.padding(contentPadding).padding(24.dp)) {
            Text("This session is no longer in the schedule.", style = AppTheme.type.body, color = colors.muted)
        }
        return
    }
    val room = repo.roomOf(session)
    val me by graph.settings.speakingAs.collectAsStateWithLifecycle()

    // Details: synchronous when already known (bundled, summit, cached this process), else loaded
    // off the main thread. "Loading…" only appears if that takes noticeably long.
    val details = graph.details
    val initial = remember(details, sessionId) { details.peekResult(sessionId) }
    val result by produceState(initial, details, sessionId) {
        value = initial // a new data set (live update) brings its own details
        if (value == null || value == DetailsResult.Unavailable) value = details.load(sessionId)
    }
    var showLoading by remember(sessionId) { mutableStateOf(false) }
    if (result == null) {
        LaunchedEffect(sessionId) {
            delay(LOADING_DELAY_MS)
            showLoading = true
        }
    }

    // Survives Directions-and-back and process death; follows the session between the sheet
    // (folded) and the pane (unfolded) across fold/unfold recreation.
    val scroll = rememberDetailsScrollState(sessionId)

    val uriHandler = LocalUriHandler.current
    val openUrl: (String) -> Unit = remember(uriHandler) {
        { url ->
            try {
                uriHandler.openUri(url)
            } catch (e: Exception) {
                // No browser (or a bad URL): nothing to do, never crash.
            }
        }
    }

    val wide = LocalWidthClass.current.isWide && !inSheet
    val hPad = if (wide) 24.dp else 18.dp
    val top = contentPadding.calculateTopPadding()
    val bottom = contentPadding.calculateBottomPadding()

    Column(modifier) {
        Box(Modifier.weight(1f, fill = !inSheet)) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(scroll)
                    .padding(start = hPad, end = hPad, top = top + if (inSheet) 0.dp else 20.dp, bottom = 8.dp),
            ) {
                Column(Modifier.widthIn(max = Dimens.maxTextWidth)) {
                    if (inSheet) GrabBar()
                    DetailsBody(
                        session = session,
                        repo = repo,
                        room = room,
                        result = result,
                        showLoading = showLoading,
                        me = me,
                        reserveCloseSpace = onClose != null,
                        openUrl = openUrl,
                    )
                }
            }
            if (onClose != null) {
                CloseButton(
                    onClick = onClose,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = top + if (inSheet) 8.dp else 4.dp, end = hPad - 10.dp),
                )
            }
        }
        DirectionsBar(
            session = session,
            room = room,
            onDirections = onDirections,
            showDivider = { scroll.canScrollForward },
            horizontalPadding = hPad,
            bottomPadding = bottom,
        )
    }
}

private const val LOADING_DELAY_MS = 250L
