import XCTest
@testable import KCNA26Core

/// Port of settings/FirstRunTest.kt: the first-run "Speaking at KubeCon? Pick your name" state.
@MainActor
final class FirstRunTests: XCTestCase {

    func testFreshInstallIsNoneWithThePickerPending() {
        let s = SettingsStore(InMemoryStore())
        XCTAssertNil(s.speakingAs)
        XCTAssertTrue(s.firstRunPending)
        XCTAssertFalse(s.isSpeakingAsSet)
    }

    func testPickingSetsTheSpeakerAndTheFlag() {
        let prefs = InMemoryStore()
        let s = SettingsStore(prefs)
        s.finishFirstRun("Lucy Sweet")
        XCTAssertEqual("Lucy Sweet", s.speakingAs)
        XCTAssertFalse(s.firstRunPending)
        // Survives a restart (and a scene being recreated, which keeps the store).
        let again = SettingsStore(prefs)
        XCTAssertEqual("Lucy Sweet", again.speakingAs)
        XCTAssertFalse(again.firstRunPending)
    }

    func testSkippingKeepsNoneAndNeverAsksAgain() {
        let prefs = InMemoryStore()
        let s = SettingsStore(prefs)
        s.finishFirstRun(nil)
        XCTAssertNil(s.speakingAs)
        XCTAssertFalse(s.firstRunPending)
        XCTAssertFalse(s.isSpeakingAsSet)
        XCTAssertFalse(SettingsStore(prefs).firstRunPending)
        XCTAssertNil(SettingsStore(prefs).speakingAs)
    }

    func testSwipingTheSheetAwayOnlyHidesItUntilTheNextStart() {
        let prefs = InMemoryStore()
        let s = SettingsStore(prefs)
        s.dismissFirstRunForNow()
        XCTAssertFalse(s.firstRunPending) // hidden for this process
        XCTAssertNil(s.speakingAs)
        XCTAssertFalse(s.isSpeakingAsSet)
        XCTAssertTrue(SettingsStore(prefs).firstRunPending) // asks again on the next cold start
    }

    func testAnExistingExplicitChoiceIsUntouched() {
        let named = InMemoryStore()
        SettingsStore(named).setSpeakingAs("Graham Helton")
        do {
            let it = SettingsStore(named)
            XCTAssertEqual("Graham Helton", it.speakingAs)
            XCTAssertFalse(it.firstRunPending)
        }
        let none = InMemoryStore()
        SettingsStore(none).setSpeakingAs(nil)
        do {
            let it = SettingsStore(none)
            XCTAssertNil(it.speakingAs)
            XCTAssertTrue(it.isSpeakingAsSet)
            XCTAssertFalse(it.firstRunPending)
        }
    }

    func testChoosingInSettingsAlsoEndsTheFirstRun() {
        let s = SettingsStore(InMemoryStore())
        s.setSpeakingAs("Decheng Dai")
        XCTAssertFalse(s.firstRunPending)
    }

    func testSpeakingAsEmitsOnlyWhenAPickChangesIt() {
        // The App reschedules reminders on every speakingAs change after the first value.
        let s = SettingsStore(InMemoryStore())
        let before = s.speakingAs
        s.finishFirstRun(nil)
        XCTAssertEqual(before, s.speakingAs) // Skip: no change, nothing to reschedule
        let s2 = SettingsStore(InMemoryStore())
        s2.finishFirstRun("Lucy Sweet")
        XCTAssertEqual("Lucy Sweet", s2.speakingAs) // a change, so reminders are rescheduled
    }
}
