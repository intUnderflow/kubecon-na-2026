package app.kcna26.schedule

import app.kcna26.data.Day
import app.kcna26.data.Session
import app.kcna26.time.TimeFormat
import app.kcna26.time.ZONE
import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

/**
 * Pure, Android-free schedule rules over sessions and "now", ported from
 * schedule_app.js (`done`, `live`, `left`, `visibleDays`, the initial `view`,
 * the header clock). The bigger builders (day view, banner, search, day tabs)
 * live in [ScheduleIndex]. Unit-tested with FixedClock in app/src/test/.../schedule/.
 */
object ScheduleLogic {
    /**
     * Finished (web `done`): the effective end (end, or start + 90 min when the
     * agenda has none) is at or before now. Ends are whole minutes, so this
     * equals the web's minute arithmetic.
     */
    fun isFinished(s: Session, now: Instant): Boolean = !s.effectiveEnd.isAfter(now)

    /** Live (web `live`): start ≤ now < effective end. */
    fun isLive(s: Session, now: Instant): Boolean = !s.start.isAfter(now) && now.isBefore(s.effectiveEnd)

    /** Whole minutes until the effective end (web `left`), as in "Live · 12 min left". */
    fun minutesLeft(s: Session, now: Instant): Long = TimeFormat.minutesBetween(now, s.effectiveEnd)

    /** "Live · N min left", or "On now" for long rows (co-located / off-site) (web `card` pills). */
    fun liveLabel(s: Session, now: Instant, long: Boolean): String =
        if (long) "On now" else "Live · ${minutesLeft(s, now)} min left"

    /** Progress of a live session, 0..1, at minute precision like the web's `.bar` (`pct`). */
    fun liveProgress(s: Session, now: Instant): Float {
        val total = Duration.between(s.start, s.effectiveEnd).toMinutes()
        if (total <= 0) return 1f
        val elapsed = TimeFormat.minutesBetween(s.start, now)
        return ((elapsed * 100.0 / total).roundToInt().coerceIn(0, 100)) / 100f
    }

    /**
     * Days not yet over (web `visibleDays`): today and later. Before the
     * conference that is every day; after it, nothing is left, so like the web
     * every day is shown again.
     */
    fun visibleDays(days: List<Day>, now: Instant): List<Day> {
        val today = now.atZone(ZONE).toLocalDate()
        return days.filter { !it.date.isBefore(today) }.ifEmpty { days }
    }

    /** Key of the day whose date is today in Denver, or null. */
    fun todayKey(days: List<Day>, now: Instant): String? {
        val today = now.atZone(ZONE).toLocalDate()
        return days.firstOrNull { it.date == today }?.key
    }

    /** The day the schedule opens on: today, else the first visible day (web initial `view`). */
    fun defaultDayKey(days: List<Day>, now: Instant): String? =
        todayKey(days, now) ?: visibleDays(days, now).firstOrNull()?.key

    /**
     * The day to show: the user's [selected] day while it is still visible,
     * otherwise [defaultDayKey] (web `render`: `if(!vd.some(d=>d.k===view)) view=vd[0].k`,
     * which at midnight moves a stale selection on to the new today).
     */
    fun resolveDayKey(days: List<Day>, now: Instant, selected: String?): String? {
        val visible = visibleDays(days, now)
        if (selected != null && visible.any { it.key == selected }) return selected
        return defaultDayKey(days, now)
    }

    /** Half-hour block a start minute falls in: floor(minute / 30) × 30 (web `sk`). */
    fun slotKey(minuteOfDay: Int): Int = Math.floorDiv(minuteOfDay, 30) * 30

    /** Header clock: "9:05 AM MST" on a conference day, "Times in MST" otherwise (web `#clock`). */
    fun clockLabel(days: List<Day>, now: Instant): String =
        if (todayKey(days, now) != null) TimeFormat.clockLabel(now) else "Times in MST"

    /** Group card time range: earliest remaining start to the group's end, "9:00–10:35 AM". */
    fun spanLabel(start: Instant, end: Instant): String {
        val st = TimeFormat.minuteOfDay(start)
        val en = TimeFormat.minuteOfDay(end)
        return (if (TimeFormat.ap(st) != TimeFormat.ap(en)) TimeFormat.hma(st) else TimeFormat.hm(st)) + "–" + TimeFormat.hma(en)
    }

    /** "In 25 min", "In 1h", "In 2h 5m": the banner countdown for a talk later today (web `renderMine`). */
    fun countdownLabel(minutesUntil: Long): String =
        if (minutesUntil < 60) {
            "In $minutesUntil min"
        } else {
            val h = minutesUntil / 60
            val m = minutesUntil % 60
            "In ${h}h" + (if (m != 0L) " ${m}m" else "")
        }

    /** Break-row title without the web's leading ☕ / 🍲 (web `card` for category log). */
    fun breakTitle(title: String): String = BREAK_EMOJI.replace(title, "")

    /** Now truncated to the minute: the schedule only changes once a minute. */
    fun minuteOf(now: Instant): Instant = now.truncatedTo(ChronoUnit.MINUTES)

    private val BREAK_EMOJI = Regex("^(☕|🍲)\\uFE0F?\\s*")
}
