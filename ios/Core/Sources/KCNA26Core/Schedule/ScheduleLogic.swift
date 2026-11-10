import Foundation

/// Pure schedule rules over sessions and "now", ported from schedule_app.js (`done`, `live`,
/// `left`, `visibleDays`, the initial `view`, the header clock). The bigger builders (day view,
/// banner, search, day tabs) live in ``ScheduleIndex``. Unit-tested with fixed instants in
/// Tests/KCNA26CoreTests/Schedule/.
///
/// Kotlin -> Swift: `Instant` -> `Date`; the `Long` minute counts are `Int`.
enum ScheduleLogic {
    /// Finished (web `done`): the effective end (end, or start + 90 min when the agenda has
    /// none) is at or before now. Ends are whole minutes, so this equals the web's minute
    /// arithmetic.
    static func isFinished(_ s: Session, _ now: Date) -> Bool { !s.effectiveEnd.isAfter(now) }

    /// Live (web `live`): start ≤ now < effective end.
    static func isLive(_ s: Session, _ now: Date) -> Bool { !s.start.isAfter(now) && now.isBefore(s.effectiveEnd) }

    /// Whole minutes until the effective end (web `left`), as in "Live · 12 min left".
    static func minutesLeft(_ s: Session, _ now: Date) -> Int { TimeFormat.minutesBetween(now, s.effectiveEnd) }

    /// "Live · N min left", or "On now" for long rows (co-located / off-site) (web `card` pills).
    static func liveLabel(_ s: Session, _ now: Date, long: Bool) -> String {
        long ? "On now" : "Live · \(minutesLeft(s, now)) min left"
    }

    /// Progress of a live session, 0..1, at minute precision like the web's `.bar` (`pct`).
    static func liveProgress(_ s: Session, _ now: Date) -> Float {
        let total = durationMinutes(from: s.start, to: s.effectiveEnd)
        if total <= 0 { return 1 }
        let elapsed = TimeFormat.minutesBetween(s.start, now)
        let pct = (Double(elapsed) * 100.0 / Double(total)).kotlinRoundToInt().coerceIn(0, 100)
        return Float(pct) / 100
    }

    /// Days not yet over (web `visibleDays`): today and later. Before the conference that is
    /// every day; after it, nothing is left, so like the web every day is shown again.
    static func visibleDays(_ days: [Day], _ now: Date) -> [Day] {
        let today = now.localDate
        return days.filter { !($0.date < today) }.ifEmpty { days }
    }

    /// Key of the day whose date is today in Denver, or nil.
    static func todayKey(_ days: [Day], _ now: Date) -> String? {
        let today = now.localDate
        return days.first { $0.date == today }?.key
    }

    /// The day the schedule opens on: today, else the first visible day (web initial `view`).
    static func defaultDayKey(_ days: [Day], _ now: Date) -> String? {
        todayKey(days, now) ?? visibleDays(days, now).first?.key
    }

    /// The day to show: the user's `selected` day while it is still visible, otherwise
    /// ``defaultDayKey(_:_:)`` (web `render`: `if(!vd.some(d=>d.k===view)) view=vd[0].k`, which
    /// at midnight moves a stale selection on to the new today).
    static func resolveDayKey(_ days: [Day], _ now: Date, _ selected: String?) -> String? {
        let visible = visibleDays(days, now)
        if let selected, visible.contains(where: { $0.key == selected }) { return selected }
        return defaultDayKey(days, now)
    }

    /// Half-hour block a start minute falls in: floor(minute / 30) × 30 (web `sk`).
    static func slotKey(_ minuteOfDay: Int) -> Int { floorDiv(minuteOfDay, 30) * 30 }

    /// Header clock: "9:05 AM MST" on a conference day, "Times in MST" otherwise (web `#clock`).
    static func clockLabel(_ days: [Day], _ now: Date) -> String {
        todayKey(days, now) != nil ? TimeFormat.clockLabel(now) : "Times in MST"
    }

    /// Group card time range: earliest remaining start to the group's end, "9:00–10:35 AM".
    static func spanLabel(_ start: Date, _ end: Date) -> String {
        let st = TimeFormat.minuteOfDay(start)
        let en = TimeFormat.minuteOfDay(end)
        let head = TimeFormat.ap(st) != TimeFormat.ap(en) ? TimeFormat.hma(st) : TimeFormat.hm(st)
        return head + "–" + TimeFormat.hma(en)
    }

    /// "In 25 min", "In 1h", "In 2h 5m": the banner countdown for a talk later today (web `renderMine`).
    static func countdownLabel(_ minutesUntil: Int) -> String {
        if minutesUntil < 60 { return "In \(minutesUntil) min" }
        let h = minutesUntil / 60
        let m = minutesUntil % 60
        return "In \(h)h" + (m != 0 ? " \(m)m" : "")
    }

    /// Break-row title without the web's leading ☕ / 🍲 (web `card` for category log).
    static func breakTitle(_ title: String) -> String { BREAK_EMOJI.replace(title, "") }

    /// Now truncated to the minute: the schedule only changes once a minute.
    static func minuteOf(_ now: Date) -> Date { now.truncatedToMinute }

    private static let BREAK_EMOJI = KRegex("^(☕|🍲)\\uFE0F?\\s*")
}
