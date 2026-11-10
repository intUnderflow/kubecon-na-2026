package app.kcna26.nav

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Full screens. Session details are not a screen: see [NavViewModel.openSessionId]. */
sealed interface Screen {
    /** Stable string form, stored in SavedStateHandle and used as the SaveableStateHolder key. */
    val key: String

    data object Schedule : Screen {
        override val key = "schedule"
    }

    data object Settings : Screen {
        override val key = "settings"
    }

    data class Directions(val sessionId: String) : Screen {
        override val key = "directions:$sessionId"
    }

    companion object {
        /**
         * Null for keys this version doesn't know, e.g. "unconf" from an older install (the
         * Unconference screen was removed): restored stacks drop them and fall back to the Schedule.
         */
        fun decode(key: String): Screen? = when {
            key == Schedule.key -> Schedule
            key == Settings.key -> Settings
            key.startsWith("directions:") -> Directions(key.removePrefix("directions:"))
            else -> null
        }
    }
}

/**
 * Navigation state, activity-scoped and kept in SavedStateHandle so it survives
 * fold/unfold recreation and process death:
 * - [stack]: back stack of full screens, Schedule at the bottom.
 * - [openSessionId]: the session shown in the details sheet (compact) or pane (wide).
 *   It stays set while Directions is on top, so back returns to the same details.
 *
 * A restored stack keeps only the screens [Screen.decode] knows (stale keys such as an older
 * install's "unconf" are dropped) and is written back cleaned.
 */
class NavViewModel(private val handle: SavedStateHandle) : ViewModel() {

    private val _stack = MutableStateFlow(decode(restoredKeys()))

    init {
        handle[KEY_STACK] = ArrayList(_stack.value.map { it.key })
    }

    /** Back stack, bottom first; always starts with [Screen.Schedule]. */
    val stack: StateFlow<List<Screen>> = _stack.asStateFlow()

    /** Session shown in the details sheet/pane, or null. */
    val openSessionId: StateFlow<String?> = handle.getStateFlow(KEY_SESSION, null)

    val current: Screen get() = _stack.value.last()

    fun push(screen: Screen) {
        val s = _stack.value
        if (s.last() == screen) return
        setStack(s + screen)
    }

    /** Pops the top screen; false if already at the Schedule. */
    fun pop(): Boolean {
        val s = _stack.value
        if (s.size <= 1) return false
        setStack(s.dropLast(1))
        return true
    }

    fun openSession(sessionId: String) {
        handle[KEY_SESSION] = sessionId
    }

    fun closeSession() {
        handle[KEY_SESSION] = null
    }

    fun openSettings() = push(Screen.Settings)

    fun openDirections(sessionId: String) = push(Screen.Directions(sessionId))

    /** From a reminder notification: Schedule (with that session's details underneath) → Directions. */
    fun openDirectionsFromNotification(sessionId: String) {
        handle[KEY_SESSION] = sessionId
        setStack(listOf(Screen.Schedule, Screen.Directions(sessionId)))
    }

    private fun setStack(screens: List<Screen>) {
        val fixed = decode(screens.map { it.key })
        _stack.value = fixed
        handle[KEY_STACK] = ArrayList(fixed.map { it.key })
    }

    private fun decode(raw: List<String>): List<Screen> =
        listOf(Screen.Schedule) + raw.mapNotNull(Screen::decode).filter { it != Screen.Schedule }

    /** The saved stack's keys; anything unexpected in the handle counts as no saved stack. */
    private fun restoredKeys(): List<String> =
        (runCatching { handle.get<Any>(KEY_STACK) }.getOrNull() as? List<*>)?.filterIsInstance<String>().orEmpty()

    private companion object {
        const val KEY_STACK = "nav.stack"
        const val KEY_SESSION = "nav.session"
    }
}
