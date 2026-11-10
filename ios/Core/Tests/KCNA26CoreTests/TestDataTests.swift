import XCTest
@testable import KCNA26Core

/// The shared fixtures themselves (paths, typed test vectors, the bundled data copies).
final class TestDataTests: XCTestCase {

    func testPathsExist() {
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: TestData.dataDir.appendingPathComponent(Repository.SCHEDULE).path))
        XCTAssertTrue(fm.fileExists(atPath: TestData.publishedDataDir.appendingPathComponent(Repository.TEST_VECTORS).path))
        XCTAssertTrue(fm.fileExists(atPath: TestData.androidTestDir.appendingPathComponent("route/golden/web_routes.txt").path))
        XCTAssertEqual(TestData.assetsDir, TestData.dataDir)
        // test_vectors.json is not bundled in the app, so TestData falls back to data/.
        XCTAssertFalse(fm.fileExists(atPath: TestData.dataDir.appendingPathComponent(Repository.TEST_VECTORS).path))
        XCTAssertEqual(TestData.url(Repository.TEST_VECTORS).deletingLastPathComponent().lastPathComponent, "data")
    }

    func testVectorsAreTyped() {
        let v = TestData.vectors
        XCTAssertFalse(v.routes.isEmpty)
        XCTAssertFalse(v.compass.isEmpty)
        XCTAssertFalse(v.arrowRotation.isEmpty)
        XCTAssertTrue(v.routes.allSatisfy { !$0.steps.isEmpty && $0.totalM > 0 })
        XCTAssertTrue(v.compass.allSatisfy { ["inside", "outside"].contains($0.myLocationStart.mode) })
    }

    func testBundledDataIsTheSameAsThePublishedAndAndroidCopies() {
        for name in [Repository.SCHEDULE, Repository.ROOMS, Repository.WAYFINDING, Repository.VENUE, Repository.DETAILS,
                     Repository.SUMMIT_DETAILS, Repository.COLOCATED, Repository.COLOCATED_DETAILS, "manifest.json"] {
            let bundled = TestData.data(name)
            XCTAssertEqual(bundled, try? Data(contentsOf: TestData.publishedDataDir.appendingPathComponent(name)), name)
            XCTAssertEqual(bundled, try? Data(contentsOf: TestData.androidAssetsDir.appendingPathComponent(name)), name)
        }
    }

    func testClockAndInstantHelpers() {
        XCTAssertEqual(TestData.clockAt("2026-11-11T09:00:00-07:00").now(), TestData.instant("2026-11-11T16:00:00Z"))
        XCTAssertEqual(TestData.clockAt("2026-11-11T09:00").now(), TestData.instant("2026-11-11T09:00:00-07:00"))
        XCTAssertGreaterThan(TestData.lines(TestData.androidTestDir.appendingPathComponent("route/golden/web_routes.txt")).count, 1)
    }
}
