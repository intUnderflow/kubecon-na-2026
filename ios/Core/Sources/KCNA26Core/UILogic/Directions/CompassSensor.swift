import Foundation

/// The pure parts of Kotlin's `CompassSensor` (the compass behind the map's heading cone), and
/// how the iOS app layer replaces the rest with Core Location.
///
/// Android registers TYPE_ROTATION_VECTOR (remapped for the rotation of the display the activity
/// is on, ``CompassMath``) and TYPE_MAGNETIC_FIELD (for its accuracy only) and pushes azimuths and
/// accuracies into ``DirectionsViewModel/onAzimuth(_:_:_:_:)`` / ``DirectionsViewModel/onSensorAccuracy(_:_:)``.
///
/// ## iOS (app layer, CoreLocation)
///
/// One `CLLocationManager` per Directions screen (it can be the one used for location):
///
/// - Start with `startUpdatingHeading()` when the screen appears (and the scene is active), stop
///   with `stopUpdatingHeading()` when it disappears or the scene leaves `.active`. Both are
///   idempotent in effect, like Kotlin's `start()` / `stop()`. `headingFilter =
///   kCLHeadingFilterNone` (or 1°): the view model smooths. Check
///   `CLLocationManager.headingAvailable()` first; without it the cone stays hidden (heading nil).
/// - Display rotation (Kotlin: `remapForDisplay` for `Display.getRotation()`): set
///   `headingOrientation` to the interface orientation at start and on every interface rotation
///   (`windowScene.interfaceOrientation`, e.g. from the scene's `effectiveGeometry` or a
///   size change): `CLDeviceOrientation(rawValue: headingOrientation(interfaceOrientationRawValue:
///   scene.interfaceOrientation.rawValue))`. Core Location then reports the heading of the top
///   of the screen as the user sees it, which is what the Android remap computes.
/// - `locationManagerShouldDisplayHeadingCalibration(_:)` → `false`: the app shows its own
///   figure-8 hint (``DirectionsViewModel/calibrate``, ``DirectionsText/CALIBRATE_TITLE``).
/// - Every `CLHeading`: if an ``ObservedDeclination`` is installed as ``Geo/declinationSource``,
///   `record(trueHeading:magneticHeading:headingAccuracy:)` it, then call
///   ``DirectionsViewModel/onHeading(trueHeading:magneticHeading:headingAccuracy:timeMs:)`` with
///   `timeMs = Int64(heading.timestamp.timeIntervalSince1970 * 1000)`.
/// - Debug log: pass `{ Logger(subsystem: …, category: CompassSensor.TAG).debug("\($0)") }` as
///   the view model's `log`.
enum CompassSensor {
    /// The debug log tag (Kotlin `CompassSensor.TAG`, logcat "KcnaCompass").
    static let TAG = "KcnaCompass"

    /// android.hardware.Sensor.TYPE_MAGNETIC_FIELD (for ``DirectionsViewModel/onSensorAccuracy(_:_:)``).
    static let TYPE_MAGNETIC_FIELD = 2

    /// android.hardware.Sensor.TYPE_ROTATION_VECTOR. iOS reports a heading accuracy in its place.
    static let TYPE_ROTATION_VECTOR = 11

    /// SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM.
    static let MEDIUM = 2

    /// SensorManager.SENSOR_STATUS_ACCURACY_HIGH.
    static let HIGH = 3

    /// iOS: a `CLHeading.headingAccuracy` (maximum error, degrees) above this counts as
    /// SENSOR_STATUS_ACCURACY_LOW (the figure-8 hint shows after ``DirectionsViewModel/CALIBRATE_AFTER_MS``).
    /// Android has no degree scale; 45° (an eighth of the compass, where the cone would point
    /// at the wrong side of a corridor) is this port's choice.
    static let LOW_ACCURACY_DEG = 45.0

    /// iOS: `CLHeading.headingAccuracy` as an Android sensor status for ``Calibration``:
    /// negative (Core Location: invalid, needs calibration) or NaN → ``Calibration/UNRELIABLE``,
    /// above ``LOW_ACCURACY_DEG`` → ``Calibration/LOW``, above half of it → ``MEDIUM``, else ``HIGH``.
    static func accuracyStatus(headingAccuracy: Double) -> Int {
        if !(headingAccuracy >= 0) { return Calibration.UNRELIABLE }
        if headingAccuracy > LOW_ACCURACY_DEG { return Calibration.LOW }
        if headingAccuracy > LOW_ACCURACY_DEG / 2 { return MEDIUM }
        return HIGH
    }

    /// iOS: the `CLDeviceOrientation` raw value for `CLLocationManager.headingOrientation`, from
    /// a `UIInterfaceOrientation` raw value. UIKit defines the interface orientations by the
    /// device orientation that shows them upright (interface `.landscapeLeft` = 4 = device
    /// `.landscapeRight`), and `CLDeviceOrientation` uses the device's raw values, so portrait (1),
    /// upside down (2), landscape right (3) and left (4) carry over as they are; unknown (0) or
    /// anything else gives portrait (1), Core Location's default.
    static func headingOrientation(interfaceOrientationRawValue raw: Int) -> Int32 {
        (1...4).contains(raw) ? Int32(raw) : 1
    }

    /// Java `String.format(Locale.ROOT, "%.1f", x)` for the debug log: the shortest decimal
    /// digits of `x` rounded HALF_UP to one decimal (Java rounds the decimal digits, so 0.15 gives
    /// "0.2" where C's printf gives "0.1"); "NaN", "Infinity", "-Infinity"; a negative value keeps
    /// its sign ("-0.0").
    static func javaFixed1(_ x: Double) -> String { javaFixed(x, 1) }

    /// Java `%.<decimals>f` (see ``javaFixed1(_:)``).
    static func javaFixed(_ x: Double, _ decimals: Int) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        var s = "\(abs(x))" // shortest round-trip digits: "80.0", "1e-05", "1.5e+16"
        var exp10 = 0
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exp10 = Int(s[s.index(after: e)...]) ?? 0
            s = String(s[..<e])
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = parts.first.map(String.init) ?? "0"
        let fracPart = parts.count > 1 ? String(parts[1]) : ""
        var digits: [UInt8] = Array((intPart + fracPart).utf8).map { $0 &- 48 }
        var point = intPart.count + exp10 // digits before the decimal point
        if point < 1 {
            digits = [UInt8](repeating: 0, count: 1 - point) + digits
            point = 1
        }
        let keep = point + max(0, decimals)
        if digits.count < keep { digits += [UInt8](repeating: 0, count: keep - digits.count) }
        let roundUp = digits.count > keep && digits[keep] >= 5
        digits = Array(digits[0..<keep])
        if roundUp {
            var i = keep - 1
            while i >= 0 && digits[i] == 9 {
                digits[i] = 0
                i -= 1
            }
            if i >= 0 {
                digits[i] += 1
            } else {
                digits.insert(1, at: 0)
                point += 1
            }
        }
        var intDigits = Array(digits[0..<point].drop(while: { $0 == 0 }))
        if intDigits.isEmpty { intDigits = [0] }
        let whole = String(decoding: intDigits.map { $0 + 48 }, as: UTF8.self)
        let frac = String(decoding: digits[point...].map { $0 + 48 }, as: UTF8.self)
        let sign = x.sign == .minus ? "-" : ""
        return decimals > 0 ? "\(sign)\(whole).\(frac)" : "\(sign)\(whole)"
    }
}
