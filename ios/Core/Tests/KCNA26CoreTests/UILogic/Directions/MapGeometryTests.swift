import Foundation
import XCTest
@testable import KCNA26Core

final class MapGeometryTests: XCTestCase {
    func testViewBoxTransform() {
        XCTAssertEqual(492.0, MapGeometry.svgX(0.0))
        XCTAssertEqual(492.0, MapGeometry.svgY(0.0))
        // 251 A–C at (−73, 286) → (419, 206).
        XCTAssertEqual(419.0, MapGeometry.svgX(-73.0))
        XCTAssertEqual(206.0, MapGeometry.svgY(286.0))
    }

    func testAccuracyCircleClamped8To250() {
        XCTAssertEqual(8.0, MapGeometry.accuracyRadius(3.0))
        XCTAssertEqual(12.0, MapGeometry.accuracyRadius(12.0))
        XCTAssertEqual(250.0, MapGeometry.accuracyRadius(400.0))
    }

    func testLevelText() {
        XCTAssertEqual("L2", MapGeometry.levelText(2))
        XCTAssertEqual("L4", MapGeometry.levelText(4))
    }

    func testZoneLabelsMatchTheWeb() throws {
        let zones = TestData.repo.venue.zones.associateBy { $0.name }
        func check(_ name: String, _ text: String, _ x: Double, _ y: Double, line: UInt = #line) throws {
            let l = MapGeometry.zoneLabel(try XCTUnwrap(zones[name], name, line: line))
            XCTAssertEqual(text, l.text, line: line)
            XCTAssertEqual(x, l.x, line: line)
            XCTAssertEqual(y, l.y, line: line)
        }
        try check("Hall DE", "Hall DE", 310.0, 352.0)
        try check("Halls A–C", "Halls A–C", 310.0, 206.0)
        try check("Halls 1–5", "Halls 1–5", 37.0, 107.0)
        try check("Grand Ballroom", "Ballroom", 412.0, 302.0)
        try check("Rooms 155 / 255", "155·255", 282.0, 42.0)
        XCTAssertEqual(5, zones.count)
    }

    func testStreetAndHyattLabels() {
        let names = MapGeometry.streetLabels.map(\.text)
        XCTAssertEqual(["West Temple", "200 South", "100 South", "South Temple", "200 West", "300 W"], names)
        XCTAssertEqual(90.0, MapGeometry.streetLabels.first?.rotateDeg)
        XCTAssertEqual(414.0, MapGeometry.hyattLabel.x)
        XCTAssertEqual(462.0, MapGeometry.hyattLabel.y)
    }

    func testStaticRouteDropsTheLivePoint() {
        let pts = [PointXY(0.0, 0.0), PointXY(1.0, 1.0), PointXY(2.0, 2.0)]
        XCTAssertEqual(pts, MapGeometry.staticRoute(pts, live: false))
        XCTAssertEqual(Array(pts.dropFirst()), MapGeometry.staticRoute(pts, live: true))
    }

    // ---------------------------------------------------------------- iOS additions (SvgPath.swift)

    /// The web's path data as absolute commands for SwiftUI `Path` (Kotlin: Compose `PathParser`).
    func testIOS_svgPathLinesAndRelativeCommands() {
        let m = { (x: Double, y: Double) in MapOffset(x, y) }
        XCTAssertEqual(
            [.move(m(5, 12)), .line(m(17, 12)), .move(m(13, 7)), .line(m(18, 12)), .line(m(13, 17))],
            SvgPath.parse(MapGeometry.ICON_WALK)
        )
        XCTAssertEqual(
            [.move(m(4, 19)), .line(m(9, 19)), .line(m(16, 7)), .line(m(20, 7)), .move(m(15, 7)), .line(m(20, 7)), .line(m(20, 12))],
            SvgPath.parse(MapGeometry.ICON_UP)
        )
        XCTAssertEqual(
            [.move(m(4, 7)), .line(m(9, 7)), .line(m(16, 19)), .line(m(20, 19)), .move(m(15, 19)), .line(m(20, 19)), .line(m(20, 14))],
            SvgPath.parse(MapGeometry.ICON_DOWN)
        )
        // Compact numbers: "M0-12 5 4 0 1-5 4z" is a move then three line-tos.
        XCTAssertEqual(
            [.move(m(0, -12)), .line(m(5, 4)), .line(m(0, 1)), .line(m(-5, 4)), .close],
            SvgPath.parse(MapGeometry.ROSE_PATH)
        )
        XCTAssertEqual([.move(m(0.5, 0.5)), .line(m(-1e-3, 2))], SvgPath.parse("M.5.5L-1e-3,2"))
        // Malformed tail: the commands before it are kept.
        XCTAssertEqual([.move(m(1, 2)), .line(m(3, 4))], SvgPath.parse("M1 2 3 4 5"))
        XCTAssertEqual([], SvgPath.parse("12 3"))
    }

    func testIOS_svgPathCurvesAndArcs() throws {
        // The heading cone: two lines and a radius-32 arc over the top, closed.
        let cone = SvgPath.parse(MapGeometry.CONE_PATH)
        XCTAssertEqual(.move(MapOffset(0, 0)), cone.first)
        XCTAssertEqual(.line(MapOffset(-11, -30)), cone[1])
        XCTAssertEqual(.close, cone.last)
        let arcs = cone.dropFirst(2).dropLast()
        XCTAssertFalse(arcs.isEmpty)
        guard case .cubic(let c1, let c2, let end) = try XCTUnwrap(arcs.last) else { return XCTFail("not a cubic") }
        XCTAssertEqual(MapOffset(11, -30), end)
        // Small arc, clockwise on screen (sweep 1): it bulges up (y < −30), not down through "me".
        XCTAssertLessThan(c1.y, -30)
        XCTAssertLessThan(c2.y, -30)
        // The arc's centre is below the chord y = −30 (small arc): (0, −30 + √(32² − 11²)).
        let cy = -30.0 + (32.0 * 32.0 - 11.0 * 11.0).squareRoot()
        for c in arcs {
            guard case .cubic(_, _, let p) = c else { return XCTFail("not a cubic") }
            XCTAssertEqual(32.0, (p.x * p.x + (p.y - cy) * (p.y - cy)).squareRoot(), accuracy: 1e-9)
        }

        // The end pin: s (reflected control = current point), a semicircle, c, z.
        let pin = SvgPath.parse(MapGeometry.ICON_END)
        XCTAssertEqual(.move(MapOffset(12, 21)), pin[0])
        XCTAssertEqual(.cubic(MapOffset(12, 21), MapOffset(6, 15.4), MapOffset(6, 11)), pin[1])
        guard case .cubic(_, _, let top) = pin[2] else { return XCTFail("not a cubic") }
        XCTAssertEqual(12.0, top.x, accuracy: 1e-9) // first 90° of the semicircle ends at its top
        XCTAssertEqual(5.0, top.y, accuracy: 1e-9)
        XCTAssertEqual(.cubic(MapOffset(18, 15.4), MapOffset(12, 21), MapOffset(12, 21)), pin[pin.count - 2])
        XCTAssertEqual(.close, pin.last)

        // Quadratics become cubics (2/3 rule); T reflects.
        XCTAssertEqual(
            [.move(MapOffset(0, 0)), .cubic(MapOffset(2, 4), MapOffset(4, 4), MapOffset(6, 0)), .cubic(MapOffset(8, -4), MapOffset(10, -4), MapOffset(12, 0))],
            SvgPath.parse("M0 0Q3 6 6 0T12 0")
        )
        // Degenerate arcs: zero radius → line; same end point → nothing.
        XCTAssertEqual([.move(MapOffset(0, 0)), .line(MapOffset(5, 5))], SvgPath.parse("M0 0A0 3 0 0 1 5 5"))
        XCTAssertEqual([.move(MapOffset(1, 1))], SvgPath.parse("M1 1A3 3 0 1 1 1 1"))
        // Flags without separators.
        XCTAssertEqual(SvgPath.parse("M0 0A5 5 0 1 1 10 0"), SvgPath.parse("M0 0A5 5 0 1110 0"))
    }
}
