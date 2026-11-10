package app.kcna26.time

import app.kcna26.data.Session
import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Time formatting ported from the web version (schedule_app.js `hm`, `ap`,
 * `hma`, `dur`, `range`). All in America/Denver, 12-hour clock, no leading zero.
 * Minute-of-day values are 0..1439 (larger values wrap, like the web).
 */
object TimeFormat {
    /** Minutes since local midnight in Denver. */
    fun minuteOfDay(t: Instant): Int {
        val z = t.atZone(ZONE)
        return z.hour * 60 + z.minute
    }

    /** "9:05" (web `hm`). */
    fun hm(minuteOfDay: Int): String {
        val m = ((minuteOfDay % 1440) + 1440) % 1440
        val h = (m / 60) % 12
        return "${if (h == 0) 12 else h}:${(m % 60).toString().padStart(2, '0')}"
    }

    /** "AM" / "PM" (web `ap`). */
    fun ap(minuteOfDay: Int): String = if (((minuteOfDay % 1440) + 1440) % 1440 < 720) "AM" else "PM"

    /** "9:05 AM" (web `hma`). */
    fun hma(minuteOfDay: Int): String = hm(minuteOfDay) + " " + ap(minuteOfDay)

    fun hm(t: Instant): String = hm(minuteOfDay(t))
    fun ap(t: Instant): String = ap(minuteOfDay(t))
    fun hma(t: Instant): String = hma(minuteOfDay(t))

    /**
     * "9:00–9:30 AM", "11:30 AM–12:15 PM", or "from 5:30 PM" when the session has
     * no end (web `range`). Uses an en dash.
     */
    fun range(s: Session): String {
        val st = minuteOfDay(s.start)
        val end = s.end ?: return "from " + hma(st)
        val en = minuteOfDay(end)
        return (if (ap(st) != ap(en)) hma(st) else hm(st)) + "–" + hma(en)
    }

    /**
     * Duration label (web `dur`): "45 min", "1h", "1h 30m", prefixed with "~" when
     * [Session.endIsEstimate]. Null when the session has no end (the web shows none).
     */
    fun dur(s: Session): String? {
        val end = s.end ?: return null
        return (if (s.endIsEstimate) "~" else "") + durationLabel(Duration.between(s.start, end).toMinutes())
    }

    /** "45 min", "1h", "1h 30m". */
    fun durationLabel(minutes: Long): String = when {
        minutes >= 60 && minutes % 60 != 0L -> "${minutes / 60}h ${minutes % 60}m"
        minutes >= 60 -> "${minutes / 60}h"
        else -> "$minutes min"
    }

    /** Header clock: "9:05 AM MST". */
    fun clockLabel(now: Instant): String = hma(now) + " MST"

    /**
     * Whole minutes from [now] to [t], counting like the web (both truncated to the
     * minute), e.g. "Live · N min left" = minutesBetween(now, effectiveEnd).
     */
    fun minutesBetween(now: Instant, t: Instant): Long =
        ChronoUnit.MINUTES.between(now.truncatedTo(ChronoUnit.MINUTES), t.truncatedTo(ChronoUnit.MINUTES))
}
