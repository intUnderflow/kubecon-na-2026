import XCTest
@testable import KCNA26Core

/// Port of going/GoingStoreTest.kt.
@MainActor
final class GoingStoreTests: XCTestCase {

    func testStartsEmptyWithTenMinuteReminders() {
        let g = GoingStore(InMemoryStore())
        XCTAssertEqual(Set<String>(), g.ids)
        XCTAssertEqual(10, g.remindMinutes)
        XCTAssertEqual(GoingStore.DEFAULT_REMIND_MINUTES, g.remindMinutes)
        XCTAssertEqual([0, 5, 10, 15], GoingStore.REMIND_OPTIONS)
    }

    func testToggleStarsAndUnstarsAndUpdatesTheFlowAtOnce() {
        let g = GoingStore(InMemoryStore())
        XCTAssertTrue(g.toggle("1251049"))
        XCTAssertTrue(g.isGoing("1251049"))
        XCTAssertEqual(Set(["1251049"]), g.ids)
        XCTAssertTrue(g.toggle("m1318417"))
        XCTAssertEqual(Set(["1251049", "m1318417"]), g.ids)
        XCTAssertFalse(g.toggle("1251049"))
        XCTAssertFalse(g.isGoing("1251049"))
        XCTAssertEqual(Set(["m1318417"]), g.ids)
    }

    func testSetGoingIsIdempotent() {
        let prefs = InMemoryStore()
        let g = GoingStore(prefs)
        g.setGoing("1251049", true)
        g.setGoing("1251049", true)
        XCTAssertEqual(Set(["1251049"]), g.ids)
        g.setGoing("nope", false)
        XCTAssertEqual(Set(["1251049"]), g.ids)
        g.setGoing("1251049", false)
        XCTAssertEqual(Set<String>(), g.ids)
        XCTAssertEqual(Set<String>(), GoingStore(prefs).ids)
    }

    func testStarsAndTheReminderTimeSurviveARestart() {
        let prefs = InMemoryStore()
        let g = GoingStore(prefs)
        g.toggle("1251049")
        g.toggle("1251218")
        g.setRemindMinutes(15)
        let again = GoingStore(prefs)
        XCTAssertEqual(Set(["1251049", "1251218"]), again.ids)
        XCTAssertEqual(15, again.remindMinutes)
        g.setRemindMinutes(GoingStore.REMIND_OFF)
        XCTAssertEqual(0, GoingStore(prefs).remindMinutes)
    }

    func testUnknownIdsAreKeptSoTheyComeBackWithTheData() {
        let prefs = InMemoryStore()
        let g = GoingStore(prefs)
        g.toggle("gone-from-the-data")
        g.toggle("1251049")
        XCTAssertEqual(Set(["gone-from-the-data", "1251049"]), GoingStore(prefs).ids)
    }

    func testOnlyTheOfferedReminderTimesAreAccepted() {
        let prefs = InMemoryStore()
        let g = GoingStore(prefs)
        g.setRemindMinutes(7)
        XCTAssertEqual(10, g.remindMinutes)
        g.setRemindMinutes(5)
        XCTAssertEqual(5, g.remindMinutes)
        // A bad stored value falls back to the default.
        prefs.set(42, forKey: "remindMinutes")
        XCTAssertEqual(10, GoingStore(prefs).remindMinutes)
    }

    func testTheStoredSetIsACopy() throws {
        let prefs = InMemoryStore()
        let g = GoingStore(prefs)
        g.toggle("a")
        let stored = try XCTUnwrap(prefs.stringSet(forKey: "ids"))
        g.toggle("b")
        XCTAssertEqual(Set(["a"]), stored)
        XCTAssertEqual(Set(["a", "b"]), prefs.stringSet(forKey: "ids"))
    }
}
