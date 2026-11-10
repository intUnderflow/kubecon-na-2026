import Foundation

/// Time formatting ported from the web version (schedule_app.js `hm`, `ap`, `hma`, `dur`,
/// `range`). All in America/Denver, 12-hour clock, no leading zero. Minute-of-day values are
/// 0..1439 (larger values wrap, like the web).
enum TimeFormat {
    /// Minutes since local midnight in Denver.
    static func minuteOfDay(_ t: Date) -> Int { t.minuteOfDay }

    /// "9:05" (web `hm`).
    static func hm(_ minuteOfDay: Int) -> String {
        let m = ((minuteOfDay % 1440) + 1440) % 1440
        let h = (m / 60) % 12
        return "\(h == 0 ? 12 : h):" + String(m % 60).padStart(2, "0")
    }

    /// "AM" / "PM" (web `ap`).
    static func ap(_ minuteOfDay: Int) -> String {
        ((minuteOfDay % 1440) + 1440) % 1440 < 720 ? "AM" : "PM"
    }

    /// "9:05 AM" (web `hma`).
    static func hma(_ minuteOfDay: Int) -> String { hm(minuteOfDay) + " " + ap(minuteOfDay) }

    static func hm(_ t: Date) -> String { hm(minuteOfDay(t)) }
    static func ap(_ t: Date) -> String { ap(minuteOfDay(t)) }
    static func hma(_ t: Date) -> String { hma(minuteOfDay(t)) }

    /// "9:00–9:30 AM", "11:30 AM–12:15 PM", or "from 5:30 PM" when the session has no end
    /// (web `range`). Uses an en dash.
    static func range(_ s: Session) -> String {
        let st = minuteOfDay(s.start)
        guard let end = s.end else { return "from " + hma(st) }
        let en = minuteOfDay(end)
        return (ap(st) != ap(en) ? hma(st) : hm(st)) + "–" + hma(en)
    }

    /// Duration label (web `dur`): "45 min", "1h", "1h 30m", prefixed with "~" when
    /// ``Session/endIsEstimate``. Nil when the session has no end (the web shows none).
    static func dur(_ s: Session) -> String? {
        guard let end = s.end else { return nil }
        return (s.endIsEstimate ? "~" : "") + durationLabel(durationMinutes(from: s.start, to: end))
    }

    /// "45 min", "1h", "1h 30m".
    static func durationLabel(_ minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 != 0 { return "\(minutes / 60)h \(minutes % 60)m" }
        if minutes >= 60 { return "\(minutes / 60)h" }
        return "\(minutes) min"
    }

    /// Header clock: "9:05 AM MST".
    static func clockLabel(_ now: Date) -> String { hma(now) + " MST" }

    /// Whole minutes from `now` to `t`, counting like the web (both truncated to the minute),
    /// e.g. "Live · N min left" = minutesBetween(now, effectiveEnd).
    static func minutesBetween(_ now: Date, _ t: Date) -> Int {
        Int((t.truncatedToMinute.epochSecond - now.truncatedToMinute.epochSecond) / 60)
    }
}
