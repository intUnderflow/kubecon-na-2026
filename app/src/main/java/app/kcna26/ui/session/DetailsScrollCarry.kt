package app.kcna26.ui.session

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.ScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel

/**
 * Carries the details scroll position across fold/unfold. Folding swaps the wide pane for the
 * compact sheet (and back), so the composable sits at a different position after the activity is
 * recreated and positional `rememberSaveable` starts from the top. This activity-scoped
 * ViewModel survives the recreation and hands the position to the new instance once.
 * Closing the sheet or pane (no configuration change) carries nothing, so a fresh open starts
 * at the top like the web's `panel.scrollTop=0`.
 */
class DetailsScrollCarry : ViewModel() {
    private var sessionId: String? = null
    private var position = 0

    fun put(sessionId: String, position: Int) {
        this.sessionId = sessionId
        this.position = position
    }

    /** The carried position for [sessionId] (once), else 0. */
    fun take(sessionId: String): Int {
        val p = if (this.sessionId == sessionId) position else 0
        this.sessionId = null
        position = 0
        return p
    }
}

/**
 * The details ScrollState: positional `rememberSaveable` (so it survives going to Directions and
 * back, and process death), seeded from [DetailsScrollCarry] after a fold/unfold.
 */
@Composable
internal fun rememberDetailsScrollState(sessionId: String): ScrollState {
    val carry: DetailsScrollCarry = viewModel(key = "kcna26.session.scrollCarry")
    val scroll = rememberSaveable(sessionId, saver = ScrollState.Saver) { ScrollState(carry.take(sessionId)) }
    val activity = LocalActivity.current
    DisposableEffect(sessionId, scroll, activity) {
        onDispose {
            if (activity?.isChangingConfigurations == true) carry.put(sessionId, scroll.value)
        }
    }
    return scroll
}
