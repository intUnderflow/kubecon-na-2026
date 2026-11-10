import XCTest
@testable import KCNA26Core

/// Port of ui/settings/SpeakerPickerTest.kt.
@MainActor
final class SpeakerPickerTests: XCTestCase {
    private let repo = TestData.repo
    private let options = SpeakerPicker.options(TestData.repo)

    func testEverySpeakerIsAnOptionWithASummary() throws {
        XCTAssertEqual(repo.allSpeakers, options.map(\.name))
        XCTAssertEqual("3 sessions · Wed", try options.singleMatch { $0.name == "Lucy Sweet" }.summary)
        XCTAssertEqual("2 sessions · Thu", try options.singleMatch { $0.name == "Decheng Dai" }.summary)
        // Co-located speakers are in the picker too.
        XCTAssertEqual("3 sessions · Mon", try options.singleMatch { $0.name == "Katie Lamkin-Fulsher" }.summary)
        XCTAssertEqual("1 session · Mon", try options.singleMatch { $0.name == "Jiazhou Gao" }.summary)
        XCTAssertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("jiazhou"), nil).contains { $0.name == "Jiazhou Gao" })
    }

    func testSearchIgnoresCaseAndAccentsAndPinsTheDefault() {
        let all = SpeakerPicker.filter(options, [], "Lucy Sweet")
        XCTAssertEqual(options.count - 1, all.count)
        XCTAssertFalse(all.contains { $0.name == "Lucy Sweet" })
        XCTAssertEqual(["Lucy Sweet"], SpeakerPicker.filter(options, SpeakerPicker.terms("lucy swe"), "Lucy Sweet").map(\.name))
        XCTAssertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("KREPINSKY"), nil).contains { $0.name == "Filip Křepinský" })
        XCTAssertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("o'leary"), nil).contains { $0.name == "Justin O’Leary" })
        XCTAssertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("zzzz"), nil).isEmpty)
    }

    func testChoosingASpeakerMovesEverythingMine() throws {
        let settings = SettingsStore(InMemoryStore())
        let idx = ScheduleIndex.of(repo)
        let now = try FixedClock.parse("2026-11-10T09:00:00-07:00").now()
        XCTAssertNil(settings.speakingAs) // default: None
        settings.setSpeakingAs("Lucy Sweet")
        XCTAssertEqual("1363905", try XCTUnwrap(idx.banner("wed", now, settings.speakingAs)).next.id)

        settings.setSpeakingAs("Decheng Dai")
        XCTAssertNil(idx.banner("wed", now, settings.speakingAs))
        XCTAssertEqual("1250150", try XCTUnwrap(idx.banner("thu", now, settings.speakingAs)).next.id)
        XCTAssertEqual(["thu"], idx.dayTabs(now, settings.speakingAs).filter(\.hasMine).map(\.key))

        settings.setSpeakingAs(nil)
        XCTAssertNil(settings.speakingAs)
        XCTAssertTrue(!idx.dayTabs(now, settings.speakingAs).contains { $0.hasMine })
        let me = settings.speakingAs
        XCTAssertTrue(!repo.sessions.contains { idx.isMine($0, me) })
    }
}
