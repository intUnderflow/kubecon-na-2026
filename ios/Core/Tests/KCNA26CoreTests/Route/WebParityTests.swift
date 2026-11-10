import Foundation
import XCTest
@testable import KCNA26Core

/// Every route the web version can produce, compared with what the web's own `route` and
/// `lvStartNode` return (golden/web_routes.txt and golden/web_live.txt, written by
/// golden/gen_web_golden.js from reference/schedule.html; see that script for the format).
/// The golden files are read in place from the Android tests (``TestData/androidTestDir``).
///
/// - 43 starts (4 entrances, 39 rooms) × 39 rooms = 1677 routes: step kinds, a CRC of the
///   step texts, polyline length (±0.01 m), point count and levelsChanged.
/// - One deliberate difference: REG and COAT are missing from the web's `R` name table, so
///   starting from them the web says "Start at REG, then …" where the app uses the room
///   name. Neither is in the From picker (no session uses them).
/// - 756 live positions on a 30 m grid around the venue: start node, start key, start text
///   and the live route to a rotating destination.
/// - Another deliberate difference: the app has no Google Maps button, so the outside start
///   ("Head to the {entrance}, about N m {direction} of you.") drops the web's last sentence,
///   "The Google Maps button above walks you there." gen_web_golden.js strips it from the web
///   code before computing the CRCs.
final class WebParityTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var router = Router(repo)

    private func golden(_ name: String) -> [[String]] {
        let url = TestData.androidTestDir.appendingPathComponent("route/golden/\(name)")
        return TestData.lines(url).filter { $0.isNotBlank }.map { $0.components(separatedBy: "|") }
    }

    /// CRC-32 of the texts joined with "\n", as UTF-8 (Kotlin `CRC32` + `"%08x".format`).
    private func crc(_ texts: [String]) -> String { TestData.crc32Hex(texts.joined(separator: "\n")) }

    private func kinds(_ r: Route) -> String { r.steps.map { $0.kind.wire.kotlinTake(1) }.joined() }

    /// Compares a route with golden columns [m, dl, kinds, crc, points]; returns a mismatch description or nil.
    private func mismatch(_ r: Route?, _ g: [String], _ webTexts: ([String]) -> [String] = { $0 }) -> String? {
        guard let r else { return "no route" }
        let m = g[0], dl = g[1], k = g[2], c = g[3], n = g[4]
        if abs(r.totalM - Double(m)!) > 0.01 { return "totalM \(r.totalM) vs \(m)" }
        if r.levelsChanged != Int(dl)! { return "levelsChanged \(r.levelsChanged) vs \(dl)" }
        if kinds(r) != k { return "kinds \(kinds(r)) vs \(k)" }
        if crc(webTexts(r.steps.map(\.text))) != c {
            return "texts differ:\n" + r.steps.map { "  \($0.kind.wire): \($0.text)" }.joined(separator: "\n")
        }
        if r.points.count != Int(n)! { return "points \(r.points.count) vs \(n)" }
        return nil
    }

    /// Rooms the web has no display name for (not in its `R` table).
    private static let WEB_UNNAMED: Set<String> = ["REG", "COAT"]

    func testEveryEntranceAndRoomRouteMatchesTheWeb() {
        let lines = golden("web_routes.txt")
        XCTAssertEqual(lines.count, 43 * 39)
        var errors: [String] = []
        for g in lines {
            let from = g[0], to = g[1]
            let start: RouteFrom = repo.wayfinding.entrances.containsKey(from) ? .entrance(from) : .room(from)
            let r = router.route(start, to)
            let unnamed = Self.WEB_UNNAMED.contains(from) && from != to
            let webTexts: ([String]) -> [String]
            if unnamed {
                let name = repo.room(from)!.name
                webTexts = { texts in [texts[0].replaceFirst("Start at \(name),", "Start at \(from),")] + texts.dropFirst() }
                XCTAssertTrue(r!.steps[0].text.kotlinStartsWith("Start at \(name), then step out to the "))
            } else {
                webTexts = { $0 }
            }
            if let e = mismatch(r, Array(g.dropFirst(2)), webTexts) { errors.append("\(from) → \(to): \(e)") }
        }
        if !errors.isEmpty {
            XCTFail("\(errors.count) routes differ from the web, first: \(errors.prefix(3).joined(separator: "\n"))")
        }
    }

    func testLiveStartsAndRoutesMatchTheWeb() {
        let lines = golden("web_live.txt")
        XCTAssertTrue(lines.count > 700)
        var errors: [String] = []
        for g in lines {
            let x = Double(g[0])!
            let y = Double(g[1])!
            let st = router.myLocationStart(x, y)
            let `where` = "(\(x), \(y))"
            if st.node != g[2] { errors.append("\(`where`) start node \(st.node) vs \(g[2])") }
            if st.key != g[3] { errors.append("\(`where`) start key \(st.key) vs \(g[3])") }
            if crc([st.text]) != g[4] { errors.append("\(`where`) start text: \(st.text)") }
            let r = router.route(.myLocation(x, y, 10.0), g[5])
            if let e = mismatch(r, Array(g.dropFirst(6))) { errors.append("\(`where`) → \(g[5]): \(e)") }
            if let r, !r.live || r.start != st {
                errors.append("\(`where`) → \(g[5]): live \(r.live) start \(String(describing: r.start))")
            }
        }
        if !errors.isEmpty {
            XCTFail("\(errors.count) live mismatches, first: \(errors.prefix(3).joined(separator: "\n"))")
        }
    }
}
