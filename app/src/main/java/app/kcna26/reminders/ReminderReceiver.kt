package app.kcna26.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import app.kcna26.KcnaApp
import app.kcna26.appGraph
import java.time.Duration

/**
 * Receives the alarms armed by [ReminderScheduler] and posts "Your talk in 10 min ·
 * Grand Ballroom GI, Level 1" (my talks) or "Starting in 10 min · Grand Ballroom GI,
 * Level 1" (starred "Going" sessions). Declared in the manifest as
 * `.reminders.ReminderReceiver` (exported=false).
 *
 * Re-checks everything at firing time: the session must still be mine (current "I'm
 * speaking as") or still starred with this reminder time (or a shorter one the planner
 * kept, see [ReminderPlanner.accepts]), and not started yet (a late
 * alarm, e.g. right after boot, is dropped). The minutes shown are the real minutes left,
 * in case an inexact alarm ran late.
 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ReminderScheduler.ACTION_REMIND) return
        val key = keyOf(intent) ?: return
        val app = context.applicationContext
        goAsyncWork(app) { remind(app, key.first, key.second) }
    }

    /** The session id and offset, from the extras or else the data URI kcna26://reminder/<id>/<minutes>. */
    private fun keyOf(intent: Intent): Pair<String, Int>? {
        val id = intent.getStringExtra(ReminderScheduler.EXTRA_SESSION_ID)
        val minutes = intent.getIntExtra(ReminderScheduler.EXTRA_MINUTES_BEFORE, -1)
        if (id != null && minutes > 0) return id to minutes
        val segs = intent.data?.pathSegments.orEmpty()
        val m = segs.getOrNull(1)?.toIntOrNull() ?: return null
        return segs[0] to m
    }

    private suspend fun remind(context: Context, sessionId: String, minutesBefore: Int) {
        val graph = context.appGraph
        val repo = graph.awaitRepository()
        val session = repo.session(sessionId) ?: return
        val me = graph.settings.speakingAs.value
        val going = graph.going
        val spec = ReminderPlanner.specFor(session, me, going.ids.value, going.remindMinutes.value)
        if (spec == null || !ReminderPlanner.accepts(spec, minutesBefore)) {
            Log.i(KcnaApp.TAG, "reminders: $sessionId/$minutesBefore skipped, not mine or going any more")
            return
        }
        val now = graph.clock.now()
        val minutesLeft = ReminderPlanner.minutesLeftToShow(session.start, minutesBefore, now, spec.offsets)
        if (minutesLeft == null) {
            Log.i(KcnaApp.TAG, "reminders: $sessionId/$minutesBefore skipped as stale at $now")
            return
        }
        val text = ReminderPlanner.text(spec.kind, minutesLeft, repo.roomOf(session))
        val untilEnd = Duration.between(now, session.effectiveEnd).toMillis()
        val posted = ReminderNotifier.post(
            context, sessionId, minutesBefore, session.title, text, untilEnd, ReminderNotifier.channelFor(spec.kind),
        )
        Log.i(KcnaApp.TAG, "reminders: $sessionId/$minutesBefore \"$text\" posted=$posted")
    }
}
