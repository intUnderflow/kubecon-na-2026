package app.kcna26.reminders

import android.content.SharedPreferences

/**
 * Remembers which reminder alarms are armed (their [ReminderPlanner.key]s), so the next
 * reschedule can cancel the ones that no longer apply, for example after "I'm speaking
 * as" changes to someone else or None. Prefs file [PREFS].
 */
class ReminderStore(private val prefs: SharedPreferences) {

    /** Keys armed by the last reschedule. */
    fun armed(): Set<String> = prefs.getStringSet(KEY_ARMED, null)?.toSet().orEmpty()

    /** Replaces the armed set. Skips the write when nothing changed. */
    fun setArmed(keys: Set<String>) {
        if (keys == armed()) return
        prefs.edit().apply { if (keys.isEmpty()) remove(KEY_ARMED) else putStringSet(KEY_ARMED, keys.toSet()) }.apply()
    }

    companion object {
        const val PREFS = "kcna26.reminders"
        private const val KEY_ARMED = "armed"
    }
}
