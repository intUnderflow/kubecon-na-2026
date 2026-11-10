import Foundation
import XCTest
@testable import KCNA26Core

final class GeoTests: XCTestCase {
    private let repo = TestData.repo
    private var origin: Origin { repo.wayfinding.origin }

    private func angleDiff(_ a: Double, _ b: Double) -> Double { abs(Geo.shortestTurn(a, b)) }

    // ---------------------------------------------------------------- test_vectors.json "compass"

    func testCompassVectorsDistanceAndBearing() {
        let vectors = TestData.vectors.compass
        XCTAssertEqual(vectors.count, 4)
        for v in vectors {
            let room = repo.room(v.room)
            XCTAssertNotNil(room, v.where)
            guard let room else { continue }
            XCTAssertEqual(room.level, v.roomLevel, v.where)
            let me = Geo.toLocal(v.lat, v.lng, origin)
            let dest = room.pos!
            XCTAssertEqual(Geo.distance(me, dest), v.expectDistanceM, accuracy: 3.0, "\(v.where): distance")
            let b = Geo.bearing(me, dest)
            XCTAssertTrue(angleDiff(b, v.expectBearingTrueDeg) <= 2.0, "\(v.where): bearing \(b) vs \(v.expectBearingTrueDeg)")
        }
    }

    func testToLocalUsesWayfindingOrigin() {
        XCTAssertEqual(origin.metersPerDegLon, 84300.0, accuracy: 0.0)
        XCTAssertEqual(origin.metersPerDegLat, 111000.0, accuracy: 0.0)
        let p = Geo.toLocal(origin.lat0 + 0.001, origin.lon0 - 0.001, origin)
        XCTAssertEqual(p.x, -84.3, accuracy: 1e-9)
        XCTAssertEqual(p.y, 111.0, accuracy: 1e-9)
        // rooms.json x/y agree with their lat/lng under this formula (to the rounding of x/y).
        for r in repo.rooms.values.filter({ $0.hasPosition }) {
            let q = Geo.toLocal(r.lat!, r.lng!, origin)
            XCTAssertEqual(q.x, r.x!, accuracy: 1.5, r.code)
            XCTAssertEqual(q.y, r.y!, accuracy: 1.5, r.code)
        }
    }

    func testBearingIsTrueAndInRange() {
        let o = PointXY(0.0, 0.0)
        XCTAssertEqual(Geo.bearing(o, PointXY(0.0, 10.0)), 0.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearing(o, PointXY(10.0, 0.0)), 90.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearing(o, PointXY(0.0, -10.0)), 180.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearing(o, PointXY(-10.0, 0.0)), 270.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearing(o, PointXY(5.0, 5.0)), 45.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearing(o, o), 0.0, accuracy: 0.0) // same point: north, not NaN
        var rnd = KotlinXorWowRandom(7)
        for _ in 0..<2000 {
            let from = PointXY(rnd.nextDouble(-500.0, 500.0), rnd.nextDouble(-500.0, 500.0))
            let to = PointXY(rnd.nextDouble(-500.0, 500.0), rnd.nextDouble(-500.0, 500.0))
            let b = Geo.bearing(from, to)
            XCTAssertTrue(b >= 0.0 && b < 360.0, "\(b)")
        }
        XCTAssertEqual(Geo.distance(PointXY(1.0, 1.0), PointXY(4.0, 5.0)), 5.0, accuracy: 1e-12)
    }

    // ---------------------------------------------------------------- dir8, r10

    func testDir8Words() {
        let words = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        for (i, w) in words.enumerated() { XCTAssertEqual(Geo.dir8(Double(i) * 45.0), w) }
        XCTAssertEqual(Geo.dir8(22.4), "north")
        XCTAssertEqual(Geo.dir8(22.5), "north-east") // JS Math.round rounds halves up
        XCTAssertEqual(Geo.dir8(67.4), "north-east")
        XCTAssertEqual(Geo.dir8(67.5), "east")
        XCTAssertEqual(Geo.dir8(337.4), "north-west")
        XCTAssertEqual(Geo.dir8(337.5), "north") // round(7.5) = 8, % 8 = 0
        XCTAssertEqual(Geo.dir8(359.9), "north")
        XCTAssertEqual(Geo.dir8(360.0), "north")
        XCTAssertEqual(Geo.dir8(450.0), "east")
        XCTAssertEqual(Geo.dir8(-45.0), "north-west")
        XCTAssertEqual(Geo.dir8(Double.nan), "north") // never throws
        XCTAssertEqual(Geo.dir8(214.0), "south-west") // test vector: EWT from Temple Square
    }

    func testR10Rounding() {
        XCTAssertEqual(Geo.r10(0.0), 10)
        XCTAssertEqual(Geo.r10(3.0), 10)
        XCTAssertEqual(Geo.r10(14.9), 10)
        XCTAssertEqual(Geo.r10(15.0), 20) // halves round up, like Math.round
        XCTAssertEqual(Geo.r10(24.99), 20)
        XCTAssertEqual(Geo.r10(383.0), 380)
        XCTAssertEqual(Geo.r10(386.0), 390)
        XCTAssertEqual(Geo.r10(-50.0), 10)
        XCTAssertEqual(Geo.r10(Double.nan), 10) // never throws
        XCTAssertEqual(Geo.round10(4.0), Int64(0))
        XCTAssertEqual(Geo.round10(253.6), Int64(250))
        XCTAssertEqual(Geo.round10(184.3), Int64(180))
        XCTAssertEqual(Geo.distanceLabel(118.0, 40.0), "120 m north-east")
        XCTAssertEqual(Geo.distanceLabel(2.0, 0.0), "10 m north")
    }

    func testHereRadius() {
        XCTAssertEqual(Geo.hereRadius(5.0), 15.0, accuracy: 0.0)
        XCTAssertEqual(Geo.hereRadius(25.0), 15.0, accuracy: 0.0)
        XCTAssertEqual(Geo.hereRadius(50.0), 30.0, accuracy: 1e-9)
        XCTAssertTrue(Geo.isAboutHere(14.9, 0.0))
        XCTAssertFalse(Geo.isAboutHere(15.0, 0.0)) // strict <, as in the web
        XCTAssertTrue(Geo.isAboutHere(29.0, 50.0))
        XCTAssertFalse(Geo.isAboutHere(10.0, Double.nan))
    }

    // ---------------------------------------------------------------- heading and arrow

    func testTrueHeadingAddsDeclination() {
        XCTAssertEqual(Geo.trueHeading(0.0, 10.0), 10.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.trueHeading(355.0, 10.0), 5.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.trueHeading(-20.0, 10.0), 350.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.trueHeading(350.0, 10.0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.trueHeading(1.0, -2.0), 359.0, accuracy: 1e-9)
        // On the JVM the Kotlin test ran against android.jar's stub GeomagneticField (unit tests
        // return default values), so its declination was 0.0 and only "finite" was checked. Here
        // the default source has no model, so the answer is the venue fallback; the fallback
        // rules themselves are pinned in testDeclinationSourcesAndFallback.
        XCTAssertTrue(Geo.declinationDeg(40.767, -111.895, 1300.0, 1_794_000_000_000).isFinite)
    }

    func testArrowRotationVectors() {
        let vectors = TestData.vectors.arrowRotation
        XCTAssertEqual(vectors.count, 3)
        for v in vectors {
            let a = Geo.arrowDeg(v.trueHeadingDeg, v.bearingDeg)
            XCTAssertTrue(a >= 0.0 && a < 360.0, "arrowDeg \(a)")
            XCTAssertEqual(Geo.shortestTurn(a, v.arrowDeg), 0.0, accuracy: 1e-9, "arrowDeg \(v)") // mod-360 equivalent

            // From an arrow at rest pointing up, the accumulator turns the short way.
            let acc = ArrowRotation()
            let value = acc.update(v.bearingDeg - v.trueHeadingDeg)
            XCTAssertEqual(Geo.shortestTurn(value, v.arrowDeg), 0.0, accuracy: 1e-9, "accumulated \(v)")
            XCTAssertTrue(abs(acc.lastDelta) <= 180.0, "delta \(acc.lastDelta) for \(v)")
            XCTAssertEqual(acc.value, value, accuracy: 0.0)
        }
        // Exact values: 45, −135 (≡ 225), and +20 (not −340).
        XCTAssertEqual(ArrowRotation().update(45.0 - 0.0), 45.0, accuracy: 1e-9)
        XCTAssertEqual(ArrowRotation().update(315.0 - 90.0), -135.0, accuracy: 1e-9)
        XCTAssertEqual(ArrowRotation().update(10.0 - 350.0), 20.0, accuracy: 1e-9)
        XCTAssertEqual(ArrowRotation().update(Geo.arrowDeg(350.0, 10.0)), 20.0, accuracy: 1e-9)
    }

    func testArrowRotationAlwaysTurnsTheShortWay() {
        var rnd = KotlinXorWowRandom(42)
        let acc = ArrowRotation(rnd.nextDouble(-720.0, 720.0))
        for _ in 0..<5000 {
            let target = rnd.nextDouble(-1080.0, 1080.0)
            let before = acc.value
            let after = acc.update(target)
            let delta = after - before
            XCTAssertTrue(abs(delta) <= 180.0, "delta \(delta)")
            XCTAssertEqual(acc.lastDelta, delta, accuracy: 1e-9)
            XCTAssertEqual(Geo.shortestTurn(after, target), 0.0, accuracy: 1e-6, "lands on the target mod 360")
        }
        // Spinning steadily clockwise keeps accumulating instead of snapping back at 360.
        let spin = ArrowRotation()
        for deg in stride(from: 0, through: 1080, by: 10) { spin.update(Double(deg % 360)) }
        XCTAssertEqual(spin.value, 1080.0, accuracy: 1e-9)
    }

    func testArrowRotationEaseAndGuards() {
        let acc = ArrowRotation(350.0)
        acc.ease(10.0, 0.5) // shortest turn is +20, half of it
        XCTAssertEqual(acc.value, 360.0, accuracy: 1e-9)
        XCTAssertEqual(acc.lastDelta, 10.0, accuracy: 1e-9)
        acc.update(Double.nan)
        XCTAssertEqual(acc.value, 360.0, accuracy: 0.0)
        XCTAssertEqual(acc.lastDelta, 0.0, accuracy: 0.0)
        acc.ease(Double.infinity, 1.0)
        XCTAssertEqual(acc.value, 360.0, accuracy: 0.0)
        acc.reset(90.0)
        XCTAssertEqual(acc.value, 90.0, accuracy: 0.0)
        XCTAssertEqual(ArrowRotation(Double.nan).value, 0.0, accuracy: 0.0)
        // ease(t, 1.0) behaves like update(t)
        let a = ArrowRotation(10.0)
        let b = ArrowRotation(10.0)
        XCTAssertEqual(b.ease(250.0, 1.0), a.update(250.0), accuracy: 1e-9)
    }

    // ---------------------------------------------------------------- iOS additions (no Kotlin twin)

    /// Kotlin's `declinationDeg` falls back to SLC_DECLINATION_DEG when GeomagneticField gives
    /// something unusable; the same rules apply to whatever source the app installs.
    func testDeclinationSourcesAndFallback() {
        let at = (lat: 40.767, lng: -111.895, alt: 1300.0, ms: Int64(1_794_000_000_000))
        func decl(_ s: any DeclinationSource) -> Double { Geo.declinationDeg(at.lat, at.lng, at.alt, at.ms, source: s) }
        XCTAssertEqual(Geo.SLC_DECLINATION_DEG, 10.4)
        XCTAssertEqual(decl(NoDeclinationModel()), Geo.SLC_DECLINATION_DEG)
        XCTAssertEqual(decl(FixedDeclination(10.1)), 10.1)
        XCTAssertEqual(decl(FixedDeclination(-3.0)), -3.0)
        XCTAssertEqual(decl(FixedDeclination(180.0)), 180.0)
        XCTAssertEqual(decl(FixedDeclination(-180.0)), -180.0)
        XCTAssertEqual(decl(FixedDeclination(180.5)), Geo.SLC_DECLINATION_DEG)
        XCTAssertEqual(decl(FixedDeclination(Double.nan)), Geo.SLC_DECLINATION_DEG)
        XCTAssertEqual(decl(FixedDeclination(-Double.infinity)), Geo.SLC_DECLINATION_DEG)
        // The default source is "no model" (the app may install another one).
        XCTAssertTrue(Geo.declinationSource is NoDeclinationModel)
        XCTAssertEqual(Geo.declinationDeg(at.lat, at.lng, at.alt, at.ms), Geo.SLC_DECLINATION_DEG)
        // Usable where Kotlin passes `Geo::declinationDeg`.
        let f: (Double, Double, Double, Int64) -> Double = Geo.declinationDeg
        XCTAssertEqual(f(at.lat, at.lng, at.alt, at.ms), Geo.SLC_DECLINATION_DEG)
    }

    func testObservedDeclination() {
        let o = ObservedDeclination()
        XCTAssertNil(o.lastDeclinationDeg)
        XCTAssertEqual(Geo.declinationDeg(0, 0, 0, 0, source: o), Geo.SLC_DECLINATION_DEG) // nothing seen yet
        o.record(trueHeading: 5.0, magneticHeading: 355.0, headingAccuracy: 10.0) // across north: +10
        XCTAssertEqual(o.lastDeclinationDeg!, 10.0, accuracy: 1e-9)
        XCTAssertEqual(Geo.declinationDeg(0, 0, 0, 0, source: o), 10.0, accuracy: 1e-9)
        o.record(trueHeading: -1.0, magneticHeading: 100.0, headingAccuracy: 10.0) // no true heading: ignored
        o.record(trueHeading: 120.0, magneticHeading: 100.0, headingAccuracy: -1.0) // invalid reading: ignored
        o.record(trueHeading: 120.0, magneticHeading: Double.nan, headingAccuracy: 5.0) // ignored
        XCTAssertEqual(o.lastDeclinationDeg!, 10.0, accuracy: 1e-9)
        o.record(trueHeading: 97.0, magneticHeading: 100.0, headingAccuracy: 5.0) // west: −3
        XCTAssertEqual(o.lastDeclinationDeg!, -3.0, accuracy: 1e-9)
    }

    /// How the app turns a CLHeading into the true heading Kotlin gets from azimuth + declination.
    func testCompassTrueHeadingFromCoreLocation() {
        // A valid true heading is used as is: the declination is not added a second time.
        XCTAssertEqual(Geo.compassTrueHeading(trueHeading: 350.0, magneticHeading: 340.0, headingAccuracy: 5.0, declinationDeg: 10.4)!, 350.0, accuracy: 0.0)
        XCTAssertEqual(Geo.compassTrueHeading(trueHeading: 0.0, magneticHeading: 349.6, headingAccuracy: 5.0, declinationDeg: 10.4)!, 0.0, accuracy: 0.0)
        XCTAssertEqual(Geo.compassTrueHeading(trueHeading: 360.0, magneticHeading: 349.6, headingAccuracy: 5.0, declinationDeg: 10.4)!, 0.0, accuracy: 0.0)
        // No true heading (−1): magnetic + declination, like Android's trueHeading(azimuth, declination).
        XCTAssertEqual(
            Geo.compassTrueHeading(trueHeading: -1.0, magneticHeading: 340.0, headingAccuracy: 5.0, declinationDeg: 10.0)!,
            Geo.trueHeading(340.0, 10.0), accuracy: 0.0
        )
        XCTAssertEqual(Geo.compassTrueHeading(trueHeading: -1.0, magneticHeading: 355.0, headingAccuracy: 5.0, declinationDeg: 10.0)!, 5.0, accuracy: 1e-9)
        XCTAssertEqual(
            Geo.compassTrueHeading(trueHeading: -1.0, magneticHeading: 0.0, headingAccuracy: 5.0, declinationDeg: Double.nan)!,
            Geo.SLC_DECLINATION_DEG, accuracy: 1e-9
        )
        // Invalid readings give no heading at all.
        XCTAssertNil(Geo.compassTrueHeading(trueHeading: 10.0, magneticHeading: 0.0, headingAccuracy: -1.0, declinationDeg: 10.0))
        XCTAssertNil(Geo.compassTrueHeading(trueHeading: -1.0, magneticHeading: Double.nan, headingAccuracy: 5.0, declinationDeg: 10.0))
        XCTAssertNil(Geo.compassTrueHeading(trueHeading: 10.0, magneticHeading: 0.0, headingAccuracy: Double.nan, declinationDeg: 10.0))
    }

    /// `Geo.javaHypot` / `Geo.javaAtan2` are bit-identical to the JVM's `Math.hypot` / `Math.atan2`
    /// (checked against 200,000 Java results while porting; a sample is pinned here).
    func testJavaMathMatchesJava() {
        for (x, y, hypot, atan2) in Self.MATH_VECTORS {
            let dx = Double(bitPattern: x), dy = Double(bitPattern: y)
            let h = Geo.javaHypot(dx, dy)
            if Double(bitPattern: hypot).isNaN {
                XCTAssertTrue(h.isNaN, "hypot(\(dx), \(dy)) = \(h)")
            } else {
                XCTAssertEqual(h.bitPattern, hypot, "hypot(\(dx), \(dy)) = \(h)")
            }
            let a = Geo.javaAtan2(dx, dy)
            if Double(bitPattern: atan2).isNaN {
                XCTAssertTrue(a.isNaN, "atan2(\(dx), \(dy)) = \(a)")
            } else {
                XCTAssertEqual(a.bitPattern, atan2, "atan2(\(dx), \(dy)) = \(a)")
            }
        }
        XCTAssertEqual(Geo.javaHypot(3, 4), 5.0)
        XCTAssertEqual(Geo.javaHypot(-3, 4), 5.0)
        XCTAssertEqual(Geo.javaHypot(Double.nan, Double.infinity), Double.infinity)
        XCTAssertTrue(Geo.javaHypot(Double.nan, 1).isNaN)
        XCTAssertEqual(Geo.javaAtan2(1, 1), Double.pi / 4)
        XCTAssertEqual(Geo.javaAtan2(-0.0, -1).bitPattern, (-Double.pi).bitPattern)
        XCTAssertEqual(Geo.javaAtan2(-0.0, 1).bitPattern, (-0.0).bitPattern)
    }

    /// The test's random inputs are the Kotlin test's (`kotlin.random.Random(seed)`, values from Kotlin 2.3).
    func testKotlinRandomMatchesKotlin() {
        var r7 = KotlinXorWowRandom(7)
        for expected in Self.RANDOM_7 { XCTAssertEqual(r7.nextDouble(-500.0, 500.0).bitPattern, expected) }
        var r42 = KotlinXorWowRandom(42)
        for expected in Self.RANDOM_42 { XCTAssertEqual(r42.nextDouble(-720.0, 720.0).bitPattern, expected) }
    }

    private static let RANDOM_7: [UInt64] = [
        0x407c98d59b2b1574, 0x4047fc33c891e2f0, 0xc061128ce03e99bc, 0x4077ae33d1357a30, 0xc07dc5259336cc21,
        0xc04a0b478f1b3930, 0x407c367aa4c84184, 0xc0728e2e68ae3ca7, 0xc05c9ee195958eec, 0x40714ab7cc3a67ee,
    ]

    private static let RANDOM_42: [UInt64] = [
        0xc078a1b23ee1b3aa, 0x4082391a3fb460f0, 0xc074a26c4298548c, 0x40852c0bab3faa90, 0xc07c79c47e0fb052,
    ]

    /// (x bits, y bits, Java `Math.hypot(x, y)` bits, Java `Math.atan2(x, y)` bits), from Java 21.
    /// Includes inputs where glibc's hypot / atan2 differ from Java in the last bit.
    private static let MATH_VECTORS: [(UInt64, UInt64, UInt64, UInt64)] = [
        (0x4010000000000000, 0x4014000000000000, 0x40199ccc999fff00, 0x3fe5977a5103ea93),
        (0x4014000000000000, 0x4010000000000000, 0x40199ccc999fff00, 0x3fecac7c57846f9e),
        (0x000012688b70e62b, 0x0000000000000001, 0x000012688b70e62b, 0x3ff921fb54442c3a),
        (0x0000000000000001, 0x01a56e1fc2f8f359, 0x01a56e1fc2f8f359, 0x3b17e43c8800759b),
        (0x7fe1ccf385ebc8a0, 0x7fefffffffffffff, 0x7ff0000000000000, 0x3fe03e9cc33ffaf3),
        (0x7fefffffffffffff, 0x7fe1ccf385ebc8a0, 0x7ff0000000000000, 0x3ff102acf2a42f9f),
        (0x6974e718d7d7625a, 0x16687e92154ef7ac, 0x6974e718d7d7625a, 0x3ff921fb54442d18),
        (0x01a56e1fc2f8f359, 0x01a56e1fc2f8f359, 0x01ae4e8d12762225, 0x3fe921fb54442d18),
        (0x4008000000000000, 0x0000000000000000, 0x4008000000000000, 0x3ff921fb54442d18),
        (0x7ff0000000000000, 0x7ff8000000000000, 0x7ff0000000000000, 0x7ff8000000000000),
        (0x7ff8000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff8000000000000),
        (0x7ff8000000000000, 0x0000000000000000, 0x7ff8000000000000, 0x7ff8000000000000),
        (0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000),
        (0xc01e000000000000, 0x4010000000000000, 0x4021000000000000, 0xbff14b1dd5f90ce1),
        (0x3fc999999999999a, 0x16687e92154ef7ac, 0x3fc999999999999a, 0x3ff921fb54442d18),
        (0x3fb999999999999a, 0x0010000000000000, 0x3fb999999999999a, 0x3ff921fb54442d18),
        (0x7e37e43c8800759c, 0x7e37e43c8800759c, 0x7e40e4d50f99b211, 0x3fe921fb54442d18),
        (0x7fefffffffffffff, 0x7fefffffffffffff, 0x7ff0000000000000, 0x3fe921fb54442d18),
        (0x8000000000000000, 0x000012688b70e62b, 0x000012688b70e62b, 0x8000000000000000),
        (0x7ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x3fe921fb54442d18),
        (0x8000000000000000, 0xc01e000000000000, 0x401e000000000000, 0xc00921fb54442d18),
        (0x0000000000000000, 0xc01e000000000000, 0x401e000000000000, 0x400921fb54442d18),
        (0x7ff0000000000000, 0x4010000000000000, 0x7ff0000000000000, 0x3ff921fb54442d18),
        (0xc01e000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x8000000000000000),
        (0x4010000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x0000000000000000),
        (0x406e920abb0c97fc, 0xc07428a3d3af6a87, 0x40794c69f8e10694, 0x4003f15455c7a4f6),
        (0xc079381cc76685f8, 0x4018e71cd953fc5a, 0x407938e17d6ff461, 0xbff8e2ca2b79775b),
        (0xc078da7f444043f7, 0x40538f2092776879, 0x40795477da36374c, 0xbff6064830579588),
        (0xc075981952e5f030, 0x407627ef8efd806e, 0x407ef04607729b55, 0xbfe8b8c80eff72da),
        (0xc07ce9c1543c18ea, 0x406013eee58ad147, 0x407e0286aad7b923, 0xbff4cb32023e119c),
        (0xc076930ecc9afcf4, 0xc074ad29f77849e8, 0x407e9cc73c662c19, 0xc0027fab5f09af07),
        (0xc068428f5c28f5c3, 0x4076cd1eb851eb85, 0x4079d3b63cb865b0, 0xbfdf4a4b9ece7896),
        (0x407643851eb851ec, 0x4035266666666666, 0x40764d8ea10ba09c, 0x3ff82f12c9953e2e),
        (0x4073d028f5c28f5c, 0xc06f36147ae147ae, 0x4079388f0e2c58fc, 0x4001e755425023ce),
        (0xc07abb3333333333, 0x40638d70a3d70a3d, 0x407c767e71818ce9, 0xbff385deaacf390e),
        (0x4071626666666666, 0x407cfd70a3d70a3d, 0x4080e6c5b113fe1f, 0x3fe1491dcac0f3a5),
        (0x407104cccccccccd, 0x4079f7851eb851ec, 0x407f0c0871f388af, 0x3fe290b3476f5e6a),
        (0xaa9eba78b868fac6, 0xe89f5932faad9990, 0x689f5932faad9990, 0xc00921fb54442d18),
        (0xd8b522a734fa95b4, 0x64bfa31cb0052e10, 0x64bfa31cb0052e10, 0xb3e560b51915acd3),
        (0x8e61e9353d799d18, 0xc3536de97e0b220c, 0x43536de97e0b220c, 0xc00921fb54442d18),
        (0x232b752029bc8392, 0x0e822bf9f4136fdc, 0x232b752029bc8392, 0x3ff921fb54442d18),
        (0x619d0a019096b988, 0xef1a3479651e4190, 0x6f1a3479651e4190, 0x400921fb54442d18),
        (0x18a2dfe946803cf4, 0x43a3e812de05fe60, 0x43a3e812de05fe60, 0x14ee575b0b6964fe),
        (0xc0076eb64a0cd40a, 0xc0076fcd31a0d27c, 0x4010921d7cc2b00e, 0xc002d9ac1a3cbd01),
        (0x3fa39097d3175020, 0x3fa3908e3fa63603, 0x3fabab319c420e84, 0x3fe92203290cab86),
        (0xc00eb72678b5fdeb, 0xc00eb659a0efce1b, 0x4015b7cdd23ebfdc, 0xc002d961d1bdac5e),
        (0x3fb40b7a8d45afc0, 0x3fb40991068eb5b1, 0x3fbc57a7a0128b0e, 0x3fe92382259da296),
        (0x4004b9270b7f7194, 0x4004b8149cb52f15, 0x400d4ddc5443fcd0, 0x3fe922cf3c09694f),
        (0x3ff397cb0661cc19, 0x3ff39932c3f060ea, 0x3ffbb6657408a3eb, 0x3fe920d5994dacd8),
        (0x7e37e43c8800759c, 0xc01e000000000000, 0x7e37e43c8800759c, 0x3ff921fb54442d19),
        (0x4008000000000000, 0x3fc999999999999a, 0x40080da360d9e625, 0x3ff811518cde39a6),
        (0xc073d256eb06683d, 0xc05e50d864e09736, 0x4075389e48cf2f62, 0xbffef9dce4c49722),
        (0xc07a5947ae147ae1, 0xc079a40000000000, 0x408261fa3fcd16d9, 0xc002bd97d61370bd),
        (0xc07470a3d70a3d71, 0x406bb4cccccccccd, 0x4078b1314629f905, 0xbfef348865822491),
        (0xc0646af7031f7092, 0xc0715385c18eacd9, 0x40741c37d93a4025, 0xc004df84cecb9ffc),
        (0x40507839db682b59, 0xc06a63c769748af7, 0x406ba50dc223a553, 0x4006b6855c96dc65),
        (0x48779aeb5507c964, 0xacf6ae2c7ca4b6b0, 0x48779aeb5507c964, 0x3ff921fb54442d19),
        (0xc00b209ccf8a7e74, 0xc00b1ea36faa0c11, 0x40132de27c9fa02e, 0xc002d931f7b355aa),
        (0xc0351fa66d69832f, 0xc07ebe2c82cacc1e, 0x407ec56d78c5fd0c, 0xc008ca1609de060a),
        (0x5adacc327e4c0724, 0xcc2aa3af025b18ac, 0x5adacc327e4c0724, 0x3ff921fb54442d19),
        (0x2e98264e07bd96f8, 0x8e5b69c68900cbb0, 0x2e98264e07bd96f8, 0x3ff921fb54442d19),
        (0x407d5cf5c28f5c29, 0x407906b851eb851f, 0x40834a639e073f5a, 0x3febadd003dc59a4),
        (0xc00b2f2af69dcafc, 0xc00b318da6e42020, 0x401339b7de48d79e, 0xc002d9d65734fd4e),
        (0xc057fd49ff2aec8c, 0xc07a4390044db320, 0x407af0a1545a2bed, 0xc007563488d3f424),
        (0xc076ce12fdd16f9b, 0xc04bdf470bb66b1d, 0x407711cfd2886a12, 0xbffb8ef1fdb6b03e),
    ]
}

/// Kotlin's `kotlin.random.Random(seed)` (XorWowRandom, Marsaglia's xorwow) with `nextDouble`
/// and `nextDouble(from, until)`, so the property tests draw the same inputs as the Kotlin tests.
private struct KotlinXorWowRandom {
    private var x: Int32
    private var y: Int32
    private var z: Int32
    private var w: Int32
    private var v: Int32
    private var addend: Int32

    init(_ seed: Int32) {
        let seed1 = seed
        let seed2 = seed >> 31
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        precondition((x | y | z | w | v) != 0, "Initial state must have at least one non-zero element.")
        for _ in 0..<64 { _ = nextInt() }
    }

    mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362_437
        return t &+ addend
    }

    /// `nextInt().takeUpperBits(bitCount)`.
    private mutating func nextBits(_ bitCount: Int32) -> Int32 {
        let i = nextInt()
        return Int32(bitPattern: UInt32(bitPattern: i) >> UInt32(32 - bitCount)) & ((-bitCount) >> 31)
    }

    mutating func nextDouble() -> Double {
        let hi26 = nextBits(26)
        let low27 = nextBits(27)
        return Double((Int64(hi26) << 27) + Int64(low27)) / Double(Int64(1) << 53)
    }

    mutating func nextDouble(_ from: Double, _ until: Double) -> Double {
        precondition(until > from)
        let size = until - from
        let r: Double
        if size.isInfinite && from.isFinite && until.isFinite {
            let r1 = nextDouble() * (until / 2 - from / 2)
            r = from + r1 + r1
        } else {
            r = from + nextDouble() * size
        }
        return r >= until ? until.nextDown : r
    }
}
