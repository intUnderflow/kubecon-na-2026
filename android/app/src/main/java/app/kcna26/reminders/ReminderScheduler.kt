package app.kcna26.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import app.kcna26.KcnaApp
import app.kcna26.appGraph
import app.kcna26.time.realEpochMillis
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Arms the talk reminders: 30 and 10 minutes before each of the speaker's own sessions
 * (`isMine(s, settings.speakingAs)`), and one "Remind me before sessions I'm going to"
 * minutes before each starred session (`going.ids`, `going.remindMinutes`; Off = none).
 *
 * [reschedule] is called by MainActivity on every fresh start, by [BootReceiver] after a
 * reboot or app update, and by the App whenever "I'm speaking as", the stars, the
 * "Going" reminder time or the debug fake time changes. It is cheap and idempotent: it cancels every alarm it armed before that is no
 * longer planned (tracked in [ReminderStore]) and re-arms the planned ones, which
 * replaces them in place.
 *
 * Exact alarms (`setExactAndAllowWhileIdle`) when `canScheduleExactAlarms()`, otherwise
 * inexact ones (`setAndAllowWhileIdle`), silently: the user is never prompted.
 */
object ReminderScheduler {

    /** Broadcast action of the alarms (explicit to [ReminderReceiver]). */
    const val ACTION_REMIND = "app.kcna26.action.REMIND"
    const val EXTRA_SESSION_ID = "app.kcna26.extra.REMINDER_SESSION_ID"
    const val EXTRA_MINUTES_BEFORE = "app.kcna26.extra.REMINDER_MINUTES_BEFORE"

    /** Serialises reschedules so the last call (the newest setting) always wins. */
    private val mutex = Mutex()

    /** Re-plans and re-arms all reminders. Returns at once; the work runs in the background. */
    fun reschedule(context: Context) {
        val app = context.applicationContext
        reminderScope(app).launch { rescheduleNow(app) }
    }

    /**
     * The work of [reschedule], for callers that must wait for it (receivers using
     * goAsync). Never throws. Returns the number of reminders armed.
     */
    suspend fun rescheduleNow(context: Context): Int = mutex.withLock {
        try {
            doReschedule(context.applicationContext)
        } catch (e: Exception) {
            Log.e(KcnaApp.TAG, "reminders: reschedule failed", e)
            0
        }
    }

    private suspend fun doReschedule(context: Context): Int {
        val graph = context.appGraph
        val repo = graph.awaitRepository()
        val me = graph.settings.speakingAs.value
        val going = graph.going.ids.value
        val goingMinutes = graph.going.remindMinutes.value
        val clock = graph.clock
        val store = ReminderStore(context.getSharedPreferences(ReminderStore.PREFS, Context.MODE_PRIVATE))
        val armed = store.armed()
        // armed: a "Going" reminder whose new, longer lead time is already past keeps its armed one.
        val plan = ReminderPlanner.plan(repo.sessions, repo.rooms, me, clock.now(), going, goingMinutes, armed)

        val planned = plan.mapTo(LinkedHashSet()) { it.key }
        val am = context.getSystemService(AlarmManager::class.java)
        if (am == null) {
            Log.w(KcnaApp.TAG, "reminders: no AlarmManager")
            return 0
        }

        ReminderNotifier.ensureChannel(context)

        // Cancel what no longer applies (the setting changed, or the alarm already fired).
        val stale = armed - planned
        for (key in stale) {
            val (id, minutes) = ReminderPlanner.parseKey(key) ?: continue
            cancelAlarm(context, am, id, minutes)
        }
        // A reminder still showing for a session that is no longer mine or starred goes too.
        val wanted = repo.sessions.filter { ReminderPlanner.specFor(it, me, going, goingMinutes) != null }.mapTo(HashSet()) { it.id }
        ReminderNotifier.shownSessionIds(context).filterNot { it in wanted }.forEach { ReminderNotifier.cancel(context, it) }

        val exact = canScheduleExact(am)
        var exactCount = 0
        for (r in plan) {
            if (arm(context, am, r.sessionId, r.minutesBefore, clock.realEpochMillis(r.triggerAt), exact)) exactCount++
        }
        store.setArmed(planned)
        Log.i(
            KcnaApp.TAG,
            "reminders: me=${me ?: "None"} going=${going.size}@${goingMinutes}m armed=${plan.size} (exact=$exactCount) cancelled=${stale.size} " +
                "next=${plan.firstOrNull()?.let { "${it.key}@${it.triggerAt}" } ?: "none"}",
        )
        return plan.size
    }

    private fun canScheduleExact(am: AlarmManager): Boolean =
        try {
            am.canScheduleExactAlarms()
        } catch (e: RuntimeException) {
            false
        }

    /**
     * Arms one alarm at real wall-clock [atMillis]; re-arming the same reminder replaces
     * it. Returns true if it went in as an exact alarm.
     */
    private fun arm(context: Context, am: AlarmManager, sessionId: String, minutes: Int, atMillis: Long, exact: Boolean): Boolean {
        val pi = PendingIntent.getBroadcast(
            context,
            ReminderPlanner.requestCode(sessionId, minutes),
            alarmIntent(context, sessionId, minutes),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        if (exact) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
                return true
            } catch (e: SecurityException) {
                // Exact-alarm access was revoked between the check and the call: go inexact.
            }
        }
        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
        } catch (e: RuntimeException) {
            Log.w(KcnaApp.TAG, "reminders: can't arm $sessionId/$minutes", e)
        }
        return false
    }

    private fun cancelAlarm(context: Context, am: AlarmManager, sessionId: String, minutes: Int) {
        val pi = PendingIntent.getBroadcast(
            context,
            ReminderPlanner.requestCode(sessionId, minutes),
            alarmIntent(context, sessionId, minutes),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
        ) ?: return
        am.cancel(pi)
        pi.cancel()
    }

    /** Explicit broadcast to [ReminderReceiver], with a data URI unique per session and offset. */
    private fun alarmIntent(context: Context, sessionId: String, minutes: Int): Intent =
        Intent(context, ReminderReceiver::class.java)
            .setAction(ACTION_REMIND)
            .setData(Uri.parse("kcna26://reminder/" + Uri.encode(sessionId) + "/" + minutes))
            .putExtra(EXTRA_SESSION_ID, sessionId)
            .putExtra(EXTRA_MINUTES_BEFORE, minutes)
}
