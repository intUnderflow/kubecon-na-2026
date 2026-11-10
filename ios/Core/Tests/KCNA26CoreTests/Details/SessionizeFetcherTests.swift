import XCTest
@testable import KCNA26Core

final class SessionizeFetcherTests: XCTestCase {

    func testClassifiesResponses() {
        let md = "# T\n\n## Description\n\nHi"
        XCTAssertEqual(FetchResult.ok(md), SessionizeFetcher.classify(200, "text/plain; charset=utf-8", md))
        XCTAssertEqual(FetchResult.notFound, SessionizeFetcher.classify(404, "text/html; charset=utf-8", "<!DOCTYPE html>"))
        XCTAssertEqual(FetchResult.notFound, SessionizeFetcher.classify(410, nil, ""))
        XCTAssertTrue(SessionizeFetcher.classify(500, "text/plain", "").isFailed)
        XCTAssertTrue(SessionizeFetcher.classify(429, "text/plain", "").isFailed)
        // A hotel Wi-Fi login page is a failure (retry later), not "no description".
        XCTAssertTrue(SessionizeFetcher.classify(200, "text/html", "<html><body>Sign in</body></html>").isFailed)
        XCTAssertTrue(SessionizeFetcher.classify(200, nil, "  <!doctype html><html>").isFailed)
    }

    func testUsesTheSessionizeEndpointAndAPoliteUserAgent() {
        XCTAssertEqual("https://sessionize.com/api/v2/uo948i5p/view/markdown/session/", SessionizeFetcher.URL_PREFIX)
        XCTAssertTrue(SessionizeFetcher.USER_AGENT.hasPrefix("kubecon-schedule-app/1.0 (personal schedule app"))
    }

    func testRefusesNonKubeConIdsWithoutNetwork() async {
        let r1 = await SessionizeFetcher().fetch("m1318474")
        XCTAssertEqual(FetchResult.notFound, r1)
        let r2 = await SessionizeFetcher().fetch("../x")
        XCTAssertEqual(FetchResult.notFound, r2)
    }
}
