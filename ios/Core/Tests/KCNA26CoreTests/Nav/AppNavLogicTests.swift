import XCTest
@testable import KCNA26Core

/// The navigation rules of nav/AppNav.kt (no Kotlin unit test covers them).
final class AppNavLogicTests: XCTestCase {
    private let repo = TestData.repo

    func testListPaneIs47PercentWithin360To480() {
        XCTAssertEqual(360, AppNavLogic.listPaneWidth(600))
        XCTAssertEqual(360, AppNavLogic.listPaneWidth(700)) // 329
        XCTAssertEqual(Double(Float(900) * Float(0.47)), AppNavLogic.listPaneWidth(900), accuracy: 0)
        XCTAssertEqual(423, AppNavLogic.listPaneWidth(900), accuracy: 0.001)
        XCTAssertEqual(480, AppNavLogic.listPaneWidth(1024)) // 481.28
        XCTAssertEqual(480, AppNavLogic.listPaneWidth(1366))
    }

    func testAStaleOpenSessionIsDropped() {
        XCTAssertEqual("1249844", AppNavLogic.shownSession("1249844", repo))
        XCTAssertFalse(AppNavLogic.dropsStaleSession("1249844", repo))
        XCTAssertNil(AppNavLogic.shownSession("999999999", repo))
        XCTAssertTrue(AppNavLogic.dropsStaleSession("999999999", repo))
        XCTAssertNil(AppNavLogic.shownSession(nil, repo))
        XCTAssertFalse(AppNavLogic.dropsStaleSession(nil, repo))
    }

    func testDetailsAreASheetOnCompactAndAPaneOnWide() {
        XCTAssertEqual(.sheet("1249844"), AppNavLogic.detailsPlacement(wide: false, shownSession: "1249844"))
        XCTAssertEqual(.nothing, AppNavLogic.detailsPlacement(wide: false, shownSession: nil))
        XCTAssertEqual(.pane("1249844"), AppNavLogic.detailsPlacement(wide: true, shownSession: "1249844"))
        XCTAssertEqual(.emptyHint, AppNavLogic.detailsPlacement(wide: true, shownSession: nil))
        XCTAssertEqual("Pick a session", AppNavLogic.EMPTY_DETAILS_TITLE)
        XCTAssertEqual("Its details, speakers and directions show up here.", AppNavLogic.EMPTY_DETAILS_TEXT)
    }

    func testBackPopsScreensAndClosesTheWidePane() {
        XCTAssertEqual(.pop, AppNavLogic.backAction(stackCount: 2, top: .directions("1"), wide: false, shownSession: "1"))
        XCTAssertEqual(.pop, AppNavLogic.backAction(stackCount: 2, top: .settings, wide: true, shownSession: "1"))
        XCTAssertEqual(.closeSession, AppNavLogic.backAction(stackCount: 1, top: .schedule, wide: true, shownSession: "1"))
        // Compact: the sheet handles back itself.
        XCTAssertEqual(.nothing, AppNavLogic.backAction(stackCount: 1, top: .schedule, wide: false, shownSession: "1"))
        XCTAssertEqual(.nothing, AppNavLogic.backAction(stackCount: 1, top: .schedule, wide: true, shownSession: nil))
    }
}
