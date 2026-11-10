package app.kcna26.going

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * RSVPs ("Going" in code): the starred sessions, and how long before them to send a reminder. Stored in
 * SharedPreferences ([PREFS]) and exposed as StateFlows. Setters write through at once and
 * update the flows synchronously, so they are safe to call from a click handler.
 *
 * Ids are kept exactly as starred: an id the current data doesn't have is ignored by the
 * schedule and the reminders, but stays here, so the star comes back if the session returns
 * in a later data set.
 *
 * The App reschedules the reminders whenever [ids] or [remindMinutes] change.
 */
class GoingStore(private val prefs: SharedPreferences) {

    private val _ids = MutableStateFlow(readIds())
    private val _remindMinutes = MutableStateFlow(readRemindMinutes())

    /** Starred session ids (unordered). */
    val ids: StateFlow<Set<String>> = _ids.asStateFlow()

    /**
     * "Remind me before sessions I'm going to": minutes before the start, one of
     * [REMIND_OPTIONS]; [REMIND_OFF] (0) is Off. Defaults to [DEFAULT_REMIND_MINUTES].
     */
    val remindMinutes: StateFlow<Int> = _remindMinutes.asStateFlow()

    fun isGoing(sessionId: String): Boolean = sessionId in _ids.value

    /** Stars or unstars [sessionId]. Returns the new state. */
    fun toggle(sessionId: String): Boolean {
        val now = !isGoing(sessionId)
        setGoing(sessionId, now)
        return now
    }

    fun setGoing(sessionId: String, going: Boolean) {
        var changed = false
        _ids.update { cur ->
            val next = if (going) cur + sessionId else cur - sessionId
            changed = next != cur
            next
        }
        if (changed) write()
    }

    /** Sets the reminder lead time; anything not in [REMIND_OPTIONS] is ignored. */
    fun setRemindMinutes(minutes: Int) {
        if (minutes !in REMIND_OPTIONS || minutes == _remindMinutes.value) return
        prefs.edit().putInt(KEY_REMIND, minutes).apply()
        _remindMinutes.value = minutes
    }

    private fun write() {
        // A fresh copy: SharedPreferences must never be handed a set it might see mutated.
        val snapshot = HashSet(_ids.value)
        prefs.edit().apply { if (snapshot.isEmpty()) remove(KEY_IDS) else putStringSet(KEY_IDS, snapshot) }.apply()
    }

    private fun readIds(): Set<String> = prefs.getStringSet(KEY_IDS, null)?.toSet().orEmpty()

    private fun readRemindMinutes(): Int =
        prefs.getInt(KEY_REMIND, DEFAULT_REMIND_MINUTES).takeIf { it in REMIND_OPTIONS } ?: DEFAULT_REMIND_MINUTES

    companion object {
        const val PREFS = "kcna26.going"
        const val REMIND_OFF = 0
        const val DEFAULT_REMIND_MINUTES = 10

        /** The settings choices, in order: Off, 5, 10, 15 min. */
        val REMIND_OPTIONS: List<Int> = listOf(REMIND_OFF, 5, 10, 15)

        private const val KEY_IDS = "ids"
        private const val KEY_REMIND = "remindMinutes"
    }
}
