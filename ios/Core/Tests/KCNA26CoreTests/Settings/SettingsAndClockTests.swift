import XCTest
@testable import KCNA26Core

/// Port of settings/SettingsAndClockTest.kt.
@MainActor
final class SettingsAndClockTests: XCTestCase {

    func testSpeakingAsDefaultsToNoneAndDistinguishesNeverSet() {
        let prefs = InMemoryStore()
        let s = SettingsStore(prefs)
        XCTAssertNil(s.speakingAs)
        XCTAssertFalse(s.isSpeakingAsSet)
        s.setSpeakingAs(nil)
        XCTAssertNil(s.speakingAs)
        XCTAssertTrue(s.isSpeakingAsSet)
        // Survives a restart.
        XCTAssertNil(SettingsStore(prefs).speakingAs)
        s.setSpeakingAs("Graham Helton")
        XCTAssertEqual("Graham Helton", SettingsStore(prefs).speakingAs)
        s.resetSpeakingAs()
        XCTAssertNil(s.speakingAs)
        XCTAssertNil(SettingsStore(prefs).speakingAs)
        XCTAssertFalse(SettingsStore(prefs).isSpeakingAsSet)
    }

    func testDirectionsFromDefaultsToLive() {
        let prefs = InMemoryStore()
        let s = SettingsStore(prefs)
        XCTAssertEqual(SettingsStore.FROM_LIVE, s.directionsFrom)
        s.setDirectionsFrom("EWT")
        XCTAssertEqual("EWT", SettingsStore(prefs).directionsFrom)
    }

    func testFakeNowPersistsAndTicks() throws {
        let prefs = InMemoryStore()
        let c = FakeableClock(prefs, allowFake: true)
        let target = try parseFakeNow("2026-11-11T09:00:00-07:00")
        XCTAssertTrue(c.applyFakeNowArg("2026-11-11T09:00:00-07:00"))
        XCTAssertLessThan(abs(c.now().timeIntervalSince(target)), 2)
        // A new clock (app restart) keeps the offset.
        let c2 = FakeableClock(prefs, allowFake: true)
        XCTAssertLessThan(abs(c2.now().timeIntervalSince(target)), 2)
        // Notification time conversion maps back to real time.
        let real = c2.realEpochMillis(target.plusSeconds(600))
        XCTAssertLessThan(abs(real - (Date().epochMillis + 600_000)), 2_000)
        XCTAssertTrue(c2.applyFakeNowArg("clear"))
        XCTAssertFalse(c2.isFaked)
        XCTAssertLessThan(abs(Date().timeIntervalSince(FakeableClock(prefs, allowFake: true).now())), 2)
        // Release builds ignore it.
        let rel = FakeableClock(prefs, allowFake: false)
        XCTAssertFalse(rel.applyFakeNowArg("2026-11-11T09:00:00-07:00"))
        XCTAssertFalse(rel.isFaked)
        XCTAssertFalse(c2.applyFakeNowArg("not a date"))
    }
}
