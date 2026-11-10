import XCTest
@testable import KCNA26Core

/// Port of ui/settings/DataSourceTextTest.kt.
final class DataSourceTextTests: XCTestCase {
    private let now = TestData.instant("2026-11-08T18:30:00Z") // 11:30 AM in Denver

    func testUpdatedLineIsDenverTime() {
        XCTAssertEqual("Updated Nov 8, 2:15 PM", DataSourceText.updated(TestData.instant("2026-11-08T21:15:00Z"), 3))
        XCTAssertEqual("Version 3", DataSourceText.updated(nil, 3))
    }

    func testSourceLineNeverShowsErrors() {
        let b = ActiveData.Source.bundled
        XCTAssertEqual("Bundled with the app", DataSourceText.source(b, SyncStatus(), now))
        XCTAssertEqual("Bundled with the app · Checking…", DataSourceText.source(b, SyncStatus(checking: true), now))
        XCTAssertEqual("Bundled with the app · Up to date", DataSourceText.source(b, SyncStatus(last: .notModified), now))
        XCTAssertEqual("Bundled with the app", DataSourceText.source(b, SyncStatus(last: .failed("HTTP 404")), now))
        XCTAssertEqual("Bundled with the app", DataSourceText.source(b, SyncStatus(last: .rejected("bad")), now))
    }

    func testJustNowOnlyRightAfterTheDownload() {
        let g = ActiveData.Source.github
        func downloaded(_ at: String) -> SyncStatus { SyncStatus(last: .updated(2), lastCheckedAt: TestData.instant(at)) }
        XCTAssertEqual("From GitHub · Downloaded just now", DataSourceText.source(g, downloaded("2026-11-08T18:29:00Z"), now))
        // Opened Settings hours later in the same process: say when.
        XCTAssertEqual("From GitHub · Downloaded at 9:00 AM", DataSourceText.source(g, downloaded("2026-11-08T16:00:00Z"), now))
        XCTAssertEqual("From GitHub · Downloaded Nov 7, 9:00 AM", DataSourceText.source(g, downloaded("2026-11-07T16:00:00Z"), now))
    }
}
