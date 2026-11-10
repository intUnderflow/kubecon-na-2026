import Foundation
import XCTest
@testable import KCNA26Core

/// Kotlin works in Compose Floats; the Swift port in Doubles (same formulas), so the Kotlin
/// tolerances (0.01, 1e-4, 1e-6) are kept and hold with room to spare.
final class MapFramingTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var router = Router(repo)
    private let pad = MapFraming.PADDING
    private let tol = 0.01

    /// The two Pixel 10 Pro Fold map viewports (dp): cover-screen column and inner-screen left column.
    private let cover = (411.0, 485.0)
    private let inner = (460.0, 760.0)

    private func map(_ p: PointXY) -> MapOffset { MapOffset(MapGeometry.svgX(p.x), MapGeometry.svgY(p.y)) }

    private func assertInPaddedArea(_ cam: MapCamera, _ w: Double, _ h: Double, _ p: MapOffset, _ what: String, line: UInt = #line) {
        let sx = cam.screenX(p.x, w)
        let sy = cam.screenY(p.y, h)
        XCTAssertTrue(sx >= pad.left - tol && sx <= w - pad.right + tol, "\(what) x=\(sx)", line: line)
        XCTAssertTrue(sy >= pad.top - tol && sy <= h - pad.bottom + tol, "\(what) y=\(sy)", line: line)
    }

    func testCameraRoundTrip() {
        let cam = MapCamera(200.0, 300.0, 0.8)
        XCTAssertEqual(205.5, cam.screenX(200.0, 411.0), accuracy: tol)
        XCTAssertEqual(200.0, cam.mapX(cam.screenX(200.0, 411.0), 411.0), accuracy: tol)
        XCTAssertEqual(123.0, cam.mapY(cam.screenY(123.0, 485.0), 485.0), accuracy: tol)
    }

    func testFit_framesTheRouteAndTheDestination() throws {
        let route = try XCTUnwrap(router.route(.entrance("E200S"), "251AC"))
        let points = route.points.map(map)
        let dest = map(try XCTUnwrap(repo.room("251AC")?.pos))
        for (w, h) in [cover, inner] {
            let cam = MapFraming.fit(MapFraming.frameBounds(points, dest, nil), w, h)
            for p in points { assertInPaddedArea(cam, w, h, p, "route point at \(w)x\(h)") }
            assertInPaddedArea(cam, w, h, dest, "destination at \(w)x\(h)")
            // As large as fits: some framed point touches the padded area's edge.
            let xs = (points + [dest]).map { cam.screenX($0.x, w) }
            let ys = (points + [dest]).map { cam.screenY($0.y, h) }
            let touchesX = abs(xs.min()! - pad.left) < 0.5 || abs(xs.max()! - (w - pad.right)) < 0.5
            let touchesY = abs(ys.min()! - pad.top) < 0.5 || abs(ys.max()! - (h - pad.bottom)) < 0.5
            // ...unless the minimum span (140 m across the padded area's smaller side) caps the zoom.
            let cap = min(w - pad.left - pad.right, h - pad.top - pad.bottom) / MapFraming.MIN_SPAN
            let capped = abs(cam.z - cap) < 1e-4
            XCTAssertTrue(touchesX || touchesY || capped, "\(w)x\(h) z=\(cam.z)")
        }
    }

    func testFit_neverZoomsInPastTheMinimumSpan() throws {
        let dest = map(try XCTUnwrap(repo.room("251AC")?.pos))
        let (w, h) = cover
        let cam = MapFraming.fit(MapFraming.frameBounds([], dest, dest.copy(x: dest.x + 3.0)), w, h)
        let aw = w - pad.left - pad.right
        let ah = h - pad.top - pad.bottom
        XCTAssertEqual(min(aw, ah) / MapFraming.MIN_SPAN, cam.z, accuracy: 1e-4)
        assertInPaddedArea(cam, w, h, dest, "destination")
    }

    func testFit_farOutsideTheVenue_fitsMeAndTheDestination() throws {
        let dest = map(try XCTUnwrap(repo.room("251AC")?.pos))
        // Temple Square (a test vector), then 3 km north of the venue.
        let t = TestData.vectors.compass[1]
        let temple = Geo.toLocal(t.lat, t.lng, repo.wayfinding.origin)
        for meLocal in [temple, PointXY(0.0, 3000.0)] {
            let me = map(meLocal)
            let live = try XCTUnwrap(router.route(.myLocation(meLocal.x, meLocal.y, 10.0), "251AC"))
            XCTAssertTrue(live.live)
            let drawn = MapGeometry.staticRoute(live.points, live: true).map(map)
            for (w, h) in [cover, inner] {
                let cam = MapFraming.fit(MapFraming.frameBounds(drawn, dest, me), w, h)
                assertInPaddedArea(cam, w, h, me, "me")
                assertInPaddedArea(cam, w, h, dest, "destination")
            }
        }
    }

    func testFit_neverCropsTheDestinationOrItsLabel_forEveryRouteAndStart() throws {
        let labelW = 34.0 // "L4" pill, dp
        let gap = 16.0
        let starts: [RouteFrom] = router.startEntrances.map { RouteFrom.entrance($0.key) } + [RouteFrom.myLocation(0.0, 3000.0, 10.0)]
        for room in repo.rooms.values.filter({ router.isRoutable($0.code) }) {
            let dest = map(try XCTUnwrap(room.pos))
            for from in starts {
                let r = try XCTUnwrap(router.route(from, room.code))
                var me: MapOffset?
                if case .myLocation(let m) = from { me = map(PointXY(m.x, m.y)) }
                let drawn = MapGeometry.staticRoute(r.points, live: r.live).map(map)
                for (w, h) in [cover, inner, (300.0, 260.0)] {
                    let cam = MapFraming.fit(MapFraming.frameBounds(drawn, dest, me), w, h)
                    let sx = cam.screenX(dest.x, w)
                    let sy = cam.screenY(dest.y, h)
                    let left = MapFraming.labelOnLeft(pinX: sx, width: w, gap: gap, labelWidth: labelW)
                    let l = left ? sx - gap - labelW : sx + gap
                    let what = "\(room.code) from \(from) at \(w)x\(h)"
                    XCTAssertTrue(l >= 0.0 && l + labelW <= w, "\(what) label \(l)")
                    XCTAssertTrue((12.0...(w - 12.0)).contains(sx) && (12.0...(h - 12.0)).contains(sy), "\(what) pin \(sx),\(sy)")
                }
            }
        }
    }

    func testInFrame_meWalkingOutOfFrameTriggersAReframe() {
        let (w, h) = cover
        let cam = MapCamera(256.0, 255.0, 0.8)
        XCTAssertTrue(MapFraming.inFrame(cam, w, h, MapOffset(256.0, 255.0)))
        // The view is 411 / 0.8 ≈ 514 map units wide: 250 units east of centre is near the edge.
        XCTAssertTrue(MapFraming.inFrame(cam, w, h, MapOffset(256.0 + 230.0, 255.0)))
        XCTAssertFalse(MapFraming.inFrame(cam, w, h, MapOffset(256.0 + 250.0, 255.0)))
        XCTAssertFalse(MapFraming.inFrame(cam, w, h, MapOffset(256.0, 255.0 - 400.0)))
    }

    func testKeepInView_pullsTheDestinationBackOnScreen() {
        let (w, h) = cover
        let dest = MapOffset(100.0, 100.0)
        let far = MapCamera(2000.0, 2000.0, 2.0)
        let kept = MapFraming.keepInView(far, w, h, dest)
        XCTAssertEqual(MapFraming.PIN_EDGE, kept.screenX(dest.x, w), accuracy: tol + 1e-3 * w)
        XCTAssertEqual(MapFraming.PIN_EDGE, kept.screenY(dest.y, h), accuracy: tol + 1e-3 * h)
        XCTAssertEqual(far.z, kept.z, accuracy: 0.0)
        // Already in view: unchanged.
        let near = MapCamera(110.0, 90.0, 1.0)
        XCTAssertEqual(near, MapFraming.keepInView(near, w, h, dest))
    }

    func testGesture_zoomsAboutTheFingersAndPans() {
        let (w, h) = cover
        let cam = MapCamera(256.0, 255.0, 1.0)
        let centroid = MapOffset(300.0, 200.0)
        let under = MapOffset(cam.mapX(centroid.x, w), cam.mapY(centroid.y, h))
        let zoomed = MapFraming.gesture(cam, w, h, centroid, .zero, 2.0, 0.1...10.0)
        XCTAssertEqual(2.0, zoomed.z, accuracy: tol)
        XCTAssertEqual(under.x, zoomed.mapX(centroid.x, w), accuracy: tol)
        XCTAssertEqual(under.y, zoomed.mapY(centroid.y, h), accuracy: tol)

        // A 40 dp drag to the right moves the map with the finger.
        let panned = MapFraming.gesture(cam, w, h, MapOffset(240.0, 200.0), MapOffset(40.0, 0.0), 1.0, 0.1...10.0)
        XCTAssertEqual(cam.cx - 40.0, panned.cx, accuracy: tol)
        XCTAssertEqual(cam.cy, panned.cy, accuracy: tol)

        // Zoom is clamped; nonsense zoom factors are ignored.
        XCTAssertEqual(3.0, MapFraming.gesture(cam, w, h, centroid, .zero, 50.0, 0.5...3.0).z, accuracy: tol)
        XCTAssertEqual(1.0, MapFraming.gesture(cam, w, h, centroid, .zero, Double.nan, 0.5...3.0).z, accuracy: tol)
    }

    func testZoomRange_fromHalfTheFitTo30MetresAcross() {
        let (w, h) = cover
        let venueZ = MapFraming.fit(MapFraming.VENUE, w, h).z
        let r = MapFraming.zoomRange(fitZ: 2.0, width: w, height: h)
        XCTAssertEqual(venueZ / 2.0, r.lowerBound, accuracy: 1e-4)
        XCTAssertEqual(min(w, h) / MapFraming.MIN_ZOOM_SPAN, r.upperBound, accuracy: 1e-4)
        // Far away (tiny fit zoom): can zoom out to half of that.
        XCTAssertEqual(0.01, MapFraming.zoomRange(fitZ: 0.02, width: w, height: h).lowerBound, accuracy: 1e-6)
    }

    func testBoundsAndLabelSide() {
        XCTAssertNil(MapFraming.bounds([MapOffset(Double.nan, 1.0)]))
        XCTAssertEqual(MapRect(1.0, 2.0, 5.0, 8.0), MapFraming.bounds([MapOffset(5.0, 2.0), MapOffset(1.0, 8.0)]))
        XCTAssertFalse(MapFraming.labelOnLeft(pinX: 100.0, width: 411.0, gap: 16.0, labelWidth: 34.0))
        XCTAssertTrue(MapFraming.labelOnLeft(pinX: 380.0, width: 411.0, gap: 16.0, labelWidth: 34.0))
    }

    // ---------------------------------------------------------------- iOS additions

    /// Swift ranges can't be empty-by-NaN like Kotlin's: a NaN size gives a safe 1:1 range instead of a trap.
    func testIOS_zoomRangeAndCoerceNeverTrap() {
        XCTAssertEqual(1.0...1.0, MapFraming.zoomRange(fitZ: .nan, width: .nan, height: 485.0))
        XCTAssertEqual(6.0, MapFraming.kotlinCoerceIn(5.0, 6.0, 4.0)) // min > max: Kotlin throws, this never traps
        XCTAssertTrue(MapFraming.kotlinCoerceIn(.nan, 0.0, 1.0).isNaN)
        XCTAssertEqual(0.0, MapFraming.kotlinCoerceIn(-1.0, 0.0, .nan))
        let cam = MapFraming.keepInView(MapCamera(10.0, 10.0, 0.0), 411.0, 485.0, MapOffset(0.0, 0.0))
        XCTAssertEqual(10.0, cam.cx)
        XCTAssertTrue(MapFraming.javaMin(.nan, 1.0).isNaN)
        XCTAssertEqual(-0.0, MapFraming.javaMin(0.0, -0.0))
        XCTAssertEqual(.minus, MapFraming.javaMin(0.0, -0.0).sign)
    }
}
