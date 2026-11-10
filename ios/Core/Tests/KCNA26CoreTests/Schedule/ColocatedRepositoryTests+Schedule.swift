import XCTest
@testable import KCNA26Core

/// The ScheduleIndex half of data/ColocatedRepositoryTest.kt
/// `theScheduleStillLoadsWithoutColocatedJson` (Kotlin lines 230-236); the foundation's
/// ColocatedRepositoryTests ports the repository half.
extension ColocatedRepositoryTests {
    func testTheScheduleStillLoadsWithoutColocatedJsonDayView() throws {
        for text in Self.colocatedJsonFailures() {
            let r = try Self.loadWith(text)
            // Monday is as it was before the co-located cards: the All-Access events are back in the
            // "Co-located + off-site" section at the top of the day, not labelled sponsor-hosted.
            let mon = try XCTUnwrap(ScheduleIndex(r).dayView("mon", TestData.instant("2026-11-09T08:00:00-07:00"), "Lucy Sweet"))
            XCTAssertTrue(mon.colo.isEmpty)
            XCTAssertEqual("Co-located + off-site", mon.longsTitle)
            XCTAssertTrue(mon.longsFirst)
            XCTAssertEqual(11, mon.longs.filter { $0.session.note == "All-Access pass" }.count)
        }
    }
}
