package app.kcna26.schedule

import androidx.compose.runtime.Immutable
import app.kcna26.data.ColoEvent
import app.kcna26.data.Session
import app.kcna26.time.TimeFormat
import java.time.Instant

/*
 * The "Co-located events" section of a day (Monday): one card per CNCF-hosted co-located event,
 * built by ScheduleIndex.coloCards. Pure and Android-free (unit-tested in ColocatedTest).
 *
 * A card disappears when its event ends (ColoEvent.end, the last talk's end), like finished
 * sessions do. Its agenda is what's left of the event: unfinished talks and the event's own
 * breaks (a break shared by several events is in each of their agendas), in time order. A break
 * that outlives every event it serves (CiliumCon's and FluxCon's lunches start as they end) then
 * joins the day's time blocks as an ordinary quiet break row (ScheduleIndex.dayView).
 */

/** One event's card. */
@Immutable
data class ColoCard(
    val event: ColoEvent,
    /** "9:00 AM–5:45 PM", or "Half day · 1:20–5:30 PM". */
    val hours: String,
    /** The glanceable line(s) under the hours, at most two: "Starts …"; or "Now …" and/or "Next …". */
    val lines: List<ColoLine>,
    /** Unfinished talks and breaks, in time order (main room first at equal starts). */
    val agenda: List<ColoItem>,
    /** One of the remaining talks is mine: the pink "You" marker. */
    val mine: Boolean,
    /** One of the remaining talks has an Anthropic colleague (and isn't mine). */
    val anthropic: Boolean,
    /** A talk is on now. */
    val live: Boolean,
) {
    val key: String get() = event.key

    /** True when [sessionId] is still on this card's agenda. */
    fun holds(sessionId: String): Boolean = agenda.any { it.session.id == sessionId }
}

/** One agenda row: a talk, or a quiet break. */
@Immutable
data class ColoItem(
    val session: Session,
    val isBreak: Boolean,
    val live: Boolean,
    val mine: Boolean,
    val anthropic: Boolean,
    /** Room code to show: a talk outside the event's main room, or a break (they're in the foyers / lunch hall). */
    val room: String?,
)

/** A card's live line. [session] is the talk it names. */
@Immutable
sealed interface ColoLine {
    val session: Session?

    /**
     * Before the event: "Starts 9:00 AM · <first talk>" (opening remarks skipped), with the talk's
     * own time when it isn't at [at]: "Starts 9:00 AM · First talk 9:10 · <title>".
     */
    data class Starts(val at: Instant, override val session: Session?) : ColoLine

    /** A talk is on (one line: the main room's, else the one ending first): "Now · 12 min left · <title>"; [room] when it isn't in the main room. */
    data class Now(override val session: Session, val minutesLeft: Long, val room: String?) : ColoLine

    /** The next talk: "Next 10:40 · <title>"; [during] names the event's break that's on ("Lunch · Next …"). */
    data class Next(override val session: Session, val room: String?, val during: String?) : ColoLine
}

/** A card's live lines, from what's left of its agenda (ScheduleIndex.coloCard, GoingLogic's filter). */
object ColoLines {
    /**
     * The card's live line(s), at most two so a collapsed card stays compact: before the event
     * "Starts 9:00 AM · First talk 9:10 · <title>"; during it one "Now" line (the main room's talk,
     * else the one ending first: a second room's talk is in the agenda), then the next talk;
     * between talks just the next one, prefixed by the event's break if one is on.
     */
    fun of(e: ColoEvent, agenda: List<ColoItem>, now: Instant): List<ColoLine> {
        val talks = agenda.filter { !it.isBreak }.map { it.session }
        if (now.isBefore(e.start)) {
            val first = talks.firstOrNull { !ColoText.isRemarks(it) } ?: talks.firstOrNull()
            return listOf(ColoLine.Starts(e.start, first))
        }
        val out = ArrayList<ColoLine>(2)
        val live = talks.filter { ScheduleLogic.isLive(it, now) }
        val shown = live.minWithOrNull(
            compareBy<Session> { if (it.room == e.mainRoom) 0 else 1 }.thenBy { it.effectiveEnd }.thenBy { it.start },
        )
        if (shown != null) {
            out += ColoLine.Now(shown, ScheduleLogic.minutesLeft(shown, now), shown.room.takeIf { it != e.mainRoom })
        }
        val next = talks.filter { it.start.isAfter(now) }
            .minWithOrNull(compareBy<Session> { it.start }.thenBy { if (it.room == e.mainRoom) 0 else 1 })
        if (next != null) {
            val during = if (live.isEmpty()) {
                agenda.firstOrNull { it.isBreak && it.live }?.let { ScheduleLogic.breakTitle(it.session.title) }
            } else {
                null
            }
            out += ColoLine.Next(next, next.room.takeIf { it != e.mainRoom }, during)
        }
        return out
    }
}

/** The card's strings. */
object ColoText {
    /** Section heading over the cards. */
    const val SECTION = "Co-located events"

    /** "9:00 AM–5:45 PM", or "Half day · 1:20–5:30 PM" (the group cards' span style). */
    fun hours(e: ColoEvent): String = hoursParts(e).joinToString(" · ")

    /** [hours] in the pieces a narrow card may wrap between: ["Half day", "1:20–5:30 PM"]. */
    fun hoursParts(e: ColoEvent): List<String> {
        val span = ScheduleLogic.spanLabel(e.start, e.end)
        return if (e.halfDay) listOf("Half day", span) else listOf(span)
    }

    /**
     * The line's label, before the title: "Starts 9:00 AM · First talk 9:10", "Now · 12 min left",
     * "Now · 12 min left · 251 A–C", "Next 10:40", "Lunch · Next 12:45".
     */
    fun label(line: ColoLine, roomName: (String) -> String): String = when (line) {
        is ColoLine.Starts -> "Starts ${TimeFormat.hma(line.at)}" +
            (line.session?.takeIf { it.start.isAfter(line.at) }?.let { " · First talk ${TimeFormat.hm(it.start)}" } ?: "")
        is ColoLine.Now -> "Now · ${line.minutesLeft} min left" + (line.room?.let { " · " + roomName(it) } ?: "")
        is ColoLine.Next -> (line.during?.let { "$it · " } ?: "") + "Next ${TimeFormat.hm(line.session.start)}" +
            (line.room?.let { " · " + roomName(it) } ?: "")
    }

    /** The whole line as plain text (accessibility, tests): label · title. */
    fun text(line: ColoLine, roomName: (String) -> String): String =
        label(line, roomName) + (line.session?.title?.let { " · $it" } ?: "")

    /**
     * An agenda break row's text after its start time (which the row's time column shows):
     * ["Coffee Break", "until 10:40", "Meeting room foyers"], joined with " · ", the first part bold.
     */
    fun breakParts(s: Session, room: String?, roomName: (String) -> String): List<String> = listOfNotNull(
        ScheduleLogic.breakTitle(s.title),
        s.end?.let { "until " + TimeFormat.hm(it) },
        room?.let(roomName),
    )

    /** "Welcome + Opening Remarks" / "Closing Remarks": not what "Starts … · <first talk>" should name. */
    fun isRemarks(s: Session): Boolean = REMARKS.containsMatchIn(s.title)

    private val REMARKS = Regex("^(Welcome\\b|Opening Remarks|Closing Remarks)", RegexOption.IGNORE_CASE)
}
