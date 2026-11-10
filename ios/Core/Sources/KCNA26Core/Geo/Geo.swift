import Foundation

/// Pure geometry for Directions (distance, bearing, heading) and the router (owner: engine). Ports of
/// schedule_app.js: the LAT0/LON0/MY/MX conversion, `brgTo`, `dir8`, `r10`, and the
/// `LV.rot` accumulator in `lvPaint` (see ``ArrowRotation``).
///
/// Coordinates are local metres (x east, y north, true north) from wayfinding.json
/// "origin". Everything here is allocation-light and safe to call on the main thread
/// for every sensor or location update. No function throws or traps, NaN in gives a harmless
/// value out.
///
/// Kotlin -> Swift: the arithmetic keeps Kotlin's operation order, and `hypot` / `atan2` are
/// Java's (``javaHypot(_:_:)``, ``javaAtan2(_:_:)``: fdlibm, as on the JVM and Android), so
/// distances and bearings are bit-identical to the Android app's.
///
/// ## Heading on iOS
///
/// Android computes the true heading as rotation-vector azimuth + ``declinationDeg(_:_:_:_:)``
/// (`android.hardware.GeomagneticField`). iOS has no public declination model, but Core
/// Location applies one itself: `CLHeading.trueHeading` is already true north whenever
/// location updates are running. The app layer therefore feeds headings like this:
///
/// 1. Keep `CLLocationManager.headingOrientation` equal to the device orientation of the
///    current interface (`CLDeviceOrientation` uses device orientations: interface
///    `.landscapeLeft` is device `.landscapeRight` and vice versa). The Android code remaps the
///    azimuth for the display rotation (CompassMath); Core Location does that for you.
/// 2. On every `CLHeading`, call ``ObservedDeclination/record(trueHeading:magneticHeading:headingAccuracy:)``
///    on the ``ObservedDeclination`` installed as ``declinationSource`` at start-up (so a later
///    reading without a true heading still gets Core Location's own declination), then
///    ``compassTrueHeading(trueHeading:magneticHeading:headingAccuracy:declinationDeg:)``
///    with the current declination (``declinationDeg(_:_:_:_:)`` at the last fix, or at the
///    venue origin before one, with the app clock's time). It uses `trueHeading` as is when
///    it is valid (never adding the declination a second time), else `magneticHeading` +
///    declination, and returns nil for an invalid reading (`headingAccuracy` < 0).
/// 3. Feed the result (a TRUE heading) to the heading smoothing; do not pass it through
///    ``trueHeading(_:_:)`` again.
///
/// With no source installed (and before the first heading with a true heading),
/// ``declinationDeg(_:_:_:_:)`` answers ``SLC_DECLINATION_DEG``: 10.4° east, the web's `DECL`
/// ("about 10 degrees east at Salt Lake City", wayfinding.json), which is what a magnetic-only
/// reading needs at the venue.
enum Geo {
    /// Magnetic declination at Salt Lake City (web `DECL`), only a fallback for ``declinationDeg(_:_:_:_:)``.
    static let SLC_DECLINATION_DEG = 10.4

    /// lat/lng → local metres: x = (lng − lon0)·metersPerDegLon, y = (lat − lat0)·metersPerDegLat.
    static func toLocal(_ lat: Double, _ lng: Double, _ origin: Origin) -> PointXY {
        PointXY((lng - origin.lon0) * origin.metersPerDegLon, (lat - origin.lat0) * origin.metersPerDegLat)
    }

    /// Horizontal straight-line distance in metres.
    static func distance(_ a: PointXY, _ b: PointXY) -> Double { javaHypot(b.x - a.x, b.y - a.y) }

    /// True bearing from `from` to `to`, degrees clockwise from north, in [0, 360). Web `brgTo`.
    static func bearing(_ from: PointXY, _ to: PointXY) -> Double {
        (toDegrees(javaAtan2(to.x - from.x, to.y - from.y)) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Eight-way direction word, web `dir8`: `[…][Math.round(b/45) % 8]`. 337.5° and up is
    /// "north" again; half-way values round up like JavaScript (22.5° → "north-east").
    /// Negative and ≥ 360 inputs are wrapped; NaN gives "north".
    static func dir8(_ bearingDeg: Double) -> String {
        let i = Int(floorMod(jsRound(bearingDeg / 45.0), Int64(8)))
        return DIRS[i]
    }

    /// Distance rounded to 10 m, at least 10 (web `r10`): max(10, round(m/10)·10).
    static func r10(_ m: Double) -> Int {
        (Double(jsRound(m / 10.0)) * 10.0).coerceIn(10.0, Double(Int32.max)).kotlinToInt()
    }

    /// Rounds to the nearest 10 m with no minimum (the summary's `Math.round(m/10)*10`).
    /// Wraps on overflow like Kotlin's `Long` multiplication (never traps).
    static func round10(_ m: Double) -> Int64 { jsRound(m / 10.0) &* 10 }

    /// "120 m north-east": the Directions distance line (web `${r10(dist)} m ${dir8(b)}`).
    static func distanceLabel(_ distanceM: Double, _ bearingDeg: Double) -> String {
        "\(r10(distanceM)) m \(dir8(bearingDeg))"
    }

    /// Radius within which Directions says "You’re about here": max(15 m, 0.6 × accuracy)
    /// (Java `Math.max`: NaN accuracy gives NaN, so ``isAboutHere(_:_:)`` is false).
    static func hereRadius(_ accuracyM: Double) -> Double { javaMax(15.0, accuracyM * 0.6) }

    /// Web `here = dist < max(15, acc·0.6)`.
    static func isAboutHere(_ distanceM: Double, _ accuracyM: Double) -> Bool { distanceM < hereRadius(accuracyM) }

    /// trueHeading = (magneticAzimuth + declination + 360) % 360, in [0, 360).
    static func trueHeading(_ magneticAzimuthDeg: Double, _ declinationDeg: Double) -> Double {
        norm360(magneticAzimuthDeg + declinationDeg)
    }

    /// Angle of a bearing relative to the top of the phone, in [0, 360): bearing − trueHeading
    /// (the web's compass arrow; the app no longer draws one, but test_vectors.json checks it).
    /// Feed it (or the raw difference) to ``ArrowRotation/update(_:)`` so a rotation turns the short way.
    static func arrowDeg(_ trueHeadingDeg: Double, _ bearingDeg: Double) -> Double { norm360(bearingDeg - trueHeadingDeg) }

    /// Wraps any angle into [0, 360).
    static func norm360(_ deg: Double) -> Double {
        (deg.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Signed shortest turn from `fromDeg` to `toDeg`, in [−180, 180) (web `((rot−LV.rot)%360+540)%360−180`).
    static func shortestTurn(_ fromDeg: Double, _ toDeg: Double) -> Double {
        ((toDeg - fromDeg).truncatingRemainder(dividingBy: 360.0) + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0
    }

    // MARK: - Declination

    /// Magnetic declination (degrees east) at a position and time, from ``declinationSource``
    /// (Kotlin: `GeomagneticField`). Pass the app clock's time (`clock.now().epochMillis`),
    /// never the system time. Falls back to ``SLC_DECLINATION_DEG`` if the source has no
    /// answer or returns something unusable (not finite, or more than 180° either way).
    ///
    /// The four-argument form matches Kotlin's `Geo::declinationDeg`, so it can be passed where
    /// a `(lat, lng, altitudeM, epochMillis) -> Double` is expected.
    static func declinationDeg(_ lat: Double, _ lng: Double, _ altitudeM: Double, _ epochMillis: Int64) -> Double {
        declinationDeg(lat, lng, altitudeM, epochMillis, source: declinationSource)
    }

    /// ``declinationDeg(_:_:_:_:)`` with an explicit source.
    static func declinationDeg(
        _ lat: Double, _ lng: Double, _ altitudeM: Double, _ epochMillis: Int64, source: any DeclinationSource
    ) -> Double {
        guard let d = source.declinationDeg(lat: lat, lng: lng, altitudeM: altitudeM, epochMillis: epochMillis),
              d.isFinite, abs(d) <= 180.0 else { return SLC_DECLINATION_DEG }
        return d
    }

    /// The model ``declinationDeg(_:_:_:_:)`` asks. ``NoDeclinationModel`` by default (so the
    /// answer is ``SLC_DECLINATION_DEG``); the app may install an ``ObservedDeclination`` at
    /// start-up. Thread-safe.
    static var declinationSource: any DeclinationSource {
        get { declinationSourceBox.value }
        set { declinationSourceBox.value = newValue }
    }

    private static let declinationSourceBox = Locked<any DeclinationSource>(NoDeclinationModel())

    /// The true heading of the top of the phone for one Core Location heading reading
    /// (`CLHeading.trueHeading`, `.magneticHeading`, `.headingAccuracy`), in [0, 360):
    ///
    /// - nil when `headingAccuracy` is negative (CLHeading: invalid reading, e.g. uncalibrated or
    ///   magnetic interference), or `headingAccuracy` / `magneticHeading` is not finite;
    /// - `trueHeading` (wrapped) when it is ≥ 0: Core Location has already applied the
    ///   declination, so it is not added again;
    /// - otherwise (`trueHeading` is −1 when Core Location could not work out true north, e.g.
    ///   no location yet) `trueHeading(magneticHeading, declinationDeg)`.
    static func compassTrueHeading(
        trueHeading: Double, magneticHeading: Double, headingAccuracy: Double, declinationDeg: Double
    ) -> Double? {
        guard headingAccuracy.isFinite, headingAccuracy >= 0 else { return nil }
        if trueHeading.isFinite && trueHeading >= 0 { return norm360(trueHeading) }
        guard magneticHeading.isFinite else { return nil }
        return Geo.trueHeading(magneticHeading, declinationDeg.isFinite ? declinationDeg : SLC_DECLINATION_DEG)
    }

    // MARK: - Java math

    /// JavaScript Math.round: nearest integer, halves toward +∞; NaN → 0 (never throws, unlike roundToInt).
    static func jsRound(_ x: Double) -> Int64 { x.kotlinRoundToLong() }

    /// Java `Math.toDegrees` (JDK 9+: one multiplication by 180/π).
    static func toDegrees(_ angrad: Double) -> Double { angrad * RADIANS_TO_DEGREES }

    private static let RADIANS_TO_DEGREES = 57.29577951308232

    /// Java `Math.max(double, double)`: NaN if either is NaN; +0.0 beats −0.0.
    static func javaMax(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0.0 && b == 0.0 && a.sign == .minus { return b }
        return a >= b ? a : b
    }

    /// Kotlin `hypot` on the JVM (`Math.hypot` = `StrictMath.hypot`, fdlibm's `e_hypot.c`, as
    /// transliterated in the JDK's `FdLibm.Hypot`): √(x² + y²) without undue overflow or
    /// underflow, error under 1 ulp. Foundation's `hypot` (glibc / Apple libm) is a different
    /// algorithm that can differ in the last bit (glibc: for about one input in ten), which
    /// could tip a Dijkstra tie or a rounding boundary, so the router and ``distance(_:_:)``
    /// use this one.
    static func javaHypot(_ x: Double, _ y: Double) -> Double {
        var a = abs(x)
        var b = abs(y)
        if !a.isFinite || !b.isFinite {
            if a == .infinity || b == .infinity { return .infinity }
            return a + b // NaN
        }
        if b > a { swap(&a, &b) }
        var ha = highWord(a)
        var hb = highWord(b)
        if ha - hb > 0x3c0_0000 { return a + b } // x / y > 2**60
        var k: Int32 = 0
        if a > 0x1.00000_ffff_ffffp500 { // a > ~2**500: scale a and b by 2**-600
            ha -= 0x2580_0000
            hb -= 0x2580_0000
            a = a * 0x1.0p-600
            b = b * 0x1.0p-600
            k += 600
        }
        var t1: Double
        var t2: Double
        if b < 0x1.0p-500 { // b < 2**-500
            if b < Double.leastNormalMagnitude { // subnormal b or 0
                if b == 0.0 { return a }
                t1 = 0x1.0p1022
                b *= t1
                a *= t1
                k -= 1022
                // As in fdlibm and the JDK, ha and hb are not refreshed here.
            } else { // scale a and b by 2^600
                ha += 0x2580_0000
                hb += 0x2580_0000
                a = a * 0x1.0p600
                b = b * 0x1.0p600
                k -= 600
            }
        }
        // medium size a and b
        var w = a - b
        if w > b {
            t1 = withHighWord(ha)
            t2 = a - t1
            w = (t1 * t1 - (b * (-b) - t2 * (a + t1))).squareRoot()
        } else {
            a = a + a
            let y1 = withHighWord(hb)
            let y2 = b - y1
            t1 = withHighWord(ha + 0x0010_0000)
            t2 = a - t1
            w = (t1 * y1 - (w * (-w) - (t1 * y2 + t2 * b))).squareRoot()
        }
        if k != 0 {
            return Double(sign: .plus, exponent: Int(k), significand: 1.0) * w
        }
        return w
    }

    /// Kotlin `atan2(y, x)` on the JVM and Android (`StrictMath.atan2` / bionic: fdlibm's
    /// `e_atan2.c` and `s_atan.c`), bit for bit. Foundation's `atan2` can differ in the last
    /// bit (glibc: for about one input in five); ``bearing(_:_:)`` uses this one so bearings
    /// (and the direction words rounded from them) are exactly the Android app's.
    static func javaAtan2(_ y: Double, _ x: Double) -> Double {
        if x.isNaN || y.isNaN { return x + y }
        let hx = highWord(x), ix = hx & 0x7fff_ffff
        let lx = UInt32(truncatingIfNeeded: x.bitPattern)
        let hy = highWord(y), iy = hy & 0x7fff_ffff
        let ly = UInt32(truncatingIfNeeded: y.bitPattern)
        if x == 1.0 { return fdlibmAtan(y) } // x = 1.0
        let m = Int((hy >> 31) & 1) | Int((hx >> 30) & 2) // 2*sign(x)+sign(y)

        // when y = 0
        if iy == 0 && ly == 0 {
            switch m {
            case 0, 1: return y // atan(+-0,+anything)=+-0
            case 2: return ATAN2_PI + ATAN2_TINY // atan(+0,-anything) = pi
            default: return -ATAN2_PI - ATAN2_TINY // atan(-0,-anything) =-pi
            }
        }
        // when x = 0
        if ix == 0 && lx == 0 { return hy < 0 ? -ATAN2_PI_O_2 - ATAN2_TINY : ATAN2_PI_O_2 + ATAN2_TINY }

        // when x is INF
        if ix == 0x7ff0_0000 {
            if iy == 0x7ff0_0000 {
                switch m {
                case 0: return ATAN2_PI_O_4 + ATAN2_TINY // atan(+INF,+INF)
                case 1: return -ATAN2_PI_O_4 - ATAN2_TINY // atan(-INF,+INF)
                case 2: return 3.0 * ATAN2_PI_O_4 + ATAN2_TINY // atan(+INF,-INF)
                default: return -3.0 * ATAN2_PI_O_4 - ATAN2_TINY // atan(-INF,-INF)
                }
            } else {
                switch m {
                case 0: return 0.0 // atan(+...,+INF)
                case 1: return -0.0 // atan(-...,+INF)
                case 2: return ATAN2_PI + ATAN2_TINY // atan(+...,-INF)
                default: return -ATAN2_PI - ATAN2_TINY // atan(-...,-INF)
                }
            }
        }
        // when y is INF
        if iy == 0x7ff0_0000 { return hy < 0 ? -ATAN2_PI_O_2 - ATAN2_TINY : ATAN2_PI_O_2 + ATAN2_TINY }

        // compute y/x
        let k = (iy - ix) >> 20
        let z: Double
        if k > 60 {
            z = ATAN2_PI_O_2 + 0.5 * ATAN2_PI_LO // |y/x| >  2**60
        } else if hx < 0 && k < -60 {
            z = 0.0 // |y|/x < -2**60
        } else {
            z = fdlibmAtan(abs(y / x)) // safe to do y/x
        }
        switch m {
        case 0: return z // atan(+,+)
        case 1: return Double(bitPattern: z.bitPattern ^ (1 << 63)) // atan(-,+)
        case 2: return ATAN2_PI - (z - ATAN2_PI_LO) // atan(+,-)
        default: return (z - ATAN2_PI_LO) - ATAN2_PI // atan(-,-)
        }
    }

    /// fdlibm `s_atan.c` (`StrictMath.atan`).
    private static func fdlibmAtan(_ x0: Double) -> Double {
        var x = x0
        let hx = highWord(x)
        let ix = hx & 0x7fff_ffff
        let id: Int
        if ix >= 0x4410_0000 { // if |x| >= 2^66
            if x.isNaN { return x + x }
            return hx > 0 ? ATAN_HI[3] + ATAN_LO[3] : -ATAN_HI[3] - ATAN_LO[3]
        }
        if ix < 0x3fdc_0000 { // |x| < 0.4375
            if ix < 0x3e20_0000 { return x } // |x| < 2^-29
            id = -1
        } else {
            x = abs(x)
            if ix < 0x3ff3_0000 { // |x| < 1.1875
                if ix < 0x3fe6_0000 { // 7/16 <=|x|<11/16
                    id = 0
                    x = (2.0 * x - 1.0) / (2.0 + x)
                } else { // 11/16<=|x|< 19/16
                    id = 1
                    x = (x - 1.0) / (x + 1.0)
                }
            } else {
                if ix < 0x4003_8000 { // |x| < 2.4375
                    id = 2
                    x = (x - 1.5) / (1.0 + 1.5 * x)
                } else { // 2.4375 <= |x| < 2^66
                    id = 3
                    x = -1.0 / x
                }
            }
        }
        // end of argument reduction
        let z = x * x
        let w = z * z
        // break sum from i=0 to 10 aT[i]z**(i+1) into odd and even poly
        let s1: Double = z * (AT[0] + w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10])))))
        let s2: Double = w * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * AT[9]))))
        if id < 0 { return x - x * (s1 + s2) }
        let r: Double = ATAN_HI[id] - ((x * (s1 + s2) - ATAN_LO[id]) - x)
        return hx < 0 ? -r : r
    }

    private static let ATAN_HI: [Double] = [
        Double(bitPattern: 0x3FDD_AC67_0561_BB4F), // atan(0.5)hi
        Double(bitPattern: 0x3FE9_21FB_5444_2D18), // atan(1.0)hi
        Double(bitPattern: 0x3FEF_730B_D281_F69B), // atan(1.5)hi
        Double(bitPattern: 0x3FF9_21FB_5444_2D18), // atan(inf)hi
    ]

    private static let ATAN_LO: [Double] = [
        Double(bitPattern: 0x3C7A_2B7F_222F_65E2), // atan(0.5)lo
        Double(bitPattern: 0x3C81_A626_3314_5C07), // atan(1.0)lo
        Double(bitPattern: 0x3C70_0788_7AF0_CBBD), // atan(1.5)lo
        Double(bitPattern: 0x3C91_A626_3314_5C07), // atan(inf)lo
    ]

    private static let AT: [Double] = [
        Double(bitPattern: 0x3FD5_5555_5555_550D),
        Double(bitPattern: 0xBFC9_9999_9998_EBC4),
        Double(bitPattern: 0x3FC2_4924_9200_83FF),
        Double(bitPattern: 0xBFBC_71C6_FE23_1671),
        Double(bitPattern: 0x3FB7_45CD_C54C_206E),
        Double(bitPattern: 0xBFB3_B0F2_AF74_9A6D),
        Double(bitPattern: 0x3FB1_0D66_A0D0_3D51),
        Double(bitPattern: 0xBFAD_DE2D_52DE_FD9A),
        Double(bitPattern: 0x3FA9_7B4B_2476_0DEB),
        Double(bitPattern: 0xBFA2_B444_2C6A_6C2F),
        Double(bitPattern: 0x3F90_AD3A_E322_DA11),
    ]

    private static let ATAN2_TINY = 1.0e-300
    private static let ATAN2_PI_O_4 = Double(bitPattern: 0x3FE9_21FB_5444_2D18)
    private static let ATAN2_PI_O_2 = Double(bitPattern: 0x3FF9_21FB_5444_2D18)
    private static let ATAN2_PI = Double(bitPattern: 0x4009_21FB_5444_2D18)
    private static let ATAN2_PI_LO = Double(bitPattern: 0x3CA1_A626_3314_5C07)

    /// fdlibm `__HI(x)`: the high 32 bits of a double, as a signed int.
    private static func highWord(_ d: Double) -> Int32 {
        Int32(bitPattern: UInt32(truncatingIfNeeded: d.bitPattern >> 32))
    }

    /// A double whose high word is `hi` and whose low word is 0 (fdlibm `t = 0; __HI(t) = hi`).
    private static func withHighWord(_ hi: Int32) -> Double {
        Double(bitPattern: UInt64(UInt32(bitPattern: hi)) << 32)
    }

    private static let DIRS = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
}

// MARK: - Declination sources

/// A magnetic declination model for ``Geo/declinationDeg(_:_:_:_:)`` (Kotlin:
/// `android.hardware.GeomagneticField`, the World Magnetic Model). iOS has no public one: see
/// "Heading on iOS" in ``Geo``.
protocol DeclinationSource: Sendable {
    /// Degrees east at a position (degrees, metres above sea level) and time (epoch millis),
    /// or nil when unknown.
    func declinationDeg(lat: Double, lng: Double, altitudeM: Double, epochMillis: Int64) -> Double?
}

/// No model (the default): ``Geo/declinationDeg(_:_:_:_:)`` answers ``Geo/SLC_DECLINATION_DEG``.
struct NoDeclinationModel: DeclinationSource {
    func declinationDeg(lat: Double, lng: Double, altitudeM: Double, epochMillis: Int64) -> Double? { nil }
}

/// The same declination everywhere (tests and previews).
struct FixedDeclination: DeclinationSource {
    let deg: Double

    init(_ deg: Double) {
        self.deg = deg
    }

    func declinationDeg(lat: Double, lng: Double, altitudeM: Double, epochMillis: Int64) -> Double? { deg }
}

/// The declination Core Location applies itself: `trueHeading − magneticHeading` (the short
/// way round) of the latest `CLHeading` that had both, or nil before the first such reading.
/// The app installs one as ``Geo/declinationSource`` and records every heading into it, so a
/// reading without a true heading (location briefly unavailable) is corrected the same way.
/// Position and time are ignored: across the venue the declination does not change. Thread-safe.
final class ObservedDeclination: DeclinationSource {
    private let last = Locked<Double?>(nil)

    init() {}

    /// Records one `CLHeading`; ignored unless it is valid (`headingAccuracy` ≥ 0) and has a true
    /// heading (≥ 0).
    func record(trueHeading: Double, magneticHeading: Double, headingAccuracy: Double) {
        guard headingAccuracy.isFinite, headingAccuracy >= 0,
              trueHeading.isFinite, trueHeading >= 0, magneticHeading.isFinite else { return }
        let d = Geo.shortestTurn(magneticHeading, trueHeading)
        last.value = d
    }

    /// The last recorded declination (degrees east), or nil.
    var lastDeclinationDeg: Double? { last.value }

    func declinationDeg(lat: Double, lng: Double, altitudeM: Double, epochMillis: Int64) -> Double? { last.value }
}

// MARK: - ArrowRotation

/// Shortest-turn rotation accumulator, the web's compass-arrow smoothing
/// `LV.rot += ((rot − LV.rot) % 360 + 540) % 360 − 180`. The app uses it for the heading
/// cone on the Directions map.
///
/// ``value`` is unbounded (it may go past 360 or below 0), so animating it (for example a
/// SwiftUI `.rotationEffect(.degrees(value))` with an animation) never spins the long way round:
/// every update moves by at most 180°. Heading 350° → bearing 10° moves +20°, not −340°.
/// Not thread-safe; keep one per rotating thing (in a view model or `@State`).
final class ArrowRotation {
    /// Current accumulated rotation in degrees (unbounded).
    private(set) var value: Double

    /// The change made by the last ``update(_:)`` or ``ease(_:_:)``, always in [−180, 180).
    private(set) var lastDelta: Double = 0.0

    init(_ initialDeg: Double = 0.0) {
        value = initialDeg.isFinite ? initialDeg : 0.0
    }

    /// Moves ``value`` to the equivalent of `targetDeg` (any angle, e.g. bearing − heading)
    /// closest to the current value and returns it. A non-finite target is ignored.
    @discardableResult
    func update(_ targetDeg: Double) -> Double {
        if !targetDeg.isFinite {
            lastDelta = 0.0
            return value
        }
        lastDelta = Geo.shortestTurn(value, targetDeg)
        value += lastDelta
        return value
    }

    /// Like ``update(_:)`` but only moves `fraction` (0..1] of the shortest turn: a simple
    /// low-pass filter for jittery sensors. `ease(t, 1.0)` equals `update(t)`.
    @discardableResult
    func ease(_ targetDeg: Double, _ fraction: Double) -> Double {
        if !targetDeg.isFinite || !fraction.isFinite {
            lastDelta = 0.0
            return value
        }
        lastDelta = Geo.shortestTurn(value, targetDeg) * fraction.coerceIn(0.0, 1.0)
        value += lastDelta
        return value
    }

    /// Jumps to `deg` (e.g. when the destination changes).
    func reset(_ deg: Double = 0.0) {
        value = deg.isFinite ? deg : 0.0
        lastDelta = 0.0
    }
}
