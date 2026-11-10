import XCTest
@testable import KCNA26Core

/// How long a cold load of the bundled data takes (debug builds are much slower than release).
/// Prints the timings; fails only if a load is absurdly slow (a performance regression in the
/// JSON parser or decoding).
final class RepositoryLoadTimingTests: XCTestCase {

    func testColdLoadIncludingDetailsIsFast() throws {
        var best = Double.infinity
        var bestCore = Double.infinity
        for _ in 0..<3 {
            let t0 = Date()
            let r = try Repository.fromDirectory(TestData.dataDir)
            let t1 = Date()
            let details = try r.details
            let t2 = Date()
            XCTAssertEqual(562 + 223, details.count)
            bestCore = min(bestCore, t1.timeIntervalSince(t0))
            best = min(best, t2.timeIntervalSince(t0))
        }
        print(String(format: "Repository.fromDirectory: core %.0f ms, with details %.0f ms (best of 3)", bestCore * 1000, best * 1000))
        XCTAssertLessThan(best, 5.0)
    }

    func testParseOnlyTiming() throws {
        let names = [Repository.SCHEDULE, Repository.ROOMS, Repository.WAYFINDING, Repository.VENUE,
                     Repository.SUMMIT_DETAILS, Repository.COLOCATED, Repository.DETAILS, Repository.COLOCATED_DETAILS]
        let blobs = names.map { TestData.data($0) }
        let t0 = Date()
        for b in blobs { _ = try JSON.parse(b) }
        let ms = Date().timeIntervalSince(t0) * 1000
        print(String(format: "JSON.parse of all %d files (%d bytes): %.0f ms", blobs.count, blobs.reduce(0) { $0 + $1.count }, ms))
    }
}
