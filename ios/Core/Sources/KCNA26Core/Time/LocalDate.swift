import Foundation

// java.time equivalents for the app's America/Denver arithmetic: `Instant` -> `Date`,
// `LocalDate`, `LocalDateTime`, `DayOfWeek`, `ZonedDateTime` (as a Date plus the Denver
// `LocalDateTime` you get from `date.localDateTime`). Calendar arithmetic is done with the
// proleptic Gregorian epoch-day algorithms java.time uses; the time zone is only asked for its
// UTC offset at an instant, so results match java.time exactly (including DST gaps/overlaps).

/// All conference times are in this zone (MST, UTC−7 during the event). Kotlin `ZONE`.
let ZONE: TimeZone = TimeZone(identifier: "America/Denver")!

/// A Gregorian calendar in ``ZONE`` (POSIX locale), for the rare cases that need `Calendar`
/// (e.g. `DateFormatter`s in the app layer). Core arithmetic does not use it.
let zoneCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = ZONE
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}()

/// java.time `DayOfWeek`: Monday = 1 ... Sunday = 7.
enum DayOfWeek: Int, Sendable, Hashable, Comparable, CaseIterable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// java `getValue()`: 1 (Monday) ... 7 (Sunday).
    var value: Int { rawValue }

    static func < (a: DayOfWeek, b: DayOfWeek) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - LocalDate

/// java.time `LocalDate`: a date without a time zone (ISO proleptic Gregorian).
///
/// ```swift
/// let d = try LocalDate.parse("2026-11-08")   // LocalDate.parse
/// LocalDate(2026, 11, 8).dayOfWeek             // .sunday
/// d.plusDays(1) == LocalDate(2026, 11, 9)
/// d.atStartOfDay()                             // Date of 2026-11-08T00:00-07:00
/// session.start.localDate == d                 // instant.atZone(ZONE).toLocalDate()
/// ```
struct LocalDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    /// 1...12 (java `getMonthValue()`).
    let monthValue: Int
    /// 1...31 (java `getDayOfMonth()`).
    let dayOfMonth: Int

    /// java `LocalDate.of(y, m, d)`. Traps on an invalid date (java throws DateTimeException);
    /// use ``isValid(_:_:_:)`` or ``parse(_:)`` for untrusted input.
    init(_ year: Int, _ month: Int, _ day: Int) {
        precondition(LocalDate.isValid(year, month, day), "Invalid date \(year)-\(month)-\(day)")
        self.year = year
        monthValue = month
        dayOfMonth = day
    }

    /// The date `epochDay` days after 1970-01-01 (java `LocalDate.ofEpochDay`).
    init(epochDay: Int64) {
        // Howard Hinnant's civil_from_days.
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        year = Int(yoe + era * 400 + (m <= 2 ? 1 : 0))
        monthValue = Int(m)
        dayOfMonth = Int(d)
    }

    /// True when year/month/day form a real date.
    static func isValid(_ year: Int, _ month: Int, _ day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        return day <= lengthOfMonth(year, month)
    }

    static func isLeapYear(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func lengthOfMonth(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return isLeapYear(y) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// java `isLeapYear()`.
    var isLeapYear: Bool { LocalDate.isLeapYear(year) }

    /// java `lengthOfMonth()`.
    var lengthOfMonth: Int { LocalDate.lengthOfMonth(year, monthValue) }

    /// Days since 1970-01-01 (java `toEpochDay()`).
    var epochDay: Int64 {
        // Howard Hinnant's days_from_civil.
        let y = Int64(monthValue <= 2 ? year - 1 : year)
        let m = Int64(monthValue)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + Int64(dayOfMonth) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// java `getDayOfWeek()`.
    var dayOfWeek: DayOfWeek { DayOfWeek(rawValue: Int(floorMod(epochDay + 3, 7)) + 1)! }

    /// java `getDayOfYear()`: 1...366.
    var dayOfYear: Int { Int(epochDay - LocalDate(year, 1, 1).epochDay) + 1 }

    func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + Int64(n)) }
    func minusDays(_ n: Int) -> LocalDate { plusDays(-n) }

    /// java `atTime(hour, minute, second)`.
    func atTime(_ hour: Int, _ minute: Int, _ second: Int = 0, nanos: Int = 0) -> LocalDateTime {
        LocalDateTime(self, hour, minute, second, nanos: nanos)
    }

    /// java `atStartOfDay(zone).toInstant()`: the first instant of this date in `zone`
    /// (midnight, or the end of a DST gap at midnight).
    func atStartOfDay(in zone: TimeZone = ZONE) -> Date {
        atTime(0, 0).atZone(zone)
    }

    /// "2026-11-08" (java `toString()`).
    var description: String {
        let y: String
        if year >= 0 && year <= 9999 {
            y = String(year).padStart(4, "0")
        } else if year > 9999 {
            y = "+" + String(year)
        } else {
            y = "-" + String(-year).padStart(4, "0")
        }
        return y + "-" + String(monthValue).padStart(2, "0") + "-" + String(dayOfMonth).padStart(2, "0")
    }

    static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.monthValue, a.dayOfMonth) < (b.year, b.monthValue, b.dayOfMonth)
    }

    /// java `LocalDate.parse("2026-11-08")` (ISO_LOCAL_DATE, strict).
    static func parse(_ text: String) throws -> LocalDate {
        try parseLocalDate(text)
    }
}

// MARK: - LocalDateTime

/// java.time `LocalDateTime`: a date and wall-clock time without a zone.
///
/// ```swift
/// let t = try LocalDateTime.parse("2026-11-11T09:00")
/// t.atZone(ZONE)                // Date: 2026-11-11T16:00:00Z
/// session.start.localDateTime   // instant.atZone(ZONE).toLocalDateTime()
/// ```
struct LocalDateTime: Sendable, Hashable, Comparable, CustomStringConvertible {
    let date: LocalDate
    /// 0...23
    let hour: Int
    /// 0...59
    let minute: Int
    /// 0...59
    let second: Int
    /// 0...999_999_999
    let nano: Int

    /// java `LocalDateTime.of(...)`. Traps on out-of-range fields (java throws).
    init(_ date: LocalDate, _ hour: Int, _ minute: Int, _ second: Int = 0, nanos: Int = 0) {
        precondition((0...23).contains(hour) && (0...59).contains(minute) && (0...59).contains(second)
            && (0...999_999_999).contains(nanos), "Invalid time \(hour):\(minute):\(second).\(nanos)")
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
        nano = nanos
    }

    /// From seconds since 1970-01-01T00:00 local (plus nanos).
    init(localEpochSecond s: Int64, nanos: Int = 0) {
        let day = floorDiv(s, 86_400)
        let sod = Int(floorMod(s, 86_400))
        self.init(LocalDate(epochDay: day), sod / 3600, (sod / 60) % 60, sod % 60, nanos: nanos)
    }

    var year: Int { date.year }
    var monthValue: Int { date.monthValue }
    var dayOfMonth: Int { date.dayOfMonth }
    var dayOfWeek: DayOfWeek { date.dayOfWeek }

    /// java `toLocalDate()`.
    func toLocalDate() -> LocalDate { date }

    /// Minutes since local midnight: hour * 60 + minute.
    var minuteOfDay: Int { hour * 60 + minute }

    /// Seconds since local midnight.
    var secondOfDay: Int { hour * 3600 + minute * 60 + second }

    /// Seconds since 1970-01-01T00:00 in this local time line.
    var localEpochSecond: Int64 { date.epochDay * 86_400 + Int64(secondOfDay) }

    func plusMinutes(_ n: Int) -> LocalDateTime { LocalDateTime(localEpochSecond: localEpochSecond + Int64(n) * 60, nanos: nano) }
    func plusSeconds(_ n: Int) -> LocalDateTime { LocalDateTime(localEpochSecond: localEpochSecond + Int64(n), nanos: nano) }
    func plusDays(_ n: Int) -> LocalDateTime { LocalDateTime(date.plusDays(n), hour, minute, second, nanos: nano) }

    /// java `truncatedTo(ChronoUnit.MINUTES)`.
    func truncatedToMinute() -> LocalDateTime { LocalDateTime(date, hour, minute) }

    /// java `atZone(zone).toInstant()`, with java's rules for DST changes: in a gap (spring
    /// forward) the time moves later by the gap's length; in an overlap (fall back) the earlier
    /// offset (the one before the change, i.e. the earlier instant) is used.
    func atZone(_ zone: TimeZone = ZONE) -> Date {
        let local = localEpochSecond
        // Offsets a day either side of the wall time; DST changes are months apart.
        let before = zone.secondsFromGMT(for: Date(epochSecond: local - 86_400))
        let after = zone.secondsFromGMT(for: Date(epochSecond: local + 86_400))
        let candidates = before == after ? [before] : [before, after]
        let valid = candidates.filter { off in
            zone.secondsFromGMT(for: Date(epochSecond: local - Int64(off))) == off
        }
        let offset: Int
        if let best = valid.max() {
            offset = best // overlap: the larger offset is the one before the change (earlier instant)
        } else {
            offset = before // gap: keep the pre-gap offset, i.e. shift later by the gap
        }
        return Date(epochSecond: local - Int64(offset), nanos: nano)
    }

    /// "2026-11-11T09:00" / "2026-11-11T09:00:30" / "...:30.5" (java `toString()`).
    var description: String {
        var s = date.description + "T" + String(hour).padStart(2, "0") + ":" + String(minute).padStart(2, "0")
        if second != 0 || nano != 0 {
            s += ":" + String(second).padStart(2, "0")
            if nano != 0 {
                if nano % 1_000_000 == 0 {
                    s += "." + String(nano / 1_000_000).padStart(3, "0")
                } else if nano % 1000 == 0 {
                    s += "." + String(nano / 1000).padStart(6, "0")
                } else {
                    s += "." + String(nano).padStart(9, "0")
                }
            }
        }
        return s
    }

    static func < (a: LocalDateTime, b: LocalDateTime) -> Bool {
        (a.localEpochSecond, a.nano) < (b.localEpochSecond, b.nano)
    }

    /// java `LocalDateTime.parse` (ISO_LOCAL_DATE_TIME: "2026-11-11T09:00", seconds and a
    /// 0–9 digit fraction optional; 'T' case-insensitive; strict field ranges).
    static func parse(_ text: String) throws -> LocalDateTime {
        try parseLocalDateTime(text)
    }
}

// MARK: - Date (Instant) helpers

extension Date {
    /// 1970-01-01 to 2001-01-01, in seconds (Foundation's reference date).
    private static let referenceEpochSeconds: Int64 = 978_307_200

    /// java `Instant.ofEpochMilli(ms)`.
    init(epochMillis ms: Int64) {
        self.init(timeIntervalSinceReferenceDate: Double(ms - Date.referenceEpochSeconds * 1000) / 1000)
    }

    /// java `Instant.ofEpochSecond(s, nanos)`.
    init(epochSecond s: Int64, nanos: Int = 0) {
        let whole = Double(s - Date.referenceEpochSeconds)
        self.init(timeIntervalSinceReferenceDate: nanos == 0 ? whole : whole + Double(nanos) / 1e9)
    }

    /// java `toEpochMilli()`: milliseconds since 1970 (floor; exact for dates made from millis).
    var epochMillis: Int64 {
        let x = timeIntervalSinceReferenceDate * 1000
        let r = x.rounded()
        // Within float noise of a whole millisecond: that millisecond; otherwise floor.
        let ms = abs(x - r) < 1e-3 ? r : x.rounded(.down)
        return Int64(ms) + Date.referenceEpochSeconds * 1000
    }

    /// java `getEpochSecond()`: whole seconds since 1970 (floor).
    var epochSecond: Int64 { floorDiv(epochMillis, 1000) }

    /// java `truncatedTo(ChronoUnit.MINUTES)` (UTC minutes; Denver's offset is whole hours).
    var truncatedToMinute: Date { Date(epochSecond: floorDiv(epochSecond, 60) * 60) }

    /// java `plusMillis` / `plusSeconds` / `plus(Duration.ofMinutes(n))`.
    func plusMillis(_ n: Int64) -> Date { Date(epochMillis: epochMillis + n) }
    func plusSeconds(_ n: Int64) -> Date { addingTimeInterval(TimeInterval(n)) }
    func plusMinutes(_ n: Int) -> Date { addingTimeInterval(TimeInterval(n) * 60) }
    func minusMinutes(_ n: Int) -> Date { plusMinutes(-n) }

    /// java `isBefore` / `isAfter` (for literal ports; `<` / `>` work too).
    func isBefore(_ other: Date) -> Bool { self < other }
    func isAfter(_ other: Date) -> Bool { self > other }

    /// The UTC offset in ``ZONE`` at this instant, in seconds (-25200 for MST).
    var zoneOffsetSeconds: Int { ZONE.secondsFromGMT(for: self) }

    /// `atZone(ZONE).toLocalDateTime()`: the Denver wall-clock time.
    var localDateTime: LocalDateTime { localDateTime(in: ZONE) }

    /// `atZone(zone).toLocalDateTime()`.
    func localDateTime(in zone: TimeZone) -> LocalDateTime {
        let ms = epochMillis
        let s = floorDiv(ms, 1000)
        let local = s + Int64(zone.secondsFromGMT(for: self))
        return LocalDateTime(localEpochSecond: local, nanos: Int(floorMod(ms, 1000)) * 1_000_000)
    }

    /// `atZone(ZONE).toLocalDate()`: the Denver calendar date.
    var localDate: LocalDate { localDateTime.date }

    /// Denver minutes since local midnight (`z.hour * 60 + z.minute`).
    var minuteOfDay: Int { localDateTime.minuteOfDay }
}

/// java `Duration.between(a, b).toMinutes()`: whole minutes, truncated toward zero.
func durationMinutes(from a: Date, to b: Date) -> Int {
    let ms = b.epochMillis - a.epochMillis
    // Duration's seconds are floored (nanos kept positive), then toMinutes truncates.
    return Int(floorDiv(ms, 1000) / 60)
}

/// java `Duration.between(a, b).getSeconds()` (floor).
func durationSeconds(from a: Date, to b: Date) -> Int64 {
    floorDiv(b.epochMillis - a.epochMillis, 1000)
}
