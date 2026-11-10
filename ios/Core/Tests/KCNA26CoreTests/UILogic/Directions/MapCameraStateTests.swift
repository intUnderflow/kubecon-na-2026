import Foundation
import XCTest
@testable import KCNA26Core

@MainActor
final class MapCameraStateTests: XCTestCase {
    /// Kotlin: `Saver.save` then `Saver.restore` (rememberSaveable across fold/unfold).
    private func roundTrip(_ state: MapCameraState) throws -> MapCameraState {
        let saved = MapCameraState.Saver.save(state)
        return try XCTUnwrap(MapCameraState.Saver.restore(saved))
    }

    private let dest = MapOffset(419.0, 206.0) // 251 A–C

    func testFollowsByDefault_andARestoredFollowingCameraRefitsTheNewScreen() throws {
        let s = MapCameraState(true, nil)
        XCTAssertTrue(s.follow)
        XCTAssertNil(s.camera)
        let r = try roundTrip(s)
        XCTAssertTrue(r.follow)
        XCTAssertNil(r.camera) // re-fitted to whichever screen comes next
    }

    func testAManualCameraSurvivesFoldUnfold() throws {
        let cam = MapCamera(300.0, 250.0, 1.7)
        let r = try roundTrip(MapCameraState(false, cam))
        XCTAssertFalse(r.follow)
        XCTAssertEqual(cam, r.camera)
    }

    func testPinchOrPanSwitchesToManual_keepsTheDestinationOnScreen_andRefitFollowsAgain() throws {
        let s = MapCameraState(false, MapCamera(256.0, 255.0, 1.0))
        s.onGesture(411.0, 485.0, MapOffset(200.0, 200.0), MapOffset(0.0, 0.0), 2.0, [], dest, nil)
        XCTAssertFalse(s.follow)
        XCTAssertEqual(2.0, try XCTUnwrap(s.camera).z, accuracy: 1e-4)
        // A huge drag would push the pin off screen: it stops at the edge instead.
        for _ in 0..<5 { s.onGesture(411.0, 485.0, MapOffset(200.0, 200.0), MapOffset(-2000.0, -2000.0), 1.0, [], dest, nil) }
        let c = try XCTUnwrap(s.camera)
        XCTAssertTrue(MapFraming.inFrame(c, 411.0, 485.0, dest, edge: MapFraming.PIN_EDGE - 0.01))
        s.refit()
        XCTAssertTrue(s.follow)
    }

    func testGestureBeforeTheFirstLayoutIsIgnored() {
        let s = MapCameraState(true, nil)
        s.onGesture(411.0, 485.0, MapOffset(200.0, 200.0), MapOffset(10.0, 0.0), 1.5, [], dest, nil)
        XCTAssertTrue(s.follow)
        XCTAssertNil(s.camera)
    }

    // ---------------------------------------------------------------- iOS additions: frame / animation
    // (Kotlin runs these rules in a coroutine with Compose's animation clock; here they are
    // explicit calls with an injected clock.)

    private final class ManualClock {
        var ms = 1000.0
    }

    private let w = 411.0
    private let h = 485.0
    private let route = [MapOffset(400.0, 447.0), MapOffset(410.0, 300.0), MapOffset(419.0, 206.0)]

    private func fitted(_ me: MapOffset?) -> MapCamera {
        MapFraming.fit(MapFraming.frameBounds(route, dest, me), w, h)
    }

    func testIOS_firstFrameSnaps_thenAResizeSnaps_andARefitAnimates() throws {
        let clock = ManualClock()
        let s = MapCameraState(nowMs: { clock.ms })
        s.frame(w, h, route, dest, nil)
        XCTAssertEqual(fitted(nil), s.camera) // no camera yet: snap
        XCTAssertFalse(s.isAnimating)

        // Restarted for the same size (e.g. a new route): animate from where it is.
        let other = [MapOffset(300.0, 300.0), dest]
        s.frame(w, h, other, dest, nil)
        XCTAssertTrue(s.isAnimating)
        let target = MapFraming.fit(MapFraming.frameBounds(other, dest, nil), w, h)
        XCTAssertEqual(fitted(nil), s.camera) // t = 0: still the old camera
        clock.ms += Double(MapCameraState.FRAME_MS)
        XCTAssertEqual(target, s.camera) // ends exactly on the target

        // A new size snaps.
        s.frame(500.0, 700.0, other, dest, nil)
        XCTAssertFalse(s.isAnimating)
        XCTAssertEqual(MapFraming.fit(MapFraming.frameBounds(other, dest, nil), 500.0, 700.0), s.camera)

        // Refit after a pinch: animated, following again.
        s.onGesture(500.0, 700.0, MapOffset(100.0, 100.0), MapOffset(30.0, 0.0), 1.5, other, dest, nil)
        XCTAssertFalse(s.follow)
        XCTAssertFalse(s.isAnimating)
        s.refit()
        XCTAssertTrue(s.follow)
        XCTAssertTrue(s.isAnimating)
    }

    func testIOS_meWalkingOutOfFrameReframes_insideDoesNot() throws {
        let clock = ManualClock()
        let s = MapCameraState(nowMs: { clock.ms })
        s.frame(w, h, route, dest, nil)
        let cam = try XCTUnwrap(s.camera)
        // Me inside the frame: no change.
        s.updateMe(dest)
        XCTAssertFalse(s.isAnimating)
        XCTAssertEqual(cam, s.camera)
        // Me far away: re-frame (animated) to fit me too.
        let far = MapOffset(dest.x, dest.y - 2000.0)
        s.updateMe(far)
        XCTAssertTrue(s.isAnimating)
        clock.ms += 10_000
        XCTAssertEqual(fitted(far), s.camera)
        // The same position again is not a change.
        s.updateMe(far)
        XCTAssertEqual(fitted(far), s.camera)
    }

    func testIOS_manualCameraStaysPut_andKeepsTheDestinationInView() throws {
        let clock = ManualClock()
        let s = MapCameraState(nowMs: { clock.ms })
        s.frame(w, h, route, dest, nil)
        s.onGesture(w, h, MapOffset(200.0, 200.0), MapOffset(-50.0, 0.0), 1.0, route, dest, nil)
        let manual = try XCTUnwrap(s.camera)
        s.updateMe(MapOffset(dest.x, dest.y - 2000.0)) // walking out of frame does not move a manual camera
        XCTAssertFalse(s.isAnimating)
        XCTAssertEqual(manual, s.camera)
        // A manual camera restored on another screen keeps the pin in view.
        let r = MapCameraState(false, MapCamera(5000.0, 5000.0, 1.0))
        r.frame(w, h, route, dest, nil)
        XCTAssertTrue(MapFraming.inFrame(try XCTUnwrap(r.camera), w, h, dest, edge: MapFraming.PIN_EDGE - 0.01))
    }

    func testIOS_stoppingMidAnimationFreezesTheCamera() throws {
        let clock = ManualClock()
        let s = MapCameraState(nowMs: { clock.ms })
        s.frame(w, h, route, dest, nil)
        let start = try XCTUnwrap(s.camera)
        s.updateMe(MapOffset(dest.x, dest.y - 2000.0))
        clock.ms += Double(MapCameraState.FRAME_MS) / 2
        let mid = try XCTUnwrap(s.camera)
        XCTAssertNotEqual(start, mid)
        s.stopFraming()
        XCTAssertFalse(s.isAnimating)
        clock.ms += 10_000
        XCTAssertEqual(mid, s.camera)
    }

    func testIOS_animationIsEasedWithLogZoom() {
        let a = MapCameraAnimation(from: MapCamera(0.0, 0.0, 1.0), to: MapCamera(100.0, 200.0, 4.0), startMs: 0.0, durationMs: 650.0)
        XCTAssertEqual(MapCamera(0.0, 0.0, 1.0), a.value(atMs: 0.0))
        XCTAssertEqual(MapCamera(100.0, 200.0, 4.0), a.value(atMs: 650.0))
        XCTAssertEqual(MapCamera(100.0, 200.0, 4.0), a.value(atMs: 9999.0))
        let half = a.value(atMs: 325.0)
        let e = MapCameraAnimation.fastOutSlowIn(0.5)
        XCTAssertEqual(100.0 * e, half.cx, accuracy: 1e-9)
        XCTAssertEqual(200.0 * e, half.cy, accuracy: 1e-9)
        XCTAssertEqual(pow(4.0, e), half.z, accuracy: 1e-9) // log scale: 1 → 4 passes 2 at e = 0.5
        // FastOutSlowIn = cubic-bezier(0.4, 0, 0.2, 1): ends fixed, fast start, and its x(t) inverted.
        XCTAssertEqual(0.0, MapCameraAnimation.fastOutSlowIn(0.0))
        XCTAssertEqual(1.0, MapCameraAnimation.fastOutSlowIn(1.0))
        XCTAssertGreaterThan(e, 0.7)
        XCTAssertLessThan(e, 0.85)
        for t in stride(from: 0.0, through: 1.0, by: 0.125) {
            let u = 1 - t
            let x = 3 * u * u * t * 0.4 + 3 * u * t * t * 0.2 + t * t * t
            let y = 3 * u * t * t * 1.0 + t * t * t
            XCTAssertEqual(y, MapCameraAnimation.fastOutSlowIn(x), accuracy: 1e-9, "t=\(t)")
        }
    }

    func testIOS_saverRejectsForeignStrings() {
        XCTAssertNil(MapCameraState.Saver.restore(""))
        XCTAssertNil(MapCameraState.Saver.restore("manual:1,2"))
        XCTAssertNil(MapCameraState.Saver.restore("manual:1,2,x"))
        XCTAssertEqual("follow", MapCameraState.Saver.save(MapCameraState()))
        XCTAssertEqual("manual:0.1,-2.5,1.7", MapCameraState.Saver.save(MapCameraState(false, MapCamera(0.1, -2.5, 1.7))))
    }
}
