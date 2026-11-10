import XCTest
@testable import KCNA26Core

/// MainActivity's non-UI logic: the debug `-fakeNow` launch argument and the root's error text.
final class MainActivityLogicTests: XCTestCase {

    func testFakeNowLaunchArgumentIsTheValueAfterTheFlag() {
        XCTAssertEqual(
            "2026-11-11T09:00:00-07:00",
            MainActivityLogic.fakeNowArgument(["/app/KCNA26", "-fakeNow", "2026-11-11T09:00:00-07:00"])
        )
        XCTAssertEqual("clear", MainActivityLogic.fakeNowArgument(["/app/KCNA26", "-fakeNow", "clear"]))
        XCTAssertEqual("clear", MainActivityLogic.fakeNowArgument(["/app/KCNA26", "--fakeNow", "clear"]))
        // The last one wins (like UserDefaults' argument domain).
        XCTAssertEqual(
            "2026-11-12T10:00",
            MainActivityLogic.fakeNowArgument(["x", "-fakeNow", "2026-11-11T09:00", "-other", "1", "-fakeNow", "2026-11-12T10:00"])
        )
        XCTAssertEqual("2026-11-11T09:00", MainActivityLogic.fakeNowArgument(["x", "-fakeNow", "2026-11-11T09:00", "-fakeNow"]))
        XCTAssertNil(MainActivityLogic.fakeNowArgument(["/app/KCNA26"]))
        XCTAssertNil(MainActivityLogic.fakeNowArgument(["/app/KCNA26", "-fakeNow"]))
        XCTAssertNil(MainActivityLogic.fakeNowArgument(["/app/KCNA26", "-fakeNowX", "clear", "fakeNow", "clear"]))
        XCTAssertNil(MainActivityLogic.fakeNowArgument([]))
        XCTAssertEqual("-fakeNow", MainActivityLogic.FAKE_NOW_ARGUMENT)
    }

    func testFakeNowAppliesInDebugBuildsOnly() throws {
        let prefs = InMemoryStore()
        let clock = FakeableClock(prefs, allowFake: true)
        let line = try XCTUnwrap(MainActivityLogic.applyFakeNow(["app", "-fakeNow", "2026-11-11T09:00:00-07:00"], to: clock, isDebug: true))
        XCTAssertTrue(line.hasPrefix("fakeNow=2026-11-11T09:00:00-07:00 applied=true now="), line)
        XCTAssertLessThan(abs(clock.now().timeIntervalSince(TestData.instant("2026-11-11T09:00:00-07:00"))), 5)
        XCTAssertTrue(clock.isFaked)
        XCTAssertNotNil(prefs.int64(forKey: FakeableClock.KEY_OFFSET))

        // Denver local time works too; "clear" resets.
        XCTAssertNotNil(MainActivityLogic.applyFakeNow(["app", "-fakeNow", "2026-11-12T13:30"], to: clock, isDebug: true))
        XCTAssertLessThan(abs(clock.now().timeIntervalSince(TestData.instant("2026-11-12T13:30:00-07:00"))), 5)
        let cleared = try XCTUnwrap(MainActivityLogic.applyFakeNow(["app", "-fakeNow", "clear"], to: clock, isDebug: true))
        XCTAssertTrue(cleared.hasPrefix("fakeNow=clear applied=true"), cleared)
        XCTAssertFalse(clock.isFaked)
        XCTAssertNil(prefs.int64(forKey: FakeableClock.KEY_OFFSET))

        // Not a date: not applied, nothing changes.
        let bad = try XCTUnwrap(MainActivityLogic.applyFakeNow(["app", "-fakeNow", "tomorrow"], to: clock, isDebug: true))
        XCTAssertTrue(bad.hasPrefix("fakeNow=tomorrow applied=false"), bad)
        XCTAssertFalse(clock.isFaked)

        // Release builds ignore the argument (and the clock refuses a fake time anyway).
        XCTAssertNil(MainActivityLogic.applyFakeNow(["app", "-fakeNow", "2026-11-11T09:00:00-07:00"], to: clock, isDebug: false))
        XCTAssertFalse(clock.isFaked)
        let release = FakeableClock(InMemoryStore(), allowFake: false)
        let refused = try XCTUnwrap(MainActivityLogic.applyFakeNow(["app", "-fakeNow", "2026-11-11T09:00:00-07:00"], to: release, isDebug: true))
        XCTAssertTrue(refused.hasPrefix("fakeNow=2026-11-11T09:00:00-07:00 applied=false now="), refused)
        XCTAssertFalse(release.isFaked)
        // No argument: nothing to log.
        XCTAssertNil(MainActivityLogic.applyFakeNow(["app"], to: clock, isDebug: true))
    }

    func testLoadErrorTextNamesTheError() {
        let e = DataFileMissingError(name: "schedule.json", location: "/bundle/Data")
        XCTAssertEqual("Couldn’t load the schedule data: DataFileMissingError: \(DataSync.message(e))", MainActivityLogic.loadErrorText(e))
        XCTAssertTrue(MainActivityLogic.loadErrorText(e).hasPrefix("Couldn’t load the schedule data: "))
    }
}
