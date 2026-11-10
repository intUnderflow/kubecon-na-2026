import Foundation
import XCTest
@testable import KCNA26Core

/// The rotation-vector → heading pipeline, for all four display rotations, against hand-computed
/// expectations. Conventions: device x = right edge, y = top edge, z = out of the screen (natural
/// orientation); world x = east, y = north, z = up. A rotation of the phone flat on a table by yaw
/// α (counter-clockwise seen from above) is the quaternion (0, 0, sin(α/2), cos(α/2)).
final class CompassMathTests: XCTestCase {
    private let tol = 0.01

    /// Quaternion (x, y, z, w) for a rotation of `deg` degrees about the unit `axis` (world frame).
    private func quat(_ axis: [Double], _ deg: Double) -> [Double] {
        let h = deg * Double.pi / 180.0 / 2
        return [axis[0] * sin(h), axis[1] * sin(h), axis[2] * sin(h), cos(h)]
    }

    /// Hamilton product a ⊗ b (apply b first, then a).
    private func mul(_ a: [Double], _ b: [Double]) -> [Double] {
        let (ax, ay, az, aw) = (a[0], a[1], a[2], a[3])
        let (bx, by, bz, bw) = (b[0], b[1], b[2], b[3])
        let x: Double = aw * bx + ax * bw + ay * bz - az * by
        let y: Double = aw * by - ax * bz + ay * bw + az * bx
        let z: Double = aw * bz + ax * by - ay * bx + az * bw
        let w: Double = aw * bw - ax * bx - ay * by - az * bz
        return [x, y, z, w]
    }

    private func rv(_ q: [Double]) -> [Float] { [Float(q[0]), Float(q[1]), Float(q[2]), Float(q[3])] }

    /// Phone flat, screen up, yawed so that the device's top edge points at compass heading `heading`.
    private func flat(_ heading: Double) -> [Float] { rv(quat([0.0, 0.0, 1.0], -heading)) }

    private func assertDeg(_ expected: Double, _ actual: Double?, _ message: String, line: UInt = #line) {
        guard let actual else {
            XCTFail("\(message): nil", line: line)
            return
        }
        let d = Geo.shortestTurn(expected, actual)
        XCTAssertEqual(0.0, d, accuracy: tol, "\(message): expected \(expected) got \(actual)", line: line)
    }

    func testFlatNorthUp_eachRotationReportsTheScreenTop() {
        // Top edge north, right edge east. The screen's "up" is: rot0 top edge (N), rot90 the right
        // edge (E), rot180 the bottom edge (S), rot270 the left edge (W).
        let v = flat(0.0)
        assertDeg(0.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(180.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    func testFlatTopEdgeEast() {
        // Top edge east → right edge south, bottom edge west, left edge north.
        let v = flat(90.0)
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(180.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(0.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    func testFlatTopEdgeNorthEast() {
        let v = flat(45.0)
        assertDeg(45.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(135.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(225.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(315.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    func testTiltedTowardsTheUser_headingUnchanged() {
        // Top edge east, then tilted 40° about the device's x axis (top edge raised), as when
        // holding the phone while walking. Horizontal projections are unchanged.
        let yaw = quat([0.0, 0.0, 1.0], -90.0)
        let pitch = quat([1.0, 0.0, 0.0], 40.0)
        let v = rv(mul(yaw, pitch))
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_0), "rot0")
        assertDeg(180.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_180), "rot180")
        assertDeg(0.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    func testLandscapeHeldUpright_rot90UsesTheRightEdge() {
        // Phone turned 90° counter-clockwise into landscape (right edge up on screen), lying flat,
        // right edge pointing west → the user's screen-up faces west.
        // Right edge (device x) west means top edge (device y) south → flat(180).
        let v = flat(180.0)
        assertDeg(270.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_90), "rot90")
        assertDeg(90.0, CompassMath.azimuthDeg(v, CompassMath.ROTATION_270), "rot270")
    }

    func testThreeAndFiveElementVectors() {
        let q = quat([0.0, 0.0, 1.0], -90.0)
        let three: [Float] = [Float(q[0]), Float(q[1]), Float(q[2])]
        let five: [Float] = [Float(q[0]), Float(q[1]), Float(q[2]), Float(q[3]), 0.1]
        assertDeg(90.0, CompassMath.azimuthDeg(three, CompassMath.ROTATION_0), "w derived")
        assertDeg(90.0, CompassMath.azimuthDeg(five, CompassMath.ROTATION_0), "with accuracy")
        XCTAssertNil(CompassMath.azimuthDeg([0, 0], CompassMath.ROTATION_0))
    }

    func testResultIsInRange() {
        for h in stride(from: 0, to: 360, by: 15) {
            for r in 0...3 {
                let az = CompassMath.azimuthDeg(flat(Double(h)), r)
                XCTAssertNotNil(az, "\(h)/\(r)")
                guard let az else { continue }
                XCTAssertTrue(az >= 0.0 && az < 360.0, "\(h)/\(r) → \(az)")
            }
        }
    }

    func testRemapAxes_matchTheAndroidTable() {
        // SensorManager.AXIS_X = 1, AXIS_Y = 2, AXIS_MINUS_X = 0x81, AXIS_MINUS_Y = 0x82.
        XCTAssertTrue(CompassMath.remapAxes(0) == (1, 2))
        XCTAssertTrue(CompassMath.remapAxes(1) == (2, 0x81))
        XCTAssertTrue(CompassMath.remapAxes(2) == (0x81, 0x82))
        XCTAssertTrue(CompassMath.remapAxes(3) == (0x82, 1))
        XCTAssertTrue(CompassMath.remapAxes(4) == (1, 2))
    }

    func testRemapCoordinateSystem_rot90SwapsColumns() throws {
        // Columns of the output are the new axes: new x = −old y, new y = old x, new z = old z.
        let r: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
        let out = try XCTUnwrap(CompassMath.remapCoordinateSystem(r, 2, 0x81))
        XCTAssertEqual([-2.0, 1.0, 3.0, -5.0, 4.0, 6.0, -8.0, 7.0, 9.0], out)
        XCTAssertNil(CompassMath.remapCoordinateSystem(r, 1, 1))
        XCTAssertNil(CompassMath.remapCoordinateSystem(r, 0, 2))
    }

    func testRotationMatrix_identity() {
        let r = CompassMath.rotationMatrixFromVector([0, 0, 0, 1])
        XCTAssertEqual([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], r)
    }

    func testHeadingSmoother_turnsTheShortWay() {
        let s = HeadingSmoother(0.5)
        XCTAssertEqual(350.0, s.update(350.0), accuracy: tol) // first sample passes through
        XCTAssertEqual(0.0, s.update(10.0), accuracy: tol) // half way along +20°, not via 180°
        XCTAssertEqual(5.0, s.update(10.0), accuracy: tol)
        let noSmoothing = HeadingSmoother(1.0)
        noSmoothing.update(90.0)
        XCTAssertEqual(270.0, noSmoothing.update(270.0), accuracy: tol)
        s.reset()
        XCTAssertNil(s.value)
    }

    func testArrowAccumulator_neverSpinsTheLongWay() {
        // The map's heading cone animates to the accumulator's unbounded value: 350° → 10° is +20°, not −340°.
        let rot = ArrowRotation()
        let a = rot.update(350.0)
        let b = rot.update(10.0)
        XCTAssertEqual(20.0, b - a, accuracy: tol)
        let c = rot.update(190.0)
        XCTAssertTrue(abs(c - b) <= 180.0 + tol)
    }

    func testCalibrationHint() {
        XCTAssertFalse(Calibration.needsHint(nil, nil))
        XCTAssertTrue(Calibration.needsHint(0, 3)) // magnetometer unreliable
        XCTAssertTrue(Calibration.needsHint(1, 3)) // magnetometer low
        XCTAssertTrue(Calibration.needsHint(3, 0)) // rotation vector unreliable
        XCTAssertFalse(Calibration.needsHint(2, 3)) // medium is fine
        XCTAssertFalse(Calibration.needsHint(-1, 3)) // no contact is not a calibration problem
    }

    func testThrottle_atMostOncePerInterval() {
        let t = Throttle(1000)
        XCTAssertTrue(t.ready(0))
        XCTAssertFalse(t.ready(500))
        XCTAssertTrue(t.ready(1000))
        XCTAssertFalse(t.ready(1999))
        XCTAssertTrue(t.ready(2000))
    }

    // ---------------------------------------------------------------- iOS additions (CompassSensor.swift)

    /// `CLHeading.headingAccuracy` → Android sensor status (the figure-8 hint's input on iOS).
    func testIOS_headingAccuracyStatus() {
        XCTAssertEqual(Calibration.UNRELIABLE, CompassSensor.accuracyStatus(headingAccuracy: -1.0)) // invalid reading
        XCTAssertEqual(Calibration.UNRELIABLE, CompassSensor.accuracyStatus(headingAccuracy: .nan))
        XCTAssertEqual(Calibration.LOW, CompassSensor.accuracyStatus(headingAccuracy: 60.0))
        XCTAssertEqual(CompassSensor.MEDIUM, CompassSensor.accuracyStatus(headingAccuracy: 45.0))
        XCTAssertEqual(CompassSensor.MEDIUM, CompassSensor.accuracyStatus(headingAccuracy: 30.0))
        XCTAssertEqual(CompassSensor.HIGH, CompassSensor.accuracyStatus(headingAccuracy: 22.5))
        XCTAssertEqual(CompassSensor.HIGH, CompassSensor.accuracyStatus(headingAccuracy: 0.0))
        XCTAssertTrue(Calibration.needsHint(nil, CompassSensor.accuracyStatus(headingAccuracy: 90.0)))
        XCTAssertFalse(Calibration.needsHint(nil, CompassSensor.accuracyStatus(headingAccuracy: 10.0)))
    }

    /// UIInterfaceOrientation raw values → CLDeviceOrientation raw values for `headingOrientation`.
    func testIOS_headingOrientation() {
        XCTAssertEqual(1, CompassSensor.headingOrientation(interfaceOrientationRawValue: 1)) // portrait
        XCTAssertEqual(2, CompassSensor.headingOrientation(interfaceOrientationRawValue: 2)) // upside down
        XCTAssertEqual(3, CompassSensor.headingOrientation(interfaceOrientationRawValue: 3)) // interface right = device left
        XCTAssertEqual(4, CompassSensor.headingOrientation(interfaceOrientationRawValue: 4)) // interface left = device right
        XCTAssertEqual(1, CompassSensor.headingOrientation(interfaceOrientationRawValue: 0)) // unknown
    }

    /// The debug log's `%.1f`, Java style (HALF_UP on the shortest decimal digits).
    func testIOS_javaFixed1() {
        XCTAssertEqual("80.0", CompassSensor.javaFixed1(80.0))
        XCTAssertEqual("10.4", CompassSensor.javaFixed1(10.4))
        XCTAssertEqual("0.2", CompassSensor.javaFixed1(0.15)) // C's printf: "0.1"
        XCTAssertEqual("0.3", CompassSensor.javaFixed1(0.25)) // C's printf: "0.2" (ties to even)
        XCTAssertEqual("360.0", CompassSensor.javaFixed1(359.96))
        XCTAssertEqual("350.0", CompassSensor.javaFixed1(350.00000000000006))
        XCTAssertEqual("-12.3", CompassSensor.javaFixed1(-12.34))
        XCTAssertEqual("-0.0", CompassSensor.javaFixed1(-0.01))
        XCTAssertEqual("0.0", CompassSensor.javaFixed1(1e-5))
        XCTAssertEqual("0.1", CompassSensor.javaFixed1(0.05))
        XCTAssertEqual("10000000000000000.0", CompassSensor.javaFixed1(1e16))
        XCTAssertEqual("NaN", CompassSensor.javaFixed1(.nan))
        XCTAssertEqual("-Infinity", CompassSensor.javaFixed1(-.infinity))
        XCTAssertEqual("1000", CompassSensor.javaFixed(999.5, 0))
    }
}
