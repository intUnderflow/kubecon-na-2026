import Foundation

/// Pure compass maths, so it can be unit-tested (Kotlin: android.hardware.SensorManager's
/// static helpers are stubs on the JVM). These are line-for-line ports of AOSP
/// `SensorManager.getRotationMatrixFromVector`, `remapCoordinateSystem` and `getOrientation`.
///
/// iOS: the app does not use this pipeline. Core Location computes the heading itself and
/// compensates for the interface orientation through `CLLocationManager.headingOrientation`
/// (see ``CompassSensor`` and "Heading on iOS" in ``Geo``). It is kept, tested, for parity
/// and for anyone feeding raw rotation-vector data (e.g. from Core Motion).
///
/// Coordinate frames:
/// - Device frame: x to the right edge of the panel's natural orientation, y to its top edge, z out of the screen.
/// - World frame: x east, y north, z up.
/// - A rotation matrix R (row-major 3×3) maps device vectors to world vectors; its columns are the
///   device axes expressed in world coordinates.
///
/// Kotlin -> Swift: `FloatArray` -> `[Float]`, `DoubleArray` -> `[Double]`, `Pair<Int, Int>` ->
/// `(Int, Int)`. `atan2` is Java's (``Geo/javaAtan2(_:_:)``, fdlibm), so azimuths are
/// bit-identical to Android's.
enum CompassMath {
    /// android.view.Surface.ROTATION_* values, as returned by Display.getRotation().
    static let ROTATION_0 = 0
    static let ROTATION_90 = 1
    static let ROTATION_180 = 2
    static let ROTATION_270 = 3

    // SensorManager.AXIS_* values.
    private static let AXIS_X = 1
    private static let AXIS_Y = 2
    private static let AXIS_MINUS_X = AXIS_X | 0x80
    private static let AXIS_MINUS_Y = AXIS_Y | 0x80

    /// Magnetic heading in degrees [0, 360) of "the top of the phone as the user sees the screen",
    /// from TYPE_ROTATION_VECTOR `values` (x, y, z[, w[, accuracy]]) and the rotation of the display
    /// the activity is on (`displayRotation`, Surface.ROTATION_*). Nil for malformed input.
    ///
    /// Pipeline (as on Android): getRotationMatrixFromVector → remapCoordinateSystem for the display
    /// rotation → getOrientation → azimuth.
    static func azimuthDeg(_ values: [Float], _ displayRotation: Int) -> Double? {
        if values.count < 3 { return nil }
        let r = rotationMatrixFromVector(values)
        let out = remapForDisplay(r, displayRotation)
        let az = orientation(out)[0]
        if az.isNaN { return nil }
        return Geo.norm360(Geo.toDegrees(az))
    }

    /// (X, Y) axis pair for SensorManager.remapCoordinateSystem, per display rotation.
    static func remapAxes(_ displayRotation: Int) -> (Int, Int) {
        switch ((displayRotation % 4) + 4) % 4 {
        case ROTATION_90: return (AXIS_Y, AXIS_MINUS_X)
        case ROTATION_180: return (AXIS_MINUS_X, AXIS_MINUS_Y)
        case ROTATION_270: return (AXIS_MINUS_Y, AXIS_X)
        default: return (AXIS_X, AXIS_Y)
        }
    }

    /// Remaps `r` so that its y axis is "up" on the screen for `displayRotation`.
    static func remapForDisplay(_ r: [Double], _ displayRotation: Int) -> [Double] {
        let (x, y) = remapAxes(displayRotation)
        return remapCoordinateSystem(r, x, y) ?? r
    }

    /// Port of SensorManager.getRotationMatrixFromVector for a 3×3 (9-element) matrix.
    /// `rv` must have at least 3 elements (Kotlin throws otherwise; this traps).
    static func rotationMatrixFromVector(_ rv: [Float]) -> [Double] {
        let q1 = Double(rv[0])
        let q2 = Double(rv[1])
        let q3 = Double(rv[2])
        let q0: Double
        if rv.count >= 4 {
            q0 = Double(rv[3])
        } else {
            let w: Double = 1 - q1 * q1 - q2 * q2 - q3 * q3
            q0 = w > 0 ? w.squareRoot() : 0.0
        }
        let sqQ1 = 2 * q1 * q1
        let sqQ2 = 2 * q2 * q2
        let sqQ3 = 2 * q3 * q3
        let q1q2 = 2 * q1 * q2
        let q3q0 = 2 * q3 * q0
        let q1q3 = 2 * q1 * q3
        let q2q0 = 2 * q2 * q0
        let q2q3 = 2 * q2 * q3
        let q1q0 = 2 * q1 * q0
        let r0: Double = 1 - sqQ2 - sqQ3
        let r4: Double = 1 - sqQ1 - sqQ3
        let r8: Double = 1 - sqQ1 - sqQ2
        return [
            r0, q1q2 - q3q0, q1q3 + q2q0,
            q1q2 + q3q0, r4, q2q3 - q1q0,
            q1q3 - q2q0, q2q3 + q1q0, r8,
        ]
    }

    /// Port of SensorManager.remapCoordinateSystem (3×3). Nil for an invalid axis pair.
    static func remapCoordinateSystem(_ inR: [Double], _ axisX: Int, _ axisY: Int) -> [Double]? {
        if (axisX & 0x7C) != 0 || (axisY & 0x7C) != 0 { return nil }
        if (axisX & 0x3) == 0 || (axisY & 0x3) == 0 { return nil }
        if (axisX & 0x3) == (axisY & 0x3) { return nil }
        var axisZ = axisX ^ axisY
        let x = (axisX & 0x3) - 1
        let y = (axisY & 0x3) - 1
        let z = (axisZ & 0x3) - 1
        let axisYi = (z + 1) % 3
        let axisZi = (z + 2) % 3
        if ((x ^ axisYi) | (y ^ axisZi)) != 0 { axisZ ^= 0x80 }
        let sx = axisX >= 0x80
        let sy = axisY >= 0x80
        let sz = axisZ >= 0x80
        var out = [Double](repeating: 0.0, count: 9)
        for j in 0..<3 {
            let offset = j * 3
            for i in 0..<3 {
                if x == i { out[offset + i] = sx ? -inR[offset] : inR[offset] }
                if y == i { out[offset + i] = sy ? -inR[offset + 1] : inR[offset + 1] }
                if z == i { out[offset + i] = sz ? -inR[offset + 2] : inR[offset + 2] }
            }
        }
        return out
    }

    /// Port of SensorManager.getOrientation (3×3): [azimuth, pitch, roll] in radians.
    /// (The pitch uses Foundation's `asin`; only the azimuth feeds the heading.)
    static func orientation(_ r: [Double]) -> [Double] {
        [
            Geo.javaAtan2(r[1], r[4]),
            asin((-r[7]).coerceIn(-1.0, 1.0)),
            Geo.javaAtan2(-r[6], r[8]),
        ]
    }

    /// Rotation in degrees of a Surface.ROTATION_* value (for logs).
    static func rotationDegrees(_ displayRotation: Int) -> Int { (((displayRotation % 4) + 4) % 4) * 90 }
}

/// Exponential smoothing of a compass heading that always moves the short way round
/// (350° → 10° passes through 0°, never 180°), built on the engine's shortest-turn accumulator
/// (``ArrowRotation/ease(_:_:)``). `alpha` in (0, 1]: 1 = no smoothing. Output is in [0, 360).
/// Not thread-safe (one owner: ``DirectionsViewModel``, on the main actor).
final class HeadingSmoother {
    private let alpha: Double
    private let rot = ArrowRotation()
    private var started = false

    init(_ alpha: Double = 0.5) {
        self.alpha = alpha
    }

    /// The smoothed heading, or nil before the first sample.
    var value: Double? { started ? Geo.norm360(rot.value) : nil }

    @discardableResult
    func update(_ rawDeg: Double) -> Double {
        if !started {
            rot.reset(Geo.norm360(rawDeg))
            started = true
        } else {
            rot.ease(rawDeg, alpha)
        }
        return Geo.norm360(rot.value)
    }

    func reset() {
        started = false
        rot.reset()
    }
}

/// Sensor accuracy bookkeeping for the figure-8 calibration hint: the hint shows when the
/// magnetometer or the rotation vector reports SENSOR_STATUS_UNRELIABLE (0) or
/// SENSOR_STATUS_ACCURACY_LOW (1). SENSOR_STATUS_NO_CONTACT (−1) and unknown are ignored.
/// iOS: ``CompassSensor/accuracyStatus(headingAccuracy:)`` turns `CLHeading.headingAccuracy`
/// into these statuses.
enum Calibration {
    /// SensorManager.SENSOR_STATUS_UNRELIABLE
    static let UNRELIABLE = 0
    /// SensorManager.SENSOR_STATUS_ACCURACY_LOW
    static let LOW = 1

    static func isPoor(_ accuracy: Int?) -> Bool { accuracy == UNRELIABLE || accuracy == LOW }

    static func needsHint(_ magnetometerAccuracy: Int?, _ rotationVectorAccuracy: Int?) -> Bool {
        isPoor(magnetometerAccuracy) || isPoor(rotationVectorAccuracy)
    }
}

/// Lets something through at most once per `intervalMs` (for the KcnaCompass debug log).
/// Not thread-safe.
final class Throttle {
    private let intervalMs: Int64
    private var last = Int64.min

    init(_ intervalMs: Int64) {
        self.intervalMs = intervalMs
    }

    func ready(_ nowMs: Int64) -> Bool {
        // Kotlin's Long subtraction wraps; so does `&-`.
        if last != Int64.min && nowMs &- last < intervalMs { return false }
        last = nowMs
        return true
    }
}
