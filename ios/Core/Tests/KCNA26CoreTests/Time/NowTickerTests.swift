import XCTest
@testable import KCNA26Core

/// NowTicker (the port of Now.kt's rememberNow) and its delay rule.
@MainActor
final class NowTickerTests: XCTestCase {

    func testNextDelayAlignsToThePeriodPlus20ms() {
        XCTAssertEqual(NowTicker.nextDelayMillis(nowEpochMillis: 0, periodMillis: 15_000), 15_020)
        XCTAssertEqual(NowTicker.nextDelayMillis(nowEpochMillis: 14_999, periodMillis: 15_000), 21)
        XCTAssertEqual(NowTicker.nextDelayMillis(nowEpochMillis: 15_000, periodMillis: 15_000), 15_020)
        XCTAssertEqual(NowTicker.nextDelayMillis(nowEpochMillis: 1_794_412_807_500, periodMillis: 15_000), 7_520)
        XCTAssertEqual(NowTicker.nextDelayMillis(nowEpochMillis: -1, periodMillis: 15_000), 21) // floorMod
        XCTAssertEqual(NowTicker.nextDelayMillis(nowEpochMillis: 59_990, periodMillis: 60_000), 30)
        XCTAssertEqual(NOW_PERIOD_MS, 15_000)
    }

    func testStartsAtTheClocksNowAndRefreshes() {
        let clock = TestData.clockAt("2026-11-11T09:00:00-07:00")
        let ticker = NowTicker(clock: clock, running: false)
        XCTAssertEqual(ticker.now, clock.now())
        XCTAssertFalse(ticker.isRunning)
        clock.instant = clock.instant.plusMinutes(1)
        XCTAssertNotEqual(ticker.now, clock.now())
        ticker.refresh()
        XCTAssertEqual(ticker.now, clock.now())
        // resume() refreshes at once (back in the foreground).
        clock.instant = clock.instant.plusMinutes(1)
        ticker.resume()
        XCTAssertTrue(ticker.isRunning)
        XCTAssertEqual(ticker.now, clock.now())
        ticker.pause()
        XCTAssertFalse(ticker.isRunning)
    }

    func testTicksWhileRunningAndStopsWhenPaused() async throws {
        let clock = FixedClock(Date(epochMillis: 1_000_000))
        let ticker = NowTicker(clock: clock, periodMillis: 30)
        XCTAssertTrue(ticker.isRunning)
        clock.instant = Date(epochMillis: 2_000_000)
        try await waitUntil { ticker.now == clock.now() }
        ticker.pause()
        clock.instant = Date(epochMillis: 3_000_000)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(ticker.now, Date(epochMillis: 2_000_000))
        ticker.resume()
        XCTAssertEqual(ticker.now, Date(epochMillis: 3_000_000))
        ticker.pause()
    }

    func testAFakeTimeChangeRefreshesImmediately() async throws {
        let clock = FakeableClock(InMemoryStore(), allowFake: true)
        let ticker = NowTicker(clock: clock, running: false) // even while paused
        let target = TestData.instant("2026-11-11T09:00:00-07:00")
        clock.setFakeNow(target)
        try await waitUntil { abs(ticker.now.timeIntervalSince(target)) < 2 }
        // And again (the observation re-registers each time).
        clock.clearFakeNow()
        try await waitUntil { abs(ticker.now.timeIntervalSinceNow) < 2 }
        // While running too.
        ticker.resume()
        clock.setFakeNow(target)
        try await waitUntil { abs(ticker.now.timeIntervalSince(target)) < 2 }
        ticker.pause()
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
