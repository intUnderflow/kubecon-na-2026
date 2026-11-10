import XCTest
@testable import KCNA26Core

/// Port of time/TimeFormatTest.kt.
final class TimeFormatTests: XCTestCase {
    private let repo = TestData.repo

    func testClockFormats() {
        XCTAssertEqual("12:00", TimeFormat.hm(0))
        XCTAssertEqual("AM", TimeFormat.ap(0))
        XCTAssertEqual("12:05 PM", TimeFormat.hma(12 * 60 + 5))
        XCTAssertEqual("9:30 AM", TimeFormat.hma(9 * 60 + 30))
        XCTAssertEqual("1:00 AM", TimeFormat.hma(1440 + 60))
    }

    func testRangesAndDurations() throws {
        let plt = try XCTUnwrap(repo.session("1289955")) // Mon 9:30–9:35 AM
        XCTAssertEqual("9:30–9:35 AM", TimeFormat.range(plt))
        XCTAssertEqual("5 min", TimeFormat.dur(plt))
        let open = try XCTUnwrap(repo.session("m1318417"))
        XCTAssertEqual("from 5:30 PM", TimeFormat.range(open))
        XCTAssertNil(TimeFormat.dur(open))
        let est = try XCTUnwrap(repo.session("m1290687")) // 10:15–11:00, estimate
        XCTAssertEqual("~45 min", TimeFormat.dur(est))
        XCTAssertEqual("1h", TimeFormat.durationLabel(60))
        XCTAssertEqual("1h 30m", TimeFormat.durationLabel(90))
        let hack = try XCTUnwrap(repo.session("1344383")) // 9 AM – 6 PM
        XCTAssertEqual("9:00 AM–6:00 PM", TimeFormat.range(hack))
        XCTAssertEqual("9h", TimeFormat.dur(hack))
    }

    func testFixedAndFakeTimeParsing() throws {
        let c = TestData.clockAt("2026-11-11T09:00:00-07:00")
        XCTAssertEqual(try parseInstant("2026-11-11T16:00:00Z"), c.now())
        XCTAssertEqual(try parseInstant("2026-11-11T16:00:00Z"), try parseFakeNow("2026-11-11T09:00"))
        XCTAssertEqual(try parseInstant("2026-11-11T16:00:00Z"), try parseFakeNow("2026-11-11T16:00:00Z"))
        XCTAssertEqual(9 * 60, TimeFormat.minuteOfDay(c.now()))
        XCTAssertEqual(15, TimeFormat.minutesBetween(c.now(), try parseInstant("2026-11-11T16:15:59Z")))
    }
}
