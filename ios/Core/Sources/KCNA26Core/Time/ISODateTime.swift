import Foundation

// Strict ISO-8601 parsing with java.time's rules:
//
//   parseOffsetDateTime("2026-11-09T09:00:00-07:00")   // OffsetDateTime.parse(s).toInstant()
//   parseInstant("2026-11-11T16:00:00Z")               // Instant.parse(s)
//   LocalDateTime.parse("2026-11-11T09:00")            // LocalDateTime.parse(s)
//   LocalDate.parse("2026-11-08")                      // LocalDate.parse(s)
//
// Shared grammar (DateTimeFormatter.ISO_*): date `uuuu-MM-dd` (4-digit year; more digits need a
// '+'; no "-0000"), 'T' (any case), time `HH:mm[:ss[.fraction]]` with a 0–9 digit fraction,
// offset `Z` (any case) or `+HH:MM[:SS]` (at most ±18:00). Field ranges are strict (no Feb 30, no
// 24:00, no :60). OffsetDateTime.parse reads the offset leniently, as ISO_OFFSET_DATE_TIME does
// since JDK 9 (`parseLenient().appendOffsetId()`): `+HH`, `+HH:MM` or `+HH:MM:SS` (never
// `+HHMM`). Instant.parse is strict about the offset (`+HH:MM[:SS]`), requires seconds and, like
// java.time, accepts 24:00:00 (next day) and a 23:59:60 leap second (read as 23:59:59).
//
// Errors are ``DateTimeParseError`` (java `DateTimeParseException`).

/// java `DateTimeParseException`: the text and where parsing stopped.
struct DateTimeParseError: Error, CustomStringConvertible, Equatable {
    let text: String
    /// UTF-8 offset of the problem (java's index, for ASCII input).
    let index: Int
    /// Extra detail for range errors ("Invalid date 'FEBRUARY 30'"), else nil.
    let reason: String?

    var description: String {
        if let reason { return "Text '\(text)' could not be parsed: \(reason)" }
        return "Text '\(text)' could not be parsed at index \(index)"
    }
}

/// java `OffsetDateTime.parse(text).toInstant()`.
func parseOffsetDateTime(_ text: String) throws(DateTimeParseError) -> Date {
    var p = ISOParser(text)
    return try p.parseWholeOffsetDateTime()
}

/// java `Instant.parse(text)` (ISO_INSTANT; offsets other than Z accepted, as since JDK 12).
func parseInstant(_ text: String) throws(DateTimeParseError) -> Date {
    var p = ISOParser(text)
    return try p.parseWholeInstant()
}

/// java `LocalDateTime.parse(text)` (typed-throws form of ``LocalDateTime/parse(_:)``).
func parseLocalDateTime(_ text: String) throws(DateTimeParseError) -> LocalDateTime {
    var p = ISOParser(text)
    return try p.parseWholeLocalDateTime()
}

/// java `LocalDate.parse(text)` (typed-throws form of ``LocalDate/parse(_:)``).
func parseLocalDate(_ text: String) throws(DateTimeParseError) -> LocalDate {
    var p = ISOParser(text)
    return try p.parseWholeLocalDate()
}

/// The scanner behind the ISO parsers.
struct ISOParser {
    let text: String
    private let u: [UInt8]
    private var i = 0

    init(_ text: String) {
        self.text = text
        u = Array(text.utf8)
    }

    private func fail(_ at: Int? = nil, _ reason: String? = nil) -> DateTimeParseError {
        DateTimeParseError(text: text, index: at ?? i, reason: reason)
    }

    private func isDigit(_ k: Int) -> Bool { k < u.count && u[k] >= 0x30 && u[k] <= 0x39 }

    /// Exactly `count` digits.
    private mutating func digits(_ count: Int) throws(DateTimeParseError) -> Int {
        var v = 0
        for _ in 0..<count {
            guard isDigit(i) else { throw fail() }
            v = v * 10 + Int(u[i] - 0x30)
            i += 1
        }
        return v
    }

    private mutating func expect(_ c: UInt8) throws(DateTimeParseError) {
        guard i < u.count, u[i] == c else { throw fail() }
        i += 1
    }

    /// 'T' or 't' (the ISO formatters parse case-insensitively).
    private mutating func expectT() throws(DateTimeParseError) {
        guard i < u.count, u[i] == 0x54 || u[i] == 0x74 else { throw fail() }
        i += 1
    }

    private func expectEnd() throws(DateTimeParseError) {
        guard i == u.count else { throw fail() }
    }

    private static let monthNames = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
                                     "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

    /// `uuuu-MM-dd`.
    private mutating func localDate() throws(DateTimeParseError) -> LocalDate {
        let start = i
        var sign = 0
        if i < u.count, u[i] == 0x2B || u[i] == 0x2D {
            sign = u[i] == 0x2B ? 1 : -1
            i += 1
        }
        let digitsStart = i
        var year = 0
        while isDigit(i) && i - digitsStart < 10 {
            year = year * 10 + Int(u[i] - 0x30)
            i += 1
        }
        let n = i - digitsStart
        // EXCEEDS_PAD: 4 digits unsigned; more than 4 only with a sign ('+' needs more than 4).
        if n < 4 || (sign == 0 && n > 4) || (sign == 1 && n <= 4) { throw fail(start) }
        if sign == -1 && year == 0 { throw fail(start) } // strict parsing: "minus zero not allowed"
        if sign == -1 { year = -year }
        try expect(0x2D)
        let month = try digits(2)
        try expect(0x2D)
        let day = try digits(2)
        guard (1...12).contains(month) else {
            throw fail(start, "Invalid value for MonthOfYear (valid values 1 - 12): \(month)")
        }
        guard (1...31).contains(day) else {
            throw fail(start, "Invalid value for DayOfMonth (valid values 1 - 28/31): \(day)")
        }
        guard LocalDate.isValid(year, month, day) else {
            if month == 2 && day == 29 {
                throw fail(start, "Invalid date 'February 29' as '\(year)' is not a leap year")
            }
            throw fail(start, "Invalid date '\(Self.monthNames[month - 1]) \(day)'")
        }
        return LocalDate(year, month, day)
    }

    /// `HH:mm[:ss[.fffffffff]]`; raw (unchecked) values for Instant's special cases.
    private mutating func rawTime(secondsRequired: Bool) throws(DateTimeParseError) -> (h: Int, m: Int, s: Int, nano: Int) {
        let h = try digits(2)
        try expect(0x3A)
        let m = try digits(2)
        var s = 0, nano = 0
        if i < u.count && u[i] == 0x3A {
            i += 1
            s = try digits(2)
            if i < u.count && u[i] == 0x2E { // '.' then 0...9 digits
                i += 1
                var count = 0
                while isDigit(i) && count < 9 {
                    nano = nano * 10 + Int(u[i] - 0x30)
                    i += 1
                    count += 1
                }
                for _ in count..<9 { nano *= 10 }
            }
        } else if secondsRequired {
            throw fail()
        }
        return (h, m, s, nano)
    }

    private func checkTime(_ t: (h: Int, m: Int, s: Int, nano: Int), at start: Int) throws(DateTimeParseError) {
        guard (0...23).contains(t.h) else { throw fail(start, "Invalid value for HourOfDay (valid values 0 - 23): \(t.h)") }
        guard (0...59).contains(t.m) else { throw fail(start, "Invalid value for MinuteOfHour (valid values 0 - 59): \(t.m)") }
        guard (0...59).contains(t.s) else { throw fail(start, "Invalid value for SecondOfMinute (valid values 0 - 59): \(t.s)") }
    }

    private mutating func localDateTime() throws(DateTimeParseError) -> LocalDateTime {
        let start = i
        let d = try localDate()
        try expectT()
        let t = try rawTime(secondsRequired: false)
        try checkTime(t, at: start)
        return LocalDateTime(d, t.h, t.m, t.s, nanos: t.nano)
    }

    /// `Z` | `+HH:MM` | `+HH:MM:SS`, in seconds east of UTC (java `appendOffsetId()`).
    /// `lenient` (java's `parseLenient()` around it): the minutes are optional too (`+HH`); a
    /// `:MM` / `:SS` part is taken only when it is a colon and two digits 00–59, otherwise
    /// parsing stops there (and the leftover text fails the whole parse, as in java).
    private mutating func offsetSeconds(lenient: Bool = false) throws(DateTimeParseError) -> Int {
        guard i < u.count else { throw fail() }
        if u[i] == 0x5A || u[i] == 0x7A { // Z z
            i += 1
            return 0
        }
        guard u[i] == 0x2B || u[i] == 0x2D else { throw fail() }
        let start = i
        let negative = u[i] == 0x2D
        i += 1
        var mm = 0, ss = 0
        let hh: Int
        if lenient {
            guard let h = colonPair(at: i, colon: false) else { throw fail(start) }
            hh = h
            i += 2
            if let m = colonPair(at: i, colon: true) {
                mm = m
                i += 3
                if let s = colonPair(at: i, colon: true) {
                    ss = s
                    i += 3
                }
            }
        } else {
            hh = try digits(2)
            try expect(0x3A)
            mm = try digits(2)
            if i < u.count && u[i] == 0x3A {
                i += 1
                ss = try digits(2)
            }
        }
        guard hh <= 18, mm <= 59, ss <= 59 else { throw fail(start) }
        let total = hh * 3600 + mm * 60 + ss
        guard total <= 18 * 3600 else {
            throw fail(start, "Zone offset not in valid range: -18:00 to +18:00")
        }
        return negative ? -total : total
    }

    /// Two digits 00–59 at `k` (after a ':' when `colon`), as java's lenient offset parser reads
    /// each part; nil when they are not there.
    private func colonPair(at k: Int, colon: Bool) -> Int? {
        var k = k
        if colon {
            guard k < u.count, u[k] == 0x3A else { return nil }
            k += 1
        }
        guard isDigit(k), isDigit(k + 1) else { return nil }
        let v = Int(u[k] - 0x30) * 10 + Int(u[k + 1] - 0x30)
        return v <= 59 ? v : nil
    }

    mutating func parseWholeLocalDate() throws(DateTimeParseError) -> LocalDate {
        let d = try localDate()
        try expectEnd()
        return d
    }

    mutating func parseWholeLocalDateTime() throws(DateTimeParseError) -> LocalDateTime {
        let t = try localDateTime()
        try expectEnd()
        return t
    }

    mutating func parseWholeOffsetDateTime() throws(DateTimeParseError) -> Date {
        let t = try localDateTime()
        let off = try offsetSeconds(lenient: true)
        try expectEnd()
        return Date(epochSecond: t.localEpochSecond - Int64(off), nanos: t.nano)
    }

    mutating func parseWholeInstant() throws(DateTimeParseError) -> Date {
        let start = i
        var d = try localDate()
        try expectT()
        var t = try rawTime(secondsRequired: true)
        if t.h == 24 && t.m == 0 && t.s == 0 && t.nano == 0 {
            t.h = 0
            d = d.plusDays(1)
        } else if t.h == 23 && t.m == 59 && t.s == 60 {
            t.s = 59
        }
        try checkTime(t, at: start)
        let off = try offsetSeconds()
        try expectEnd()
        let local = LocalDateTime(d, t.h, t.m, t.s, nanos: t.nano)
        return Date(epochSecond: local.localEpochSecond - Int64(off), nanos: t.nano)
    }
}
