package app.kcna26.schedule

import androidx.compose.runtime.Immutable
import app.kcna26.data.ColoEvent
import app.kcna26.data.Day
import app.kcna26.data.Repository
import app.kcna26.data.Session
import app.kcna26.data.SessionGroup
import app.kcna26.data.hasAnthropic as mineHasAnthropic
import app.kcna26.data.isMine as mineIsMine
import app.kcna26.time.TimeFormat
import app.kcna26.time.ZONE
import java.time.Instant

/**
 * Everything the schedule screen shows, computed from the [Repository], "now"
 * and "me" (the "I'm speaking as" name; null = None). Pure and Android-free.
 *
 * Ports schedule_app.js `renderDay` ([dayView]), `renderMine` ([banner]),
 * `renderSearch` ([search]) and the day tabs of `render` ([dayTabs]). "Mine"
 * and "Anthropic" are always worked out here from the speakers list (never the
 * precomputed JSON flags).
 *
 * Co-located events (colocated.json): each event is one card in the day's
 * "Co-located events" section ([coloCards]) holding its talks and breaks, so
 * those never appear one by one in the half-hour blocks (a break that outlives
 * all its events' cards joins the blocks then); the schedule.json placeholders
 * they replace are never shown ([isHidden]). Everything else about a co-located
 * talk (search, details, mine/Anthropic, the banner) is ordinary.
 *
 * Build once per repository with [of] (cached), then call the builders as often
 * as needed: each is a cheap pass over one day (≤ 200 sessions) or the week.
 */
class ScheduleIndex(val repo: Repository) {
    val days: List<Day> get() = repo.days
    val anthropicSpeakers: Set<String> get() = repo.anthropicSpeakers

    // Three talks titled "Breaking…" are filed as breaks in the JSON; re-run the web rules for them.
    private val categoryFix: Map<String, String>
    private val groupFix: Map<String, SessionGroup?>

    init {
        val cats = HashMap<String, String>()
        val groups = HashMap<String, SessionGroup?>()
        for (s in repo.sessions) {
            if (!s.isColocated && ScheduleRules.isMisfiledBreak(s)) {
                val cat = ScheduleRules.catOf(s)
                cats[s.id] = cat
                groups[s.id] = ScheduleRules.seriesOf(s, cat)
            }
        }
        categoryFix = cats
        groupFix = groups
    }

    /** The session's category key (the JSON value, corrected for misfiled "Breaking…" talks). */
    fun category(s: Session): String = categoryFix[s.id] ?: s.category

    /** The session's group (the JSON value, corrected like [category]). */
    fun group(s: Session): SessionGroup? = if (s.id in groupFix) groupFix[s.id] else s.group

    /** A quiet break row (category log). */
    fun isBreak(s: Session): Boolean = category(s) == "log"

    /** Web `x.long`: off-site or All-Access co-located rows, listed in their own section. */
    fun isLong(s: Session): Boolean = group(s) == null && (s.room == "OFF" || s.note == "All-Access pass")

    /** A schedule.json all-day placeholder that a co-located event card replaces: never listed. */
    fun isHidden(s: Session): Boolean = s.id in repo.supersededIds

    /** The co-located events whose cards list [s]: a talk's event, or every event a break serves. */
    fun coloEventsOf(s: Session): List<ColoEvent> {
        if (!s.isColocated) return emptyList()
        return s.coloEvents.ifEmpty { listOfNotNull(s.coloEvent) }.mapNotNull { repo.coloEvent(it) }
    }

    /** The one co-located event [s] belongs to (its talks, its own breaks), or null. */
    fun coloEventOf(s: Session): ColoEvent? {
        if (!s.isColocated) return null
        return s.coloEvent?.let { repo.coloEvent(it) } ?: coloEventsOf(s).singleOrNull()
    }

    /** Shown inside co-located event cards rather than in the half-hour blocks. */
    fun inColoCard(s: Session): Boolean = coloEventsOf(s).isNotEmpty()

    /**
     * [s] is on a co-located card at [now]: one of its events hasn't ended yet. An unfinished talk
     * always is (its event ends with its last talk); a break may not be (CiliumCon's lunch starts
     * as CiliumCon ends), and then it's an ordinary break row in the blocks.
     */
    fun onColoCard(s: Session, now: Instant): Boolean = coloEventsOf(s).any { now.isBefore(it.end) }

    /** Days with co-located event cards in the data (Monday), whatever the time. */
    private val coloDays: Set<String> = repo.coloEvents.mapTo(HashSet()) { it.day }

    /** Room display name (web `rname`); the code itself for an unknown room. */
    fun roomName(code: String): String = repo.room(code)?.name ?: code

    /** Building line, e.g. "Salt Palace L2" (web `bldg`); "" for HL, OFF and unknown rooms. */
    fun building(code: String): String = repo.room(code)?.buildingLabel.orEmpty()

    /** Category label as the web shows it (`CATS`): "Keynote", "Talk", …; "" for breaks. */
    fun categoryLabel(key: String): String = if (key == "log") "" else repo.category(key)?.label.orEmpty()

    /** My session under the current "I'm speaking as" ([me] = null: None). */
    fun isMine(s: Session, me: String?): Boolean = mineIsMine(s, me)

    /** Not mine, and an Anthropic colleague other than [me] speaks (web `x.ant`). */
    fun hasAnthropic(s: Session, me: String?): Boolean = mineHasAnthropic(s, me, repo.anthropicSpeakers)

    private val dayPos: Map<String, Int> = repo.days.withIndex().associate { (i, d) -> d.key to i }
    private val byDay: Map<String, List<Session>> = repo.sessions.groupBy { it.day }

    /** Room sort order: rooms.json order, which equals the web's `Object.keys(R)`. */
    private val roomOrder: Map<String, Int> = repo.rooms.keys.withIndex().associate { (i, k) -> k to i }

    /**
     * Every group (web `SERIES`), in order of first appearance; kids sorted by start. Co-located
     * talks (grouped by event in the JSON) are their event's card instead, so they're not here.
     */
    val groups: Map<String, GroupInfo> = run {
        val acc = LinkedHashMap<String, MutableList<Session>>()
        val first = HashMap<String, Session>()
        val titles = HashMap<String, String>()
        for (s in repo.sessions) {
            if (inColoCard(s) || isHidden(s)) continue
            val g = group(s) ?: continue
            acc.getOrPut(g.key) { mutableListOf() }.add(s)
            if (g.key !in first) {
                first[g.key] = s
                titles[g.key] = g.title
            }
        }
        val out = LinkedHashMap<String, GroupInfo>()
        for ((key, kids) in acc) {
            val f = first.getValue(key)
            out[key] = GroupInfo(
                key = key,
                title = titles.getValue(key),
                day = f.day,
                room = f.room,
                category = category(f),
                kids = kids.sortedBy { it.start },
                end = kids.maxOf { it.effectiveEnd },
            )
        }
        out
    }

    private val groupOfSession: Map<String, String> =
        groups.values.flatMap { g -> g.kids.map { it.id to g.key } }.toMap()

    /** The key of the group a session is shown in, or null. */
    fun groupKeyOf(sessionId: String): String? = groupOfSession[sessionId]

    /** Sessions of one day in file order. */
    fun sessionsOn(dayKey: String): List<Session> = byDay[dayKey].orEmpty()

    /**
     * Each co-located event's whole agenda (talks and the breaks it lists), by start; at equal
     * starts talks before breaks, the main room first, then rooms.json order.
     */
    val coloAgendas: Map<String, List<Session>> = run {
        val acc = LinkedHashMap<String, MutableList<Session>>()
        for (e in repo.coloEvents) acc[e.key] = ArrayList()
        for (s in repo.sessions) for (e in coloEventsOf(s)) acc.getValue(e.key).add(s)
        acc.mapValues { (key, xs) ->
            val main = repo.coloEvent(key)?.mainRoom
            xs.sortedWith(
                compareBy<Session> { it.start }
                    .thenBy { if (isBreak(it)) 1 else 0 }
                    .thenBy { if (it.room == main) 0 else 1 }
                    .thenBy { roomOrder[it.room] ?: Int.MAX_VALUE },
            )
        }
    }

    // ------------------------------------------------------------------ day tabs

    /** Web `render` day tabs: visible days, "Today" label, "You" badge while I still have a talk that day. */
    fun dayTabs(now: Instant, me: String?): List<DayTab> {
        val today = ScheduleLogic.todayKey(days, now)
        return ScheduleLogic.visibleDays(days, now).map { d ->
            DayTab(
                key = d.key,
                title = d.label,
                label = if (d.key == today) "Today" else d.dow,
                number = d.num,
                hasMine = me != null && sessionsOn(d.key).any { isMine(it, me) && !ScheduleLogic.isFinished(it, now) },
            )
        }
    }

    // ------------------------------------------------------------------ day view

    /** Web `renderDay(k)`: what's left of one day, in half-hour blocks. Null for an unknown day key. */
    fun dayView(dayKey: String, now: Instant, me: String?): DayView? {
        val day = repo.day(dayKey) ?: return null
        val today = day.date == now.atZone(ZONE).toLocalDate()
        val items = sessionsOn(dayKey).filter { !ScheduleLogic.isFinished(it, now) && !isHidden(it) }
        val longs = items.filter { isLong(it) }.sortedBy { it.start }

        val blocks = ArrayList<Block>()
        // The day's own break rows. A co-located break that is the same break (start, end and
        // title) shows once, as that quiet row.
        val breakKeys = items.filter { isBreak(it) && !it.isColocated }.mapTo(HashSet()) { BreakKey.of(it) }
        for (s in items) {
            // Co-located talks and their events' breaks live in the event cards (coloCards), not in
            // the blocks; a break whose events have all ended (their cards are gone) is a block row.
            if (isLong(s) || group(s) != null || onColoCard(s, now)) continue
            if (s.isColocated && isBreak(s) && !breakKeys.add(BreakKey.of(s))) continue
            blocks += SessionBlock(s, category(s), mine = isMine(s, me), anthropic = hasAnthropic(s, me))
        }
        for (g in groups.values) {
            if (g.day != dayKey) continue
            val kids = g.kids.filter { !ScheduleLogic.isFinished(it, now) }
            if (kids.isNotEmpty()) blocks += GroupBlock(g, kids)
        }
        // Within a start time: my own talks first, then the normal order (category, then room).
        val sorted = blocks.sortedWith(
            compareBy<Block> { it.start }
                .thenByDescending { it.mine }
                .thenBy { CATEGORY_ORDER[it.category] ?: CATEGORY_ORDER.size }
                .thenBy { roomOrder[it.room] ?: -1 },
        )

        val slots = ArrayList<Slot>()
        var cur: MutableList<Block>? = null
        var curKey = Int.MIN_VALUE
        for (b in sorted) {
            val k = ScheduleLogic.slotKey(TimeFormat.minuteOfDay(b.start))
            if (cur == null || k != curKey) {
                cur = ArrayList()
                curKey = k
                slots += Slot(dayKey, k, b.start, cur)
            }
            cur.add(b)
        }

        var status: DayStatus? = null
        var upNextBefore = -1
        if (today) {
            val core = items.filter { !isLong(it) && !isBreak(it) }
            val onNow = core.count { ScheduleLogic.isLive(it, now) }
            val next = core.filter { it.start.isAfter(now) }.minByOrNull { it.start }
            status = DayStatus(onNow, next?.start)
            val nowMin = TimeFormat.minuteOfDay(now)
            val i = slots.indexOfFirst { it.key > nowMin }
            if (i > 0) upNextBefore = i
        }

        // With co-located cards (the data has events this day), Monday's CNCF co-located events are
        // those cards and what's left of the web's "Co-located + off-site" section is the
        // sponsor-hosted (separate registration) list, after the blocks. Without them (colocated.json
        // missing or unreadable) the All-Access placeholders are back, so is the web's section.
        val coloDay = dayKey in coloDays
        return DayView(
            day = day,
            isToday = today,
            status = status,
            longsTitle = when {
                coloDay -> "Sponsor-hosted · off-site"
                dayKey == "mon" -> "Co-located + off-site"
                else -> "Off-site"
            },
            longs = longs.map { SessionBlock(it, category(it), isMine(it, me), hasAnthropic(it, me)) },
            longsFirst = !coloDay && dayKey == "mon",
            slots = slots,
            upNextBefore = upNextBefore,
            colo = coloCards(dayKey, now, me),
        )
    }

    // ------------------------------------------------------------------ co-located events

    /**
     * The day's co-located event cards, alphabetical, each until its event ends. Empty on days
     * without co-located events.
     */
    fun coloCards(dayKey: String, now: Instant, me: String?): List<ColoCard> =
        repo.coloEvents
            .filter { it.day == dayKey && now.isBefore(it.end) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
            .map { coloCard(it, now, me) }

    /** One event's card at [now]. */
    fun coloCard(e: ColoEvent, now: Instant, me: String?): ColoCard {
        val left = coloAgendas[e.key].orEmpty().filter { !ScheduleLogic.isFinished(it, now) }
        val agenda = left.map { s ->
            val brk = isBreak(s)
            val mine = isMine(s, me)
            ColoItem(
                session = s,
                isBreak = brk,
                live = ScheduleLogic.isLive(s, now),
                mine = mine,
                anthropic = !mine && hasAnthropic(s, me),
                room = if (brk || s.room != e.mainRoom) s.room else null,
            )
        }
        val talks = agenda.filter { !it.isBreak }
        return ColoCard(
            event = e,
            hours = ColoText.hours(e),
            lines = ColoLines.of(e, agenda, now),
            agenda = agenda,
            mine = talks.any { it.mine },
            anthropic = talks.any { it.anthropic },
            live = talks.any { it.live },
        )
    }

    // ------------------------------------------------------------------ my talks banner

    /**
     * Web `renderMine`: my talks still to come on [dayKey], or null (no talks
     * that day, me = None, or a search is showing).
     */
    fun banner(dayKey: String?, now: Instant, me: String?, searching: Boolean = false): MineBanner? {
        if (searching || me == null || dayKey == null) return null
        val xs = sessionsOn(dayKey).filter { isMine(it, me) && !ScheduleLogic.isFinished(it, now) }.sortedBy { it.start }
        val nx = xs.firstOrNull() ?: return null
        val todayDate = now.atZone(ZONE).toLocalDate()
        val nxDay = repo.dayOf(nx)
        val nxIsToday = nxDay?.date == todayDate

        val countdown: String
        val soon: Boolean
        when {
            ScheduleLogic.isLive(nx, now) -> {
                countdown = "On now"
                soon = true
            }
            nxIsToday -> {
                val until = TimeFormat.minutesBetween(now, nx.start)
                countdown = ScheduleLogic.countdownLabel(until)
                soon = until <= 45
            }
            nxDay != null && nxDay.date == todayDate.plusDays(1) -> {
                countdown = "Tomorrow"
                soon = false
            }
            else -> {
                countdown = nxDay?.label?.substringBefore(',') ?: ""
                soon = false
            }
        }

        fun dayPrefix(s: Session): String {
            val d = repo.dayOf(s) ?: return ""
            return if (d.date == todayDate) "" else d.dow + " "
        }

        val where = buildString {
            if (soon) append("Head to ")
            append(roomName(nx.room))
            val b = building(nx.room)
            if (b.isNotEmpty()) append(" · ").append(b)
            if (category(nx) == "key") append(" · Keynote")
        }
        val later = xs.drop(1).mapIndexed { i, x ->
            LaterTalk(
                session = x,
                time = (if (x.day != xs[i].day) dayPrefix(x) else "") + TimeFormat.hma(x.start),
                roomName = roomName(x.room),
            )
        }
        return MineBanner(
            next = nx,
            countdown = countdown,
            soon = soon,
            live = ScheduleLogic.isLive(nx, now),
            nextTime = dayPrefix(nx) + TimeFormat.hma(nx.start),
            nextWhere = where,
            later = later,
        )
    }

    // ------------------------------------------------------------------ search

    /** Normalised search text per session id, without the "anthropic" flag (web `x.hay`). */
    private val haystack: Map<String, String> by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        repo.sessions.associate { s ->
            s.id to TextMatch.normalize(
                listOf(
                    s.title,
                    s.speakers.joinToString(", "),
                    roomName(s.room),
                    s.note.orEmpty(),
                    categoryLabel(category(s)),
                    // Co-located talks: "argocon" finds all of ArgoCon's; also topic, format and level.
                    coloEventOf(s)?.name.orEmpty(),
                    s.topic.orEmpty(),
                    s.format.orEmpty(),
                    s.level.orEmpty(),
                ).joinToString(" "),
            )
        }
    }

    /** Builds the search text now (call off the main thread) so the first keystroke is cheap. */
    fun prewarmSearch() {
        haystack.size
    }

    /** True when [s] matches every search term (title, speakers, room name, note, category label, co-located event). */
    fun matches(s: Session, terms: List<String>, me: String?): Boolean {
        if (terms.isEmpty()) return false
        val base = haystack[s.id] ?: return false
        if (TextMatch.matchesAll(base, terms)) return true
        // Web: x.hay gets " anthropic" for the speaker's own sessions and sessions with Anthropic colleagues.
        if (!(isMine(s, me) || hasAnthropic(s, me))) return false
        return TextMatch.matchesAll("$base anthropic", terms)
    }

    /** Web `renderSearch`: unfinished, non-break sessions of the whole week matching every term, by day. */
    fun search(query: String, now: Instant, me: String?): SearchResults {
        val terms = TextMatch.terms(query)
        if (terms.isEmpty()) return SearchResults(0, emptyList())
        val hits = repo.sessions.filter {
            !isBreak(it) && !isHidden(it) && !ScheduleLogic.isFinished(it, now) && matches(it, terms, me)
        }
        val byDayHits = hits.groupBy { it.day }
        val sections = days.mapNotNull { d ->
            val xs = byDayHits[d.key]?.sortedBy { it.start } ?: return@mapNotNull null
            SearchDay(d, xs.map { SessionBlock(it, category(it), isMine(it, me), hasAnthropic(it, me)) })
        }
        return SearchResults(hits.size, sections)
    }

    // ------------------------------------------------------------------ cards

    /** Live state for one card (web `card`: pills, live border, progress bar). */
    fun cardStatus(s: Session, now: Instant): CardStatus {
        if (!ScheduleLogic.isLive(s, now)) return CardStatus.NotLive
        val long = isLong(s)
        return CardStatus(
            live = true,
            liveLabel = ScheduleLogic.liveLabel(s, now, long),
            progress = if (long) null else ScheduleLogic.liveProgress(s, now),
        )
    }

    companion object {
        /** Web `ORD`: block sort order by category. */
        val CATEGORY_ORDER: Map<String, Int> =
            mapOf("key" to 0, "talk" to 1, "mnt" to 2, "hands" to 3, "com" to 4, "show" to 5, "soc" to 6, "colo" to 7, "log" to 8)

        @Volatile
        private var cached: ScheduleIndex? = null

        /**
         * The index for [repo], built once per Repository (it survives fold/unfold recreation).
         * Only the latest is kept, so a live data update doesn't keep the old data set alive.
         */
        fun of(repo: Repository): ScheduleIndex {
            cached?.let { if (it.repo === repo) return it }
            synchronized(this) {
                cached?.let { if (it.repo === repo) return it }
                return ScheduleIndex(repo).also { cached = it }
            }
        }
    }
}

/** A group of back-to-back sessions in one room (web `SERIES` entry). */
@Immutable
data class GroupInfo(
    val key: String,
    val title: String,
    val day: String,
    val room: String,
    val category: String,
    /** All kids, sorted by start. */
    val kids: List<Session>,
    /** Latest effective end of any kid. */
    val end: Instant,
)

/** One entry in a half-hour block: a session card / break row, or a group card. */
@Immutable
sealed interface Block {
    val start: Instant
    val category: String
    val room: String
    val mine: Boolean
    val anthropic: Boolean
    /** Stable LazyColumn key. */
    val key: String
}

@Immutable
data class SessionBlock(
    val session: Session,
    override val category: String,
    override val mine: Boolean,
    override val anthropic: Boolean,
) : Block {
    override val start: Instant get() = session.start
    override val room: String get() = session.room
    override val key: String get() = "s-" + session.id
}

@Immutable
data class GroupBlock(
    val group: GroupInfo,
    /** Kids not finished yet, sorted by start. */
    val kids: List<Session>,
) : Block {
    override val start: Instant get() = kids.first().start
    override val category: String get() = group.category
    override val room: String get() = group.room
    override val mine: Boolean get() = false
    override val anthropic: Boolean get() = false
    override val key: String get() = "g-" + group.key
}

/** A half-hour block labelled with its earliest real start ("10:15 AM", not "10:00"). */
@Immutable
data class Slot(val dayKey: String, val key: Int, val start: Instant, val blocks: List<Block>) {
    val label: String get() = TimeFormat.hma(start)
}

/** Today's status line: "3 on now · Next at 10:15 AM". */
@Immutable
data class DayStatus(val onNow: Int, val nextStart: Instant?)

@Immutable
data class DayView(
    val day: Day,
    val isToday: Boolean,
    /** Only for today. */
    val status: DayStatus?,
    /**
     * "Sponsor-hosted · off-site" (Monday, with its co-located cards), "Co-located + off-site"
     * (Monday without co-located data, as on the web) or "Off-site".
     */
    val longsTitle: String,
    val longs: List<SessionBlock>,
    /** List [longs] before the blocks: only Monday without co-located cards (the web's order). */
    val longsFirst: Boolean,
    val slots: List<Slot>,
    /** Index into [slots] of the block the "Up next" line goes before, or -1. */
    val upNextBefore: Int,
    /** The "Co-located events" cards (Monday), shown above the blocks; empty on other days. */
    val colo: List<ColoCard> = emptyList(),
) {
    /** "That’s a wrap for today". */
    val isEmpty: Boolean get() = slots.isEmpty() && longs.isEmpty() && colo.isEmpty()
}

/** Identity of a break for de-duplication: the same start, end and title (emoji and case aside). */
internal data class BreakKey(val start: Instant, val end: Instant?, val title: String) {
    companion object {
        fun of(s: Session) = BreakKey(s.start, s.end, TextMatch.normalize(ScheduleLogic.breakTitle(s.title)).trim())
    }
}

@Immutable
data class DayTab(
    val key: String,
    /** "Wednesday, Nov 11" (for accessibility). */
    val title: String,
    /** "Today" or "Wed". */
    val label: String,
    val number: Int,
    /** I still have a talk to come that day: the pink "YOU" badge. */
    val hasMine: Boolean,
)

@Immutable
data class LaterTalk(val session: Session, val time: String, val roomName: String)

/** The pinned "You’re speaking" banner. */
@Immutable
data class MineBanner(
    val next: Session,
    /** "On now", "In 25 min", "In 1h 45m", "Tomorrow", "Wednesday". */
    val countdown: String,
    /** Live or within 45 min: pulse the countdown and say "Head to …". */
    val soon: Boolean,
    val live: Boolean,
    /** "9:45 AM", or "Wed 9:45 AM" when not today. */
    val nextTime: String,
    /** "Head to Hall DE · Salt Palace L1 · Keynote". */
    val nextWhere: String,
    val later: List<LaterTalk>,
)

@Immutable
data class SearchDay(val day: Day, val sessions: List<SessionBlock>)

@Immutable
data class SearchResults(val count: Int, val days: List<SearchDay>) {
    /** "1 match", "12 matches". */
    val heading: String get() = "$count ${if (count == 1) "match" else "matches"}"
}

@Immutable
data class CardStatus(val live: Boolean, val liveLabel: String?, val progress: Float?) {
    companion object {
        val NotLive = CardStatus(false, null, null)
    }
}
