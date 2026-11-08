package app.kcna26.settings

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * User settings in SharedPreferences ("kcna26.settings"), exposed as StateFlows.
 * Setters write through immediately and update the flows synchronously.
 *
 * In Compose: `val me by graph.settings.speakingAs.collectAsStateWithLifecycle()`.
 * Elsewhere (receivers): `settings.speakingAs.value`.
 *
 * The App reschedules reminders whenever [speakingAs] changes, so callers of
 * [setSpeakingAs] don't need to.
 */
class SettingsStore(private val prefs: SharedPreferences) {

    private val _speakingAs = MutableStateFlow(readSpeakingAs())
    private val _directionsFrom = MutableStateFlow(readDirectionsFrom())
    private val _firstRunPending = MutableStateFlow(readFirstRunPending())

    /**
     * "I'm speaking as": a speaker name, or null for None. None until the user
     * picks someone (in the first-run picker or Settings).
     */
    val speakingAs: StateFlow<String?> = _speakingAs.asStateFlow()

    /**
     * True on a fresh install until the first-run picker ("Speaking at KubeCon?
     * Pick your name") is answered with a name or Skip. Never true once
     * [speakingAs] has been set explicitly (a name or None).
     */
    val firstRunPending: StateFlow<Boolean> = _firstRunPending.asStateFlow()

    /**
     * Directions "From" choice: [FROM_LIVE] ("LIVE", the default = My location),
     * an entrance key (E200S, EWT, EHY, E200W) or a room code.
     */
    val directionsFrom: StateFlow<String> = _directionsFrom.asStateFlow()

    /** False until the user has explicitly chosen a speaker or None (distinguishes "never set" from None). */
    val isSpeakingAsSet: Boolean get() = prefs.contains(KEY_SPEAKING_AS)

    /** Sets "I'm speaking as"; null means None. */
    fun setSpeakingAs(name: String?) {
        prefs.edit().putString(KEY_SPEAKING_AS, name ?: NONE).apply()
        _speakingAs.value = name
        _firstRunPending.value = false
    }

    /**
     * Answers the first-run picker: a [name] sets "I'm speaking as" (reminders
     * follow, like any change); null is Skip, which leaves it at None.
     */
    fun finishFirstRun(name: String?) {
        if (name != null) setSpeakingAs(name)
        prefs.edit().putBoolean(KEY_FIRST_RUN_DONE, true).apply()
        _firstRunPending.value = false
    }

    /**
     * The first-run sheet was swiped away, or closed with Back or a tap outside it: hide it for
     * this process only, so it asks again on the next cold start. Only a name or Skip
     * ([finishFirstRun]) is final.
     */
    fun dismissFirstRunForNow() {
        _firstRunPending.value = false
    }

    /** Forgets the choice, so [speakingAs] goes back to the default (None). */
    fun resetSpeakingAs() {
        prefs.edit().remove(KEY_SPEAKING_AS).apply()
        _speakingAs.value = null
    }

    fun setDirectionsFrom(value: String) {
        prefs.edit().putString(KEY_FROM, value).apply()
        _directionsFrom.value = value
    }

    /** True once the app has asked for POST_NOTIFICATIONS (MainActivity asks only once). */
    var notificationPermissionAsked: Boolean
        get() = prefs.getBoolean(KEY_NOTIF_ASKED, false)
        set(v) = prefs.edit().putBoolean(KEY_NOTIF_ASKED, v).apply()

    private fun readSpeakingAs(): String? {
        if (!prefs.contains(KEY_SPEAKING_AS)) return null
        val v = prefs.getString(KEY_SPEAKING_AS, null)
        return if (v == null || v == NONE) null else v
    }

    private fun readDirectionsFrom(): String = prefs.getString(KEY_FROM, null) ?: FROM_LIVE

    private fun readFirstRunPending(): Boolean =
        !prefs.contains(KEY_SPEAKING_AS) && !prefs.getBoolean(KEY_FIRST_RUN_DONE, false)

    companion object {
        const val PREFS = "kcna26.settings"
        /** The schedule's own "me" (schedule.json). No longer the default: fresh installs start at None. */
        const val DEFAULT_SPEAKER = "Lucy Sweet"
        const val FROM_LIVE = "LIVE"
        private const val KEY_SPEAKING_AS = "speakingAs"
        private const val KEY_FROM = "directionsFrom"
        private const val KEY_NOTIF_ASKED = "notifAsked"
        private const val KEY_FIRST_RUN_DONE = "firstRunDone"
        /** Stored value meaning "None" (no speaker has an empty name). */
        private const val NONE = ""
    }
}
