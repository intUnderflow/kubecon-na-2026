import XCTest
@testable import KCNA26Core

/// Tests of the helpers extracted from ui/settings/SettingsScreen.kt and FirstRunSheet.kt (no
/// Kotlin test of their own), against the Kotlin expressions they replace.
final class SettingsScreenLogicTests: XCTestCase {
    private let options = SpeakerPicker.options(TestData.repo)

    func testTheSpeakingAsSection() throws {
        let lucy = try XCTUnwrap(SettingsScreenLogic.current(options, "Lucy Sweet"))
        XCTAssertEqual("Lucy Sweet", lucy.name)
        XCTAssertNil(SettingsScreenLogic.current(options, nil))
        XCTAssertNil(SettingsScreenLogic.current(options, "Nobody Here"))
        XCTAssertEqual("None", SettingsScreenLogic.speakingAsName(nil))
        XCTAssertEqual("Lucy Sweet", SettingsScreenLogic.speakingAsName("Lucy Sweet"))
        XCTAssertEqual("No talks are marked as yours, so there are no talk reminders.", SettingsScreenLogic.speakingAsSummary(nil, nil))
        XCTAssertEqual("3 sessions · Wed", SettingsScreenLogic.speakingAsSummary("Lucy Sweet", lucy))
        XCTAssertEqual("Not on the schedule.", SettingsScreenLogic.speakingAsSummary("Nobody Here", nil))
    }

    func testTheListAndItsNoMatchNote() {
        // Settings lists everyone (no pinned default).
        XCTAssertEqual(options, SettingsScreenLogic.shown(options, ""))
        XCTAssertEqual(["Lucy Sweet"], SettingsScreenLogic.shown(options, " lucy swe ").map(\.name))
        let none = SettingsScreenLogic.shown(options, "zzzz")
        XCTAssertTrue(SettingsScreenLogic.showsNoMatch(none, SpeakerPicker.terms("zzzz")))
        XCTAssertFalse(SettingsScreenLogic.showsNoMatch([], [])) // no search: no note
        XCTAssertFalse(SettingsScreenLogic.showsNoMatch(options, SpeakerPicker.terms("lucy")))
        XCTAssertEqual("No speaker matches “zzz”.", SettingsScreenLogic.noMatchText("  zzz "))
        // The first-run sheet shows the note for any empty list.
        XCTAssertTrue(FirstRunSheetLogic.showsNoMatch([]))
        XCTAssertFalse(FirstRunSheetLogic.showsNoMatch(options))
    }

    func testChoosingOnlyWritesAChange() {
        XCTAssertFalse(SettingsScreenLogic.shouldChoose(nil, nil))
        XCTAssertFalse(SettingsScreenLogic.shouldChoose("Lucy Sweet", "Lucy Sweet"))
        XCTAssertTrue(SettingsScreenLogic.shouldChoose("Lucy Sweet", nil))
        XCTAssertTrue(SettingsScreenLogic.shouldChoose(nil, "Lucy Sweet"))
        XCTAssertTrue(SettingsScreenLogic.shouldChoose("Decheng Dai", "Lucy Sweet"))
    }

    func testTheDataRowLabels() {
        XCTAssertEqual("Schedule data", DataSourceText.HEADING)
        XCTAssertEqual("Check now", DataSourceText.CHECK_NOW)
        XCTAssertEqual("Updated Sep 30, 11:59 PM", DataSourceText.updated(TestData.instant("2026-10-01T05:59:00Z"), 1)) // MDT
        XCTAssertEqual("Updated Jan 1, 12:00 AM", DataSourceText.updated(TestData.instant("2027-01-01T07:00:00Z"), 1)) // MST
    }
}
