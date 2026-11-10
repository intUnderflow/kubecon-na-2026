import XCTest
@testable import KCNA26Core

/// LocalDate / LocalDateTime / Date helpers and strict ISO-8601 parsing (java.time rules),
/// including America/Denver's DST changes (2026-03-08 02:00 MST -> 03:00 MDT, 2026-11-01
/// 02:00 MDT -> 01:00 MST).
final class LocalDateTests: XCTestCase {

    private func utc(_ s: String) -> Date { try! parseInstant(s) }

    // MARK: LocalDate

    func testLocalDateBasics() throws {
        let d = try LocalDate.parse("2026-11-08")
        XCTAssertEqual(d, LocalDate(2026, 11, 8))
        XCTAssertEqual(d.year, 2026)
        XCTAssertEqual(d.monthValue, 11)
        XCTAssertEqual(d.dayOfMonth, 8)
        XCTAssertEqual(d.dayOfWeek, .sunday)
        XCTAssertEqual(d.dayOfWeek.value, 7)
        XCTAssertEqual(LocalDate(2026, 11, 9).dayOfWeek, .monday)
        XCTAssertEqual(LocalDate(1970, 1, 1).dayOfWeek, .thursday)
        XCTAssertEqual(d.epochDay, 20765)
        XCTAssertEqual(LocalDate(epochDay: 20765), d)
        XCTAssertEqual(LocalDate(1970, 1, 1).epochDay, 0)
        XCTAssertEqual(LocalDate(epochDay: -1), LocalDate(1969, 12, 31))
        XCTAssertEqual(d.description, "2026-11-08")
        XCTAssertEqual(d.dayOfYear, 312)
        XCTAssertLessThan(LocalDate(2026, 11, 8), LocalDate(2026, 11, 9))
        XCTAssertLessThan(LocalDate(2025, 12, 31), LocalDate(2026, 1, 1))
    }

    func testLocalDateArithmeticAndCalendarRules() {
        XCTAssertEqual(LocalDate(2026, 11, 30).plusDays(1), LocalDate(2026, 12, 1))
        XCTAssertEqual(LocalDate(2026, 12, 31).plusDays(1), LocalDate(2027, 1, 1))
        XCTAssertEqual(LocalDate(2024, 2, 28).plusDays(1), LocalDate(2024, 2, 29))
        XCTAssertEqual(LocalDate(2026, 2, 28).plusDays(1), LocalDate(2026, 3, 1))
        XCTAssertEqual(LocalDate(2026, 3, 1).minusDays(1), LocalDate(2026, 2, 28))
        XCTAssertTrue(LocalDate.isLeapYear(2000))
        XCTAssertFalse(LocalDate.isLeapYear(1900))
        XCTAssertEqual(LocalDate(2024, 2, 1).lengthOfMonth, 29)
        // epochDay round trip over a wide range.
        for day in stride(from: Int64(-800_000), through: 800_000, by: 997) {
            XCTAssertEqual(LocalDate(epochDay: day).epochDay, day)
        }
    }

    func testLocalDateParsingIsStrict() {
        for bad in ["2026-11-8", "2026-1-08", "26-11-08", "2026/11/08", " 2026-11-08", "2026-11-08 ", "2026-13-01",
                    "2026-00-10", "2026-11-31", "2026-02-29", "2026-11-00", "20261-01-01", "+2026-01-01", "2026-11-08T00:00", "",
                    "-0000-01-01"] { // java strict: "minus zero not allowed"
            XCTAssertThrowsError(try LocalDate.parse(bad), bad)
        }
        XCTAssertEqual(try LocalDate.parse("2024-02-29"), LocalDate(2024, 2, 29))
        XCTAssertEqual(try LocalDate.parse("+12026-01-01"), LocalDate(12026, 1, 1))
        XCTAssertEqual(try LocalDate.parse("-0001-01-01"), LocalDate(-1, 1, 1))
        do {
            _ = try LocalDate.parse("2026-02-30")
            XCTFail("no error")
        } catch {
            XCTAssertEqual("\(error)", "Text '2026-02-30' could not be parsed: Invalid date 'FEBRUARY 30'")
        }
        do {
            _ = try LocalDate.parse("9 AM Monday")
            XCTFail("no error")
        } catch {
            XCTAssertEqual("\(error)", "Text '9 AM Monday' could not be parsed at index 0")
        }
    }

    // MARK: Offset date-times and instants

    func testOffsetDateTimeParsing() throws {
        let t = try parseOffsetDateTime("2026-11-09T09:00:00-07:00")
        XCTAssertEqual(t.epochSecond, 1_794_240_000) // 2026-11-09T16:00:00Z
        XCTAssertEqual(t, utc("2026-11-09T16:00:00Z"))
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00:00Z"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09t16:00:00z"), t) // ISO formatters are case-insensitive
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T09:00-07:00"), t) // seconds optional
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T21:30:00+05:30"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00:30+00:00:30"), t)
        // Fractions: 1-9 digits.
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00:00.5Z").epochMillis, t.epochMillis + 500)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00:00.123Z").epochMillis, t.epochMillis + 123)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00:00.123456789Z").epochMillis, t.epochMillis + 123)
        for bad in ["2026-11-09T09:00:00", "2026-11-09 09:00:00-07:00", "2026-11-09T9:00:00-07:00", "2026-11-09T09:00:00-7:00",
                    "2026-11-09T09:00:00-0700", "2026-11-09T09:00:00+19:00", "2026-11-09T24:00:00Z", "2026-11-09T09:60:00Z",
                    "2026-11-09T09:00:60Z", "2026-11-09T09:00:00.1234567890Z", "2026-11-31T09:00:00Z", "9 AM Monday",
                    "2026-11-09T09:00:00-07:00 ", "2026-11-09T09:00:00-07:", "2026-11-09T09:00:00-07:0",
                    "2026-11-09T09:00:00-07:60", "2026-11-09T09:00:00-7", "2026-11-09T09:00:00+19", "2026-11-09T09:00:00+18:00:01",
                    "2026-11-09T09:00:00-07:00:", "2026-11-09T09:00:00-", "-0000-11-09T09:00:00Z"] {
            XCTAssertThrowsError(try parseOffsetDateTime(bad), bad)
        }
    }

    func testOffsetDateTimeReadsTheOffsetLeniently() throws {
        // ISO_OFFSET_DATE_TIME = ...parseLenient().appendOffsetId().parseStrict() (JDK 9+): the
        // offset's minutes and seconds are optional; colons stay required ("-0700" fails).
        let t = utc("2026-11-09T16:00:00Z")
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T09:00:00-07"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T09:00-07"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00+00"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-10T10:00+18"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T09:00:00.000-07"), t)
        XCTAssertEqual(try parseOffsetDateTime("2026-11-09T16:00:30+00:00:30"), t)
        // Instant.parse stays strict about the offset.
        XCTAssertThrowsError(try parseInstant("2026-11-09T09:00:00-07"))
        XCTAssertEqual(try parseInstant("2026-11-09T09:00:00-07:00"), t)
        // So the fake-now argument accepts it (OffsetDateTime is tried first).
        XCTAssertEqual(try parseFakeNow("2026-11-09T09:00-07"), t)
        XCTAssertThrowsError(try parseInstant("-0000-11-09T09:00:00Z"))
        XCTAssertThrowsError(try parseLocalDateTime("-0000-11-09T09:00"))
    }

    func testInstantParsing() throws {
        XCTAssertEqual(try parseInstant("2026-11-11T16:00:00Z").epochSecond, 1_794_412_800)
        XCTAssertEqual(try parseInstant("2026-11-11T09:00:00-07:00"), try parseInstant("2026-11-11T16:00:00Z"))
        XCTAssertThrowsError(try parseInstant("2026-11-11T16:00Z")) // seconds are required
        XCTAssertThrowsError(try parseInstant("2026-11-11T16:00:00")) // and an offset
        // java.time's special cases.
        XCTAssertEqual(try parseInstant("2026-12-31T24:00:00Z"), try parseInstant("2027-01-01T00:00:00Z"))
        XCTAssertEqual(try parseInstant("2026-12-31T23:59:60Z"), try parseInstant("2026-12-31T23:59:59Z"))
        XCTAssertThrowsError(try parseInstant("2026-12-31T24:00:01Z"))
    }

    func testFakeNowAcceptsAllThreeForms() throws {
        let expected = utc("2026-11-11T16:00:00Z")
        XCTAssertEqual(try parseFakeNow("2026-11-11T09:00:00-07:00"), expected)
        XCTAssertEqual(try parseFakeNow("2026-11-11T16:00:00Z"), expected)
        XCTAssertEqual(try parseFakeNow("2026-11-11T09:00"), expected) // Denver local
        XCTAssertEqual(try parseFakeNow("2026-11-11T09:00:00"), expected)
        XCTAssertThrowsError(try parseFakeNow("tomorrow"))
        XCTAssertEqual(TestData.instant("2026-11-11T09:00"), expected)
        XCTAssertEqual(try FixedClock.parse("2026-11-11T09:00").now(), expected)
    }

    // MARK: Denver local time and DST

    func testLocalDateTimeParsingAndFormatting() throws {
        let t = try LocalDateTime.parse("2026-11-11T09:05")
        XCTAssertEqual(t.hour, 9)
        XCTAssertEqual(t.minute, 5)
        XCTAssertEqual(t.second, 0)
        XCTAssertEqual(t.minuteOfDay, 545)
        XCTAssertEqual(t.description, "2026-11-11T09:05")
        XCTAssertEqual(try LocalDateTime.parse("2026-11-11T09:05:07.25").description, "2026-11-11T09:05:07.250")
        XCTAssertEqual(try LocalDateTime.parse("2026-11-11T09:05:07").description, "2026-11-11T09:05:07")
        XCTAssertThrowsError(try LocalDateTime.parse("2026-11-11T09:05Z"))
        XCTAssertThrowsError(try LocalDateTime.parse("2026-11-11"))
        XCTAssertEqual(t.plusMinutes(60 * 15).description, "2026-11-12T00:05")
        XCTAssertLessThan(t, t.plusSeconds(1))
        XCTAssertEqual(t.truncatedToMinute(), t)
    }

    func testInstantToDenverLocal() {
        let t = utc("2026-11-11T16:00:00Z")
        XCTAssertEqual(t.localDateTime.description, "2026-11-11T09:00")
        XCTAssertEqual(t.localDate, LocalDate(2026, 11, 11))
        XCTAssertEqual(t.minuteOfDay, 540)
        XCTAssertEqual(t.zoneOffsetSeconds, -7 * 3600)
        // Just before local midnight is still the previous day.
        XCTAssertEqual(utc("2026-11-09T06:59:59Z").localDate, LocalDate(2026, 11, 8))
        XCTAssertEqual(utc("2026-11-09T07:00:00Z").localDate, LocalDate(2026, 11, 9))
        // Summer: MDT (UTC-6).
        XCTAssertEqual(utc("2026-07-04T18:00:00Z").localDateTime.description, "2026-07-04T12:00")
        XCTAssertEqual(utc("2026-07-04T18:00:00Z").zoneOffsetSeconds, -6 * 3600)
    }

    func testFallBackOverlapOnNovember1() {
        // 01:30 happens twice: 07:30Z (MDT) and 08:30Z (MST).
        XCTAssertEqual(utc("2026-11-01T07:30:00Z").localDateTime.description, "2026-11-01T01:30")
        XCTAssertEqual(utc("2026-11-01T08:30:00Z").localDateTime.description, "2026-11-01T01:30")
        XCTAssertEqual(utc("2026-11-01T07:59:59Z").zoneOffsetSeconds, -6 * 3600)
        XCTAssertEqual(utc("2026-11-01T08:00:00Z").zoneOffsetSeconds, -7 * 3600)
        // java.time picks the earlier offset (MDT) for the ambiguous local time.
        XCTAssertEqual(LocalDateTime(LocalDate(2026, 11, 1), 1, 30).atZone(ZONE), utc("2026-11-01T07:30:00Z"))
        XCTAssertEqual(LocalDateTime(LocalDate(2026, 11, 1), 0, 59).atZone(ZONE), utc("2026-11-01T06:59:00Z"))
        XCTAssertEqual(LocalDateTime(LocalDate(2026, 11, 1), 2, 0).atZone(ZONE), utc("2026-11-01T09:00:00Z"))
        // That day has 25 hours.
        let start = LocalDate(2026, 11, 1).atStartOfDay()
        let next = LocalDate(2026, 11, 2).atStartOfDay()
        XCTAssertEqual(start, utc("2026-11-01T06:00:00Z"))
        XCTAssertEqual(next.timeIntervalSince(start), 25 * 3600)
        XCTAssertEqual(LocalDate(2026, 11, 8).atStartOfDay(), utc("2026-11-08T07:00:00Z"))
        // Minute of day around the change.
        XCTAssertEqual(utc("2026-11-01T08:30:00Z").minuteOfDay, 90)
    }

    func testSpringForwardGapOnMarch8() {
        // 02:00–02:59 does not exist; java.time moves it later by the gap (1 h).
        XCTAssertEqual(LocalDateTime(LocalDate(2026, 3, 8), 2, 30).atZone(ZONE), utc("2026-03-08T09:30:00Z"))
        XCTAssertEqual(utc("2026-03-08T09:30:00Z").localDateTime.description, "2026-03-08T03:30")
        XCTAssertEqual(LocalDateTime(LocalDate(2026, 3, 8), 1, 59).atZone(ZONE), utc("2026-03-08T08:59:00Z"))
        XCTAssertEqual(LocalDateTime(LocalDate(2026, 3, 8), 3, 0).atZone(ZONE), utc("2026-03-08T09:00:00Z"))
        XCTAssertEqual(LocalDate(2026, 3, 9).atStartOfDay().timeIntervalSince(LocalDate(2026, 3, 8).atStartOfDay()), 23 * 3600)
    }

    // MARK: Date helpers

    func testEpochMillisRoundTrip() {
        for ms: Int64 in [0, 1, -1, 999, 1_794_412_800_123, 1_794_412_800_999, -62_135_596_800_000, 4_102_444_800_123] {
            XCTAssertEqual(Date(epochMillis: ms).epochMillis, ms, "\(ms)")
        }
        XCTAssertEqual(Date(epochSecond: 1_794_412_800).epochMillis, 1_794_412_800_000)
        XCTAssertEqual(Date(epochSecond: -1, nanos: 500_000_000).epochMillis, -500)
        XCTAssertEqual(Date(epochMillis: -1).epochSecond, -1)
        XCTAssertEqual(Date(epochMillis: 1_500).plusMillis(-501).epochMillis, 999)
    }

    func testTruncationAndDurations() {
        let t = utc("2026-11-11T16:15:59Z").plusMillis(999)
        XCTAssertEqual(t.truncatedToMinute, utc("2026-11-11T16:15:00Z"))
        XCTAssertEqual(utc("2026-11-11T16:15:00Z").truncatedToMinute, utc("2026-11-11T16:15:00Z"))
        let a = utc("2026-11-09T16:30:00Z")
        XCTAssertEqual(durationMinutes(from: a, to: a.plusMinutes(5)), 5)
        XCTAssertEqual(durationMinutes(from: a, to: a.plusSeconds(299)), 4)
        XCTAssertEqual(durationMinutes(from: a.plusMinutes(5), to: a), -5)
        XCTAssertEqual(durationMinutes(from: a, to: a.plusSeconds(-30)), 0) // truncates toward zero
        XCTAssertEqual(durationSeconds(from: a, to: a.plusMillis(-1)), -1)
        XCTAssertEqual(TimeFormat.minutesBetween(a.plusSeconds(59), a.plusSeconds(60)), 1)
        XCTAssertEqual(TimeFormat.minutesBetween(a.plusSeconds(60), a.plusSeconds(59)), -1)
        XCTAssertTrue(a.isBefore(a.plusMinutes(1)))
        XCTAssertTrue(a.plusMinutes(1).isAfter(a))
        XCTAssertEqual(a.minusMinutes(30), utc("2026-11-09T16:00:00Z"))
    }
}
