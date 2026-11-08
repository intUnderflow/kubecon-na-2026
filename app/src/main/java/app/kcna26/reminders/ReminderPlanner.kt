package app.kcna26.reminders

import app.kcna26.data.Room
import app.kcna26.data.Session
import app.kcna26.data.isMine
import app.kcna26.time.TimeFormat
import java.time.Duration
import java.time.Instant

/**
 * One reminder to arm: notify [minutesBefore] minutes before session [sessionId] starts.
 *
 * [title] is the session title; [text] is the notification line, e.g.
 * "Your talk in 10 min · Grand Ballroom GI, Level 1" ([ReminderKind.MINE]) or
 * "Starting in 10 min · Grand Ballroom GI, Level 1" ([ReminderKind.GOING]).
 */
data class PlannedReminder(
    val sessionId: String,
    val triggerAt: Instant,
    val minutesBefore: Int,
    val title: String,
    val text: String,
    val kind: ReminderKind = ReminderKind.MINE,
) {
    /** Stable identity of this alarm ("sessionId/minutes"), stored to cancel it later. */
    val key: String get() = ReminderPlanner.key(sessionId, minutesBefore)
}

/** Why a session has reminders: I speak at it (30 and 10 min), or I starred it ("Going", one reminder). */
enum class ReminderKind { MINE, GOING }

/** The reminders one session gets: [kind] and the minutes before its start, earliest first. */
data class ReminderSpec(val kind: ReminderKind, val offsets: List<Int>)

/**
 * Pure reminder logic (no Android): which alarms to arm, what they say, and whether a
 * firing alarm should still notify. Unit-tested with a FixedClock.
 */
object ReminderPlanner {

    /** Minutes before each of the speaker's own sessions, earliest first (30 and 10). */
    val OFFSETS_MIN: List<Int> = listOf(30, 10)

    /**
     * Every reminder still to come, keeping only those strictly after [now], sorted by
     * trigger time:
     * - each session where [me] speaks (null = None, so none): start − 30 and − 10 min;
     * - each starred ("Going") session in [going]: one at start − [goingMinutes]
     *   ([GoingStore.REMIND_OFF][app.kcna26.going.GoingStore.REMIND_OFF] = 0: none).
     *
     * A session that is both mine and starred gets only my 30/10 reminders, never a
     * third one. Starred ids the data doesn't have are ignored.
     *
     * [armed] (the keys armed by the last reschedule) only matters when the "Going" lead time
     * was just raised so close to a start that its new trigger is already past: the earlier,
     * shorter reminder of that session that is still to come stays planned (e.g. 5 → 15 min
     * at start − 8 keeps the start − 5 one), instead of the session losing its reminder.
     */
    fun plan(
        sessions: List<Session>,
        rooms: Map<String, Room>,
        me: String?,
        now: Instant,
        going: Set<String> = emptySet(),
        goingMinutes: Int = 0,
        armed: Set<String> = emptySet(),
    ): List<PlannedReminder> {
        if (me == null && (going.isEmpty() || goingMinutes <= 0)) return emptyList()
        val armedBySession: Map<String, List<Int>> =
            if (armed.isEmpty()) emptyMap() else armed.mapNotNull { parseKey(it) }.groupBy({ it.first }, { it.second })
        val out = ArrayList<PlannedReminder>()
        for (s in sessions) {
            if (!s.start.isAfter(now)) continue
            val spec = specFor(s, me, going, goingMinutes) ?: continue
            val room = rooms[s.room]
            for (m in spec.offsets) {
                val at = s.start.minus(Duration.ofMinutes(m.toLong()))
                if (at.isAfter(now)) {
                    out += PlannedReminder(s.id, at, m, s.title, text(spec.kind, m, room), spec.kind)
                } else if (spec.kind == ReminderKind.GOING) {
                    // Too late for the new lead time: keep the shorter one already armed, if still to come.
                    val kept = armedBySession[s.id].orEmpty()
                        .filter { it in 1 until m && s.start.minus(Duration.ofMinutes(it.toLong())).isAfter(now) }
                        .maxOrNull()
                    if (kept != null) {
                        val keptAt = s.start.minus(Duration.ofMinutes(kept.toLong()))
                        out += PlannedReminder(s.id, keptAt, kept, s.title, text(spec.kind, kept, room), spec.kind)
                    }
                }
            }
        }
        out.sortWith(compareBy<PlannedReminder> { it.triggerAt }.thenBy { it.sessionId })
        return out
    }

    /**
     * Whether a firing alarm of [minutesBefore] still belongs to [spec]: one of its offsets,
     * or, for "Going", a shorter one kept by [plan] after the lead time was raised late.
     */
    fun accepts(spec: ReminderSpec, minutesBefore: Int): Boolean =
        minutesBefore in spec.offsets ||
            (spec.kind == ReminderKind.GOING && minutesBefore > 0 && minutesBefore < (spec.offsets.maxOrNull() ?: 0))

    /**
     * The reminders [s] gets right now, ignoring the time: mine wins over starred (so a
     * session that is both is reminded once, at 30 and 10 min); null when it gets none.
     * The receiver re-checks a firing alarm against this.
     */
    fun specFor(s: Session, me: String?, going: Set<String>, goingMinutes: Int): ReminderSpec? = when {
        isMine(s, me) -> ReminderSpec(ReminderKind.MINE, OFFSETS_MIN)
        goingMinutes > 0 && s.id in going -> ReminderSpec(ReminderKind.GOING, listOf(goingMinutes))
        else -> null
    }

    /** [text] for my talks, [goingText] for starred sessions. */
    fun text(kind: ReminderKind, minutes: Int, room: Room?): String = when (kind) {
        ReminderKind.MINE -> text(minutes, room)
        ReminderKind.GOING -> goingText(minutes, room)
    }

    /**
     * "Your talk in 10 min · Grand Ballroom GI, Level 1". The level is left out when the
     * room has none (OFF: "Your talk in 10 min · Off-site"), the room part when the room
     * is unknown.
     */
    fun text(minutes: Int, room: Room?): String = withRoom("Your talk in $minutes min", room)

    /**
     * A starred session: "Starting in 10 min · Grand Ballroom GI, Level 1", with the same
     * room rules as [text] ("Starting in 10 min · Off-site", or no room part when unknown).
     */
    fun goingText(minutes: Int, room: Room?): String = withRoom("Starting in $minutes min", room)

    private fun withRoom(head: String, room: Room?): String {
        if (room == null) return head
        val level = room.level?.let { ", Level $it" }.orEmpty()
        return "$head · ${room.name}$level"
    }

    /**
     * What a firing alarm should do at [now]: null to skip it, otherwise the whole
     * minutes left until [start] to show (the alarm may run late, so this is the real
     * figure, not the planned [minutesBefore]).
     *
     * Skips when the session has already started (stale: the receiver ran late, e.g.
     * after boot), and skips an earlier reminder that ran so late that a later one of the
     * same session ([offsets]: 30 and 10 for my talks, the one "Going" offset for a starred
     * session) is due too, so the user isn't alerted twice for the same moment.
     */
    fun minutesLeftToShow(start: Instant, minutesBefore: Int, now: Instant, offsets: List<Int> = OFFSETS_MIN): Int? {
        if (!now.isBefore(start)) return null
        val left = TimeFormat.minutesBetween(now, start).coerceAtLeast(1L).toInt()
        val nextOffset = offsets.filter { it < minutesBefore }.maxOrNull()
        if (nextOffset != null && left <= nextOffset) return null
        return left
    }

    /** "sessionId/minutes" (session ids are digits or "m" + digits, so "/" can't clash). */
    fun key(sessionId: String, minutesBefore: Int): String = "$sessionId/$minutesBefore"

    /** Inverse of [key]; null for anything malformed. */
    fun parseKey(key: String): Pair<String, Int>? {
        val i = key.lastIndexOf('/')
        if (i <= 0 || i == key.length - 1) return null
        val minutes = key.substring(i + 1).toIntOrNull() ?: return null
        return key.substring(0, i) to minutes
    }

    /**
     * PendingIntent request code. Always different for the reminders of one session
     * (30, 15, 10 and 5 minutes). Different sessions may share a code, but their intents carry
     * different data URIs, so their PendingIntents stay distinct.
     */
    fun requestCode(sessionId: String, minutesBefore: Int): Int = sessionId.hashCode() * 31 + minutesBefore
}
