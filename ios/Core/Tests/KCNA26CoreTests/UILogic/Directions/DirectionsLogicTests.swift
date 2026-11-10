import Foundation
import XCTest
@testable import KCNA26Core

final class DirectionsLogicTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var room251: Room = repo.room("251AC")!
    private lazy var target: PointXY = room251.pos!
    private lazy var router = Router(repo)
    private lazy var planner = RoutePlanner(router, FromOptions.from(router, repo.wayfinding))
    private lazy var outside: Fix = {
        let it = TestData.vectors.compass.first!
        let p = Geo.toLocal(it.lat, it.lng, repo.wayfinding.origin)
        return Fix(it.lat, it.lng, p.x, p.y, 8.0)
    }()

    /// A fix `dist` metres due south of the room.
    private func southOf(_ dist: Double, _ acc: Double) -> Fix { Fix(0.0, 0.0, target.x, target.y - dist, acc) }

    // ---------------------------------------------------------------- readout

    func testNoFix_textsPerState() {
        let searching = DirectionsLogic.readout(target, 2, nil, .searching)
        XCTAssertEqual("Finding you…", searching.headline)
        XCTAssertEqual("Finding you…", searching.line)
        XCTAssertEqual("Hold on a moment.", searching.detail)
        XCTAssertFalse(searching.hasFix)
        XCTAssertNil(searching.accuracy)

        let noFix = DirectionsLogic.readout(target, 2, nil, .noFix)
        XCTAssertEqual("No GPS fix yet", noFix.headline)
        XCTAssertEqual("Indoors this can take a minute. A window or doorway helps.", noFix.detail)

        let denied = DirectionsLogic.readout(target, 2, nil, .permissionDenied)
        XCTAssertEqual("Location is off", denied.headline)
        // Platform difference: Kotlin says "… in Android Settings …"; the iOS text names the iOS Settings app.
        XCTAssertEqual("Allow location for this app in Settings to see distance and direction.", denied.detail)

        let deviceOff = DirectionsLogic.readout(target, 2, nil, .deviceOff)
        XCTAssertEqual("Location is off", deviceOff.headline)
        XCTAssertNil(deviceOff.distance)
    }

    func testFarAway_distanceDirectionAccuracy() {
        let r = DirectionsLogic.readout(target, 2, southOf(123.0, 12.4), .searching)
        XCTAssertEqual("120 m north", r.headline)
        XCTAssertEqual("120 m north · ±12 m", r.line)
        XCTAssertEqual("120 m", r.distance)
        XCTAssertEqual("north", r.direction)
        XCTAssertEqual("±12 m", r.accuracy)
        XCTAssertTrue(r.hasFix)
        // No compass-arrow sentence any more: the floor instruction and the map say the rest.
        XCTAssertNil(r.detail)
        XCTAssertNil(r.weakGps)
        XCTAssertFalse(r.here)
    }

    func testNorthEastExample() {
        // 120 m away at a bearing of 45°: the redesign's "120 m north-east · ±12 m".
        let d = 120.0 / 2.0.squareRoot()
        let fix = Fix(0.0, 0.0, target.x - d, target.y - d, 12.0)
        let r = DirectionsLogic.readout(target, 2, fix, .searching)
        XCTAssertEqual("120 m north-east", r.headline)
        XCTAssertEqual("±12 m", r.accuracy)
        XCTAssertEqual("120 m north-east · ±12 m", r.line)
    }

    func testHere_withinMax15mOr60PercentOfAccuracy() {
        let r = DirectionsLogic.readout(target, 2, southOf(14.0, 10.0), .searching)
        XCTAssertTrue(r.here)
        XCTAssertEqual("You’re about here", r.headline)
        XCTAssertEqual("You’re about here · ±10 m", r.line)
        XCTAssertEqual("The room is on Level 2; the steps below get you to the right floor.", r.detail)
        XCTAssertNil(r.distance)
        XCTAssertEqual("±10 m", r.accuracy)

        XCTAssertFalse(DirectionsLogic.readout(target, 2, southOf(16.0, 10.0), .searching).here)
        // 0.6 × 40 m = 24 m.
        XCTAssertTrue(DirectionsLogic.readout(target, 2, southOf(20.0, 40.0), .searching).here)
        XCTAssertFalse(DirectionsLogic.readout(target, 2, southOf(25.0, 40.0), .searching).here)
    }

    func testWeakGps_above50m() {
        XCTAssertNil(DirectionsLogic.readout(target, 2, southOf(200.0, 50.0), .searching).weakGps)
        let weak = DirectionsLogic.readout(target, 2, southOf(200.0, 65.0), .searching)
        XCTAssertEqual("GPS is weak indoors: follow the steps.", weak.weakGps)
        XCTAssertEqual("±65 m", weak.accuracy)
    }

    func testAccuracyRounding() {
        XCTAssertEqual("±12 m", DirectionsLogic.accuracyText(12.4))
        XCTAssertEqual("±13 m", DirectionsLogic.accuracyText(12.5))
        XCTAssertEqual("±0 m", DirectionsLogic.accuracyText(-1.0))
    }

    func testReadoutDistancesFromTheTestVectors() throws {
        for v in TestData.vectors.compass {
            let room = try XCTUnwrap(repo.room(v.room))
            let p = Geo.toLocal(v.lat, v.lng, repo.wayfinding.origin)
            let r = DirectionsLogic.readout(try XCTUnwrap(room.pos), try XCTUnwrap(room.level), Fix(v.lat, v.lng, p.x, p.y, 10.0), .searching)
            let expected = Geo.r10(v.expectDistanceM)
            let shown = try XCTUnwrap(Int(try XCTUnwrap(r.distance).removeSuffix(" m")))
            XCTAssertTrue(abs(shown - expected) <= 10, "\(v.where): \(shown) vs \(expected)")
        }
    }

    func testNoArrowOrGoogleMapsWording() {
        let readouts = [
            DirectionsLogic.readout(target, 2, nil, .searching),
            DirectionsLogic.readout(target, 2, southOf(123.0, 12.0), .searching),
            DirectionsLogic.readout(target, 2, southOf(5.0, 12.0), .searching),
            DirectionsLogic.readout(target, 2, southOf(300.0, 80.0), .searching),
        ]
        var texts: [String] = readouts.flatMap { [$0.line, $0.detail, $0.weakGps].compactMap { $0 } }
        texts += [DirectionsText.MAP_NOTE, DirectionsText.REFIT, DirectionsText.mapDescription("SP", 2)]
        for t in texts {
            XCTAssertFalse(t.lowercased().contains("arrow"), t)
            XCTAssertFalse(t.lowercased().contains("google"), t)
        }
        XCTAssertEqual("Map: destination on Hyatt level 4", DirectionsText.mapDescription("HY", 4))
    }

    // ---------------------------------------------------------------- floor (engine's FloorReminder)

    func testFloorReminder_promptExample() {
        // Spec: "Level 2 · Salt Palace · 251 A–C" and "Room is on Level 2: take the North Foyer escalator up".
        let r = router.route(.entrance("E200S"), "251AC")
        let f = FloorReminder.of(room251, r)
        XCTAssertEqual("Level 2 · Salt Palace · 251 A–C", f.headline)
        XCTAssertEqual("Level 2", f.levelLabel)
        XCTAssertEqual("Salt Palace · 251 A–C", f.buildingAndRoom)
        XCTAssertEqual("Room is on Level 2: take the North Foyer escalator up", f.instruction)
        XCTAssertEqual(StepKind.up, f.direction)
    }

    func testFloorReminder_withoutALevelChange() {
        // From the West Temple entrance you come in on Level 2 already.
        let f = FloorReminder.of(room251, router.route(.entrance("EWT"), "251AC"))
        XCTAssertEqual("Room is on Level 2", f.instruction)
        XCTAssertNil(f.direction)
    }

    func testFloorReminder_followsTheLivePlan() throws {
        let p = planner.plan("LIVE", "RA", outside)
        let f = FloorReminder.of(try XCTUnwrap(repo.room("RA")), p.route)
        XCTAssertEqual("Level 4 · Hyatt Regency · Regency Ballroom A", f.headline)
        XCTAssertTrue(try XCTUnwrap(f.instruction).hasPrefix("Room is on Level 4"))
    }

    // ---------------------------------------------------------------- From picker

    func testFromOptions_likeTheWeb() {
        let o = FromOptions.from(router, repo.wayfinding)
        XCTAssertEqual(SettingsStore.FROM_LIVE, o.live.key)
        XCTAssertEqual("My location (GPS)", o.live.label)
        XCTAssertEqual(["E200S", "EWT", "EHY", "E200W"], o.entrances.map(\.key))
        XCTAssertEqual("200 South entrance (badge pick-up)", o.label("E200S"))
        XCTAssertEqual("Hyatt lobby", o.label("EHY"))
        // Sorted with String.localeCompare in the web; checked against node's output.
        let expected = [
            "250 A–C", "250 D–F", "251 A–C", "251 D–F", "253 A", "253 B", "254", "255 A", "255 BC", "255 D",
            "255 EF", "Capitol Reef", "Cosmic Canyon stage, Hall 5", "Demo Theater, Hall 1", "Grand Ballroom ACE",
            "Grand Ballroom BDF", "Grand Ballroom GI", "Grand Ballroom H", "Grand Ballroom J", "Hall DE",
            "Hyatt lobby", "Network Nook, Hall 1", "North Grand Ballroom Foyer", "Park City",
            "Project Pavilion, Hall 5", "Regency Ballroom A", "Regency Ballroom B", "Regency Ballroom B–D",
            "Regency Ballroom CD", "Room 151", "Salt Lake Ballroom C", "Salt Lake Ballroom DE",
            "Salt Lake Foyer South", "Showcase halls", "Starlight Summit stage, Hall B", "Upper Concourse",
            "Upper Mezzanine",
        ]
        XCTAssertEqual(expected, o.rooms.map(\.label))
        let codes = Set(o.rooms.map(\.key))
        XCTAssertFalse(codes.contains("OFF"))
        XCTAssertFalse(codes.contains("REG"))
        XCTAssertFalse(codes.contains("COAT"))
    }

    func testFromValidation() {
        let o = FromOptions.from(router, repo.wayfinding)
        XCTAssertEqual("LIVE", o.validate("LIVE"))
        XCTAssertEqual("EWT", o.validate("EWT"))
        XCTAssertEqual("251AC", o.validate("251AC"))
        XCTAssertEqual("E200S", o.validate("REG"))
        XCTAssertEqual("E200S", o.validate("OFF"))
        XCTAssertEqual("E200S", o.validate("nope"))
    }

    // ---------------------------------------------------------------- route plan

    func testRouteFrom_mapping() {
        XCTAssertEqual(RouteFrom.entrance("E200S"), planner.routeFrom("LIVE", nil))
        XCTAssertEqual(RouteFrom.myLocation(outside.x, outside.y, 8.0), planner.routeFrom("LIVE", outside))
        XCTAssertEqual(RouteFrom.entrance("EHY"), planner.routeFrom("EHY", outside))
        XCTAssertEqual(RouteFrom.room("DE"), planner.routeFrom("DE", outside))
    }

    func testPlan_myLocationWithoutAFix_fallsBackTo200South() throws {
        let p = planner.plan("LIVE", "251AC", nil)
        XCTAssertEqual("LIVE", p.from)
        XCTAssertTrue(p.showFallbackNote)
        XCTAssertFalse(try XCTUnwrap(p.route).live)
        XCTAssertNil(p.startKey)
    }

    func testPlan_myLocationWithAFix_isLive() throws {
        let p = planner.plan("LIVE", "251AC", outside)
        XCTAssertTrue(try XCTUnwrap(p.route).live)
        XCTAssertFalse(p.showFallbackNote)
        XCTAssertEqual(router.myLocationStart(outside.x, outside.y).key, p.startKey)
    }

    func testPlan_entranceAndInvalidFrom() throws {
        let ewt = planner.plan("EWT", "255EF", outside)
        XCTAssertEqual("EWT", ewt.from)
        XCTAssertFalse(try XCTUnwrap(ewt.route).live)
        XCTAssertFalse(ewt.showFallbackNote)
        XCTAssertEqual("E200S", planner.plan("REG", "251AC", nil).from)
        XCTAssertNil(planner.plan("LIVE", "OFF", outside).route)
    }

    func testPlanKey_onlyChangesWithTheStartPoint() {
        XCTAssertEqual("EWT", planner.planKey("EWT", outside))
        XCTAssertEqual("E200S", planner.planKey("bogus", outside))
        XCTAssertEqual("LIVE:none", planner.planKey("LIVE", nil))
        let a = planner.planKey("LIVE", outside)
        let moved = Fix(outside.lat, outside.lng, outside.x + 1.0, outside.y, outside.accuracyM, outside.altitudeM) // outside.copy(x = x + 1)
        let b = planner.planKey("LIVE", moved)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual("LIVE:none", a)
    }

    // ---------------------------------------------------------------- iOS additions

    /// Kotlin DirectionsScreen's status rule, and its Core Location form.
    func testIOS_locStatusRules() {
        XCTAssertEqual(.permissionDenied, LocStatus.of(permissionGranted: false, permissionDenied: true, deviceOff: true, noFix: true))
        XCTAssertEqual(.deviceOff, LocStatus.of(permissionGranted: true, permissionDenied: false, deviceOff: true, noFix: true))
        XCTAssertEqual(.noFix, LocStatus.of(permissionGranted: true, permissionDenied: false, deviceOff: false, noFix: true))
        XCTAssertEqual(.searching, LocStatus.of(permissionGranted: false, permissionDenied: false, deviceOff: true, noFix: false))
        XCTAssertEqual(.searching, LocStatus.of(permissionGranted: true, permissionDenied: false, deviceOff: false, noFix: false))

        XCTAssertEqual(.permissionDenied, LocationTracker.locStatus(.denied, deviceLocationOff: false, noFix: false))
        // Core Location reports .denied while Location Services are off: that is the switch's fault.
        XCTAssertEqual(.deviceOff, LocationTracker.locStatus(.denied, deviceLocationOff: true, noFix: false))
        XCTAssertEqual(.deviceOff, LocationTracker.locStatus(.authorized, deviceLocationOff: true, noFix: true))
        XCTAssertEqual(.noFix, LocationTracker.locStatus(.authorized, deviceLocationOff: false, noFix: true))
        XCTAssertEqual(.searching, LocationTracker.locStatus(.notDetermined, deviceLocationOff: false, noFix: false))
        XCTAssertTrue(LocationTracker.hasLocationPermission(.authorized))
        XCTAssertFalse(LocationTracker.hasLocationPermission(.notDetermined))
    }

    /// `CLLocation` validity and staleness rules.
    func testIOS_locationReadingRules() {
        func reading(acc: Double = 10.0, vAcc: Double = 3.0, age: Double = 0.5, lat: Double = 40.765) -> LocationReading {
            LocationReading(latitude: lat, longitude: -111.895, horizontalAccuracy: acc, altitude: 1300.0, verticalAccuracy: vAcc, ageSeconds: age)
        }
        XCTAssertTrue(reading().isUsable)
        XCTAssertEqual(10.0, reading().accuracyM)
        XCTAssertEqual(1300.0, reading().altitudeM)
        XCTAssertNil(reading(vAcc: -1.0).altitudeM) // invalid altitude
        XCTAssertFalse(reading(acc: -1.0).isUsable) // invalid coordinate
        XCTAssertFalse(reading(acc: .nan).isUsable)
        XCTAssertFalse(reading(lat: .nan).isUsable)
        XCTAssertTrue(reading(age: 60.0).isUsable)
        XCTAssertFalse(reading(age: 60.001).isUsable) // a cached fix from more than a minute ago
        XCTAssertTrue(reading(age: -2.0).isUsable) // clock skew
        XCTAssertEqual(0.0, reading(acc: 0.0).accuracyM)
    }
}
