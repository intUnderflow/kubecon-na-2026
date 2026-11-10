package app.kcna26.going

import androidx.compose.runtime.Immutable
import app.kcna26.data.Session
import app.kcna26.data.isMine
import app.kcna26.data.mySessions
import app.kcna26.schedule.Block
import app.kcna26.schedule.ColoCard
import app.kcna26.schedule.ColoLines
import app.kcna26.schedule.DayStatus
import app.kcna26.schedule.DayView
import app.kcna26.schedule.GroupBlock
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.schedule.ScheduleLogic
import app.kcna26.schedule.SearchDay
import app.kcna26.schedule.SearchResults
import app.kcna26.schedule.SessionBlock
import app.kcna26.schedule.Slot
import app.kcna26.time.TimeFormat
import java.time.Instant

/**
 * Pure "Going" rules (no Android, no Compose runtime): the filter, clash detection and the
 * "Up next" pick. Unit-tested in app/src/test/.../going/.
 */
object GoingLogic {

    /** How soon a starred session must start to take "Up next" over one that is on now. */
    const val SOON_MINUTES = 15L

    /** The Going filter keeps starred sessions and my own talks. */
    fun keeps(s: Session, going: Set<String>, me: String?): Boolean = s.id in going || isMine(s, me)

    // ------------------------------------------------------------------ filter

    /**
     * [view] with only the sessions [keep] accepts: session cards and long rows are kept or
     * dropped, group cards keep just their accepted kids (and go when none is left), and
     * the half-hour blocks are rebuilt, so a group whose first kept kid starts later moves
     * to that block. Co-located event cards (Monday) keep just their accepted talks (no breaks)
     * and go when none is left. The "Up next" line and today's status line ("1 on now · Next at
     * 11:45 AM") are worked out as in [ScheduleIndex.dayView], from the kept sessions only.
     */
    fun filterDay(view: DayView, now: Instant, keep: (Session) -> Boolean): DayView {
        // Stable sort by the new start keeps the index's tie order (mine, then category, then room).
        val blocks = view.slots.flatMap { it.blocks }.mapNotNull { filterBlock(it, keep) }.sortedBy { it.start }
        val slots = ArrayList<Slot>()
        var cur: MutableList<Block>? = null
        var curKey = Int.MIN_VALUE
        for (b in blocks) {
            val k = ScheduleLogic.slotKey(TimeFormat.minuteOfDay(b.start))
            if (cur == null || k != curKey) {
                cur = ArrayList()
                curKey = k
                slots += Slot(view.day.key, k, b.start, cur)
            }
            cur.add(b)
        }
        var upNextBefore = -1
        if (view.isToday) {
            val nowMin = TimeFormat.minuteOfDay(now)
            val i = slots.indexOfFirst { it.key > nowMin }
            if (i > 0) upNextBefore = i
        }
        val colo = view.colo.mapNotNull { filterColo(it, now, keep) }
        val status = view.status?.let {
            // Like the index: no breaks, no long rows (those are in view.longs, not in the blocks).
            val core = blocks.flatMap { b ->
                when (b) {
                    is SessionBlock -> if (b.category == "log") emptyList() else listOf(b.session)
                    is GroupBlock -> b.kids
                }
            } + colo.flatMap { card -> card.agenda.map { it.session } }
            DayStatus(core.count { ScheduleLogic.isLive(it, now) }, core.filter { it.start.isAfter(now) }.minOfOrNull { it.start })
        }
        return view.copy(
            slots = slots,
            longs = view.longs.filter { keep(it.session) },
            upNextBefore = upNextBefore,
            status = status,
            colo = colo,
        )
    }

    /**
     * A co-located event card with only the talks [keep] accepts, or null when none is left.
     * Its live lines come from those talks (the event's breaks still name a "Lunch · Next …").
     */
    fun filterColo(card: ColoCard, now: Instant, keep: (Session) -> Boolean): ColoCard? {
        val talks = card.agenda.filter { !it.isBreak && keep(it.session) }
        if (talks.isEmpty()) return null
        val breaks = card.agenda.filter { it.isBreak }
        return card.copy(
            lines = ColoLines.of(card.event, (talks + breaks).sortedBy { it.session.start }, now),
            agenda = talks,
            mine = talks.any { it.mine },
            anthropic = talks.any { it.anthropic },
            live = talks.any { it.live },
        )
    }

    private fun filterBlock(b: Block, keep: (Session) -> Boolean): Block? = when (b) {
        is SessionBlock -> b.takeIf { keep(it.session) }
        is GroupBlock -> b.kids.filter(keep).takeIf { it.isNotEmpty() }?.let { b.copy(kids = it) }
    }

    /** [results] with only the sessions [keep] accepts; days left empty are dropped. */
    fun filterSearch(results: SearchResults, keep: (Session) -> Boolean): SearchResults {
        val days = results.days.mapNotNull { d ->
            d.sessions.filter { keep(it.session) }.takeIf { it.isNotEmpty() }?.let { SearchDay(d.day, it) }
        }
        return SearchResults(days.sumOf { it.sessions.size }, days)
    }

    /**
     * The Going filter's note (title, text), or null for none. When the filter leaves nothing
     * from a day or search that has something, the note replaces the usual empty state; when
     * nothing is starred at all but my own talks are left, it follows them (how to star).
     * A day whose starred sessions are all over says so, and every note about a day names
     * the other days that still have stars ("You have 3 on Wednesday.").
     */
    fun emptyText(
        goingOnly: Boolean,
        fullView: DayView?,
        view: DayView?,
        allResults: SearchResults?,
        results: SearchResults?,
        index: ScheduleIndex,
        going: Set<String>,
        now: Instant,
        remindMinutes: Int,
    ): Pair<String, String>? {
        if (!goingOnly) return null
        val anyStarred = going.any { index.repo.sessionsById.containsKey(it) }
        val none = GoingText.NONE_TITLE to GoingText.noneText(remindMinutes)
        if (allResults != null) {
            if (results == null || allResults.count == 0) return null
            if (results.count > 0) return if (anyStarred) null else none
            return if (anyStarred) GoingText.SEARCH_TITLE to GoingText.SEARCH_TEXT else none
        }
        if (fullView == null || view == null || fullView.isEmpty) return null
        if (!view.isEmpty) return if (anyStarred) null else none
        if (!anyStarred) return none
        val day = fullView.day
        val others = starredLeftByDay(index, going, now).filter { it.first != day.key }
            .map { (key, n) -> n to (index.repo.day(key)?.label?.substringBefore(',') ?: key) }
        val doneToday = fullView.isToday &&
            index.sessionsOn(day.key).any { it.id in going && ScheduleLogic.isFinished(it, now) }
        return if (doneToday) {
            GoingText.DONE_TITLE to GoingText.doneText(others)
        } else {
            GoingText.dayTitle(day.label) to GoingText.dayText(others)
        }
    }

    /** (day key, starred sessions not finished at [now]) for each day that has some, in day order. */
    fun starredLeftByDay(index: ScheduleIndex, going: Set<String>, now: Instant): List<Pair<String, Int>> {
        if (going.isEmpty()) return emptyList()
        return index.days.mapNotNull { d ->
            val n = index.sessionsOn(d.key).count { it.id in going && !ScheduleLogic.isFinished(it, now) }
            if (n > 0) d.key to n else null
        }
    }

    // ------------------------------------------------------------------ clashes

    /** True when the two sessions overlap in time (back-to-back is not a clash). */
    fun overlaps(a: Session, b: Session): Boolean = a.start.isBefore(b.effectiveEnd) && b.start.isBefore(a.effectiveEnd)

    /**
     * Whether [s] takes part in clash detection: not a long row (co-located, off-site, all-day:
     * something people drop in and out of, which would otherwise clash with everything) and
     * not a break.
     */
    private fun clashable(index: ScheduleIndex, s: Session): Boolean = !index.isLong(s) && !index.isBreak(s)

    /**
     * For each starred session still in the data, the other starred sessions and my own
     * talks it overlaps, by start time. Sessions finished at [now] don't count (a clash
     * with something that is over doesn't matter any more); null [now] keeps everything.
     * Not clashes: two sessions in the same room (e.g. posters of one poster session, or
     * keynotes whose times overlap by a minute: you're there for both), and long rows
     * ([clashable]). Starred sessions without a clash are not in the map.
     */
    fun clashes(index: ScheduleIndex, going: Set<String>, me: String?, now: Instant? = null): Map<String, List<Clash>> {
        if (going.isEmpty()) return emptyMap()
        val repo = index.repo
        val counts = { s: Session -> (now == null || !ScheduleLogic.isFinished(s, now)) && clashable(index, s) }
        val starred = going.mapNotNull { repo.sessionsById[it] }.filter(counts)
        if (starred.isEmpty()) return emptyMap()
        val all = LinkedHashMap<String, Session>()
        for (s in starred) all[s.id] = s
        for (s in repo.mySessions(me)) if (counts(s)) all[s.id] = s
        val candidates = all.values.sortedWith(compareBy<Session> { it.start }.thenBy { it.id })
        val out = HashMap<String, List<Clash>>()
        for (s in starred) {
            val with = candidates.filter { it.id != s.id && it.room != s.room && overlaps(s, it) }
            if (with.isNotEmpty()) out[s.id] = with.map { Clash(it, mine = isMine(it, me)) }
        }
        return out
    }

    /** [clashes] for one session (empty when it isn't starred or clashes with nothing). */
    fun clashesFor(index: ScheduleIndex, s: Session, going: Set<String>, me: String?, now: Instant? = null): List<Clash> =
        if (s.id !in going) emptyList() else clashes(index, going, me, now)[s.id].orEmpty()

    // ------------------------------------------------------------------ up next

    /**
     * The "Up next" row for [dayKey]'s list: my next (or live) starred session today, or null
     * when [dayKey] isn't today or nothing starred is left today. My own talks are left out
     * (the "You’re speaking" banner has them), and so are breaks.
     *
     * Pick: the next starred session to start, unless one is on now and the next doesn't
     * start within [SOON_MINUTES]; then the live one (the latest to have started). A long row
     * (co-located, off-site) that is on now only counts as live when nothing else starred is
     * left today, so an all-day event doesn't hide the talks in between.
     */
    fun upNext(index: ScheduleIndex, dayKey: String?, going: Set<String>, me: String?, now: Instant): GoingNext? {
        if (going.isEmpty() || dayKey == null) return null
        val today = ScheduleLogic.todayKey(index.days, now) ?: return null
        if (dayKey != today) return null
        val left = index.sessionsOn(today).filter {
            it.id in going && !isMine(it, me) && !index.isBreak(it) && !ScheduleLogic.isFinished(it, now)
        }
        if (left.isEmpty()) return null
        val byStart = compareBy<Session> { it.start }.thenBy { it.id }
        val next = left.filter { it.start.isAfter(now) }.minWithOrNull(byStart)
        val onNow = left.filter { ScheduleLogic.isLive(it, now) }
        val live = onNow.filter { !index.isLong(it) }.maxWithOrNull(byStart)
            ?: onNow.takeIf { left.all { s -> index.isLong(s) } }?.maxWithOrNull(byStart)
        val pick = when {
            live == null -> next
            next == null -> live
            TimeFormat.minutesBetween(now, next.start) <= SOON_MINUTES -> next
            else -> live
        } ?: return null
        val isLive = ScheduleLogic.isLive(pick, now)
        val room = index.repo.room(pick.room)
        return GoingNext(
            session = pick,
            live = isLive,
            label = if (isLive) GoingText.ON_NOW else GoingText.YOUR_NEXT,
            countdown = when {
                !isLive -> countdown(TimeFormat.minutesBetween(now, pick.start))
                index.isLong(pick) -> "until " + TimeFormat.hma(pick.effectiveEnd)
                else -> "${ScheduleLogic.minutesLeft(pick, now)} min left"
            },
            time = TimeFormat.range(pick),
            roomName = index.roomName(pick.room),
            level = room?.level?.let { "Level $it" },
            canRoute = room?.hasPosition == true,
        )
    }

    /** "in 12 min", "in 1h", "in 1h 5m" (the banner's countdown, lower-case to follow a label). */
    fun countdown(minutesUntil: Long): String =
        ScheduleLogic.countdownLabel(minutesUntil.coerceAtLeast(1L)).replaceFirstChar { it.lowercaseChar() }
}

/** A session a starred one overlaps: another starred session, or one of my talks ([mine]). */
@Immutable
data class Clash(val session: Session, val mine: Boolean)

/** The "Up next" row: my next (or live) starred session today. */
@Immutable
data class GoingNext(
    val session: Session,
    val live: Boolean,
    /** "Your next", or "On now" when [live] (never "Up next": the timeline line has that name). */
    val label: String,
    /** "in 12 min", "in 1h 5m"; when [live] "8 min left" ("until 5:00 PM" for co-located / off-site rows). */
    val countdown: String,
    /** "10:30–11:00 AM". */
    val time: String,
    /** "251 A–C". */
    val roomName: String,
    /** "Level 2", or null when the room has none (off-site). */
    val level: String?,
    /** The room is on the map, so Directions can route to it. */
    val canRoute: Boolean,
)

/** Wording for the Going filter's empty states and hints. */
object GoingText {
    const val CHIP = "RSVP’d"
    const val CHIP_DESCRIPTION = "RSVP’d: only sessions you’ve RSVP’d to, and your talks"
    const val MARK = "RSVP"
    const val GOING = "RSVP’d"
    const val YOUR_NEXT = "Your next"
    const val ON_NOW = "On now"
    const val CLASH = "Clash"
    const val CLASHES_WITH = "Clashes with"
    const val YOUR_TALK = "Your talk"
    const val SETTING_TITLE = "Remind me before sessions I’ve RSVP’d to"
    const val NOTIFICATIONS_OFF = "Notifications are off for this app, so reminders can’t reach you."
    const val GOING_CHANNEL_OFF = "Reminders for sessions you’ve RSVP’d to are turned off."
    const val TALKS_CHANNEL_OFF = "Reminders for your talks are turned off."
    const val TURN_ON = "Turn on"

    /** RSVPs are a personal mark: say so, so nobody thinks they registered with the organisers. */
    const val PRIVATE_NOTE = "RSVPs stay on this phone; they don’t register you with the organisers."

    /** A card or row star: "Going: <title>" / "Mark as going: <title>" (just the state without a [title]). */
    fun starDescription(going: Boolean, title: String?): String =
        (if (going) GOING else MARK) + (title?.let { ": $it" } ?: "")

    const val NONE_TITLE = "No RSVPs yet"
    const val SEARCH_TITLE = "No RSVP’d matches"
    const val SEARCH_TEXT = "Turn off RSVP’d to search every session."

    /** Nothing starred at all: how to star. */
    fun noneText(remindMinutes: Int): String =
        "Turn off RSVP’d above, then tap the star on any session to RSVP. It shows up here" +
            (if (remindMinutes > 0) ", with a reminder $remindMinutes min before it starts." else ".") +
            " $PRIVATE_NOTE"

    /** Stars exist, but none on this day: "Nothing starred for Wednesday". */
    fun dayTitle(dayLabel: String): String = "No RSVPs for ${dayLabel.substringBefore(',')}"

    const val DAY_TEXT = "Turn off RSVP’d above to see the whole day, then tap the star on the sessions you want."

    /** Today's starred sessions are all over. */
    const val DONE_TITLE = "No RSVPs left today"

    /** "You have 3 on Wednesday and 1 on Thursday." from (count, day name) pairs; "" for none. */
    fun othersText(others: List<Pair<Int, String>>): String {
        if (others.isEmpty()) return ""
        val parts = others.map { (n, day) -> "$n on $day" }
        val list = if (parts.size == 1) parts[0] else parts.dropLast(1).joinToString(", ") + " and " + parts.last()
        return "You have $list."
    }

    /** No stars on this day: the other days that have some, then how to star here. */
    fun dayText(others: List<Pair<Int, String>>): String =
        othersText(others).let { if (it.isEmpty()) DAY_TEXT else "$it $DAY_TEXT" }

    /** Today's starred sessions are over: say so, and where the others are. */
    fun doneText(others: List<Pair<Int, String>>): String =
        listOf("Your RSVP’d sessions for today are over.", othersText(others), "Turn off RSVP’d above to see what’s still on.")
            .filter { it.isNotEmpty() }
            .joinToString(" ")

    /** Settings choice label: "Off", "5 min". */
    fun optionLabel(minutes: Int): String = if (minutes <= 0) "Off" else "$minutes min"

    /** Settings summary under the choice ([me]: "I’m speaking as", null = None). */
    fun settingSummary(minutes: Int, me: String? = null): String =
        if (minutes <= 0) {
            "No reminders for sessions you’ve RSVP’d to." + (if (me != null) " Your own talks still get theirs." else "")
        } else {
            "One notification $minutes min before each session you’ve RSVP’d to, with the room and level. Tap it for directions. $PRIVATE_NOTE"
        }
}
