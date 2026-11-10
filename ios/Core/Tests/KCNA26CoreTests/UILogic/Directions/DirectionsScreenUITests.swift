import Foundation
import XCTest
@testable import KCNA26Core

/// The Directions views' inline rules (DirectionsScreen+UI.swift): Kotlin DirectionsScreen.kt,
/// DirectionsReadout.kt, RouteViews.kt and VenueMap.kt compute these inside composables.
final class DirectionsScreenUITests: XCTestCase {
    private let repo = TestData.repo
    private lazy var router = Router(repo)
    private lazy var options = FromOptions.from(router, repo.wayfinding)
    private lazy var room251: Room = repo.room("251AC")!
    private lazy var target: PointXY = room251.pos!

    /// "The Future of Kubernetes Eviction and Node Lifecycle" (Wed 5:00–5:30 PM, 251 A–C).
    private lazy var evictionTalk: Session = repo.session("1289660")!

    /// A fix `dist` metres due south of the room.
    private func southOf(_ dist: Double, _ acc: Double) -> Fix { Fix(0.0, 0.0, target.x, target.y - dist, acc) }

    /// `s` in another room.
    private func moved(_ s: Session, to room: String) -> Session {
        Session(
            id: s.id, event: s.event, day: s.day, start: s.start, end: s.end, endIsEstimate: s.endIsEstimate,
            room: room, title: s.title, speakers: s.speakers, note: s.note, category: s.category, group: s.group,
            precomputedIsMine: s.precomputedIsMine, precomputedHasAnthropic: s.precomputedHasAnthropic,
            officialUrl: s.officialUrl, description: s.description, slidesUrl: s.slidesUrl
        )
    }

    // ---------------------------------------------------------------- top bar

    func testTopBarLabel_dayAndTime() {
        XCTAssertEqual("Directions · Wed 5:00–5:30 PM", DirectionsScreenUI.topBarLabel(repo, evictionTalk))
        XCTAssertEqual("Directions", DirectionsScreenUI.topBarLabel(repo, nil))
        // A day the data doesn't know: just the title.
        let s = evictionTalk
        let lost = Session(
            id: s.id, event: s.event, day: "nope", start: s.start, end: s.end, endIsEstimate: s.endIsEstimate,
            room: s.room, title: s.title, speakers: s.speakers, note: s.note, category: s.category, group: s.group,
            precomputedIsMine: s.precomputedIsMine, precomputedHasAnthropic: s.precomputedHasAnthropic,
            officialUrl: s.officialUrl, description: s.description, slidesUrl: s.slidesUrl
        )
        XCTAssertEqual("Directions", DirectionsScreenUI.topBarLabel(repo, lost))
    }

    func testTitle_unknownSession() {
        XCTAssertEqual("The Future of Kubernetes Eviction and Node Lifecycle", DirectionsScreenUI.title(evictionTalk))
        XCTAssertEqual("Unknown session", DirectionsScreenUI.title(nil))
    }

    // ---------------------------------------------------------------- live or unavailable

    func testLive_needsSessionRoomAndTarget() throws {
        let live = try XCTUnwrap(DirectionsScreenUI.live(evictionTalk, room251, target))
        XCTAssertEqual("251AC", live.room.code)
        XCTAssertEqual(target, live.target)
        XCTAssertEqual(2, live.level)
        XCTAssertNil(DirectionsScreenUI.live(nil, room251, target))
        XCTAssertNil(DirectionsScreenUI.live(evictionTalk, nil, target))
        XCTAssertNil(DirectionsScreenUI.live(evictionTalk, room251, nil))
        XCTAssertNil(DirectionsScreenUI.live(evictionTalk, repo.room("OFF"), nil))
    }

    func testUnavailableText_offSiteOrNoPosition() throws {
        let off = try XCTUnwrap(repo.sessions.first { $0.room == "OFF" })
        XCTAssertEqual(
            "Off-site event. The official listing has the address and registration details.",
            DirectionsScreenUI.unavailableText(off)
        )
        XCTAssertEqual("No map position for this room.", DirectionsScreenUI.unavailableText(moved(evictionTalk, to: "NOWHERE")))
    }

    func testMapPoints_routeElseTheRoom() throws {
        let route = try XCTUnwrap(router.route(.entrance("E200S"), "251AC"))
        XCTAssertEqual(route.points, DirectionsScreenUI.mapPoints(route, room251))
        XCTAssertEqual([target], DirectionsScreenUI.mapPoints(nil, room251))
        XCTAssertEqual([], DirectionsScreenUI.mapPoints(nil, try XCTUnwrap(repo.room("OFF"))))
    }

    func testSelectedFrom_planElseValidatedSetting() {
        let plan = RoutePlan(from: "EWT", route: nil, summary: "", showFallbackNote: false, startKey: nil)
        XCTAssertEqual("EWT", DirectionsScreenUI.selectedFrom(plan, options, "LIVE"))
        XCTAssertEqual("LIVE", DirectionsScreenUI.selectedFrom(nil, options, "LIVE"))
        XCTAssertEqual("251AC", DirectionsScreenUI.selectedFrom(nil, options, "251AC"))
        XCTAssertEqual("E200S", DirectionsScreenUI.selectedFrom(nil, options, "OFF"))
        XCTAssertEqual("E200S", DirectionsScreenUI.selectedFrom(nil, options, "bogus"))
    }

    // ---------------------------------------------------------------- readout

    func testLocationAction_onlyWithoutAFix() {
        let denied = DirectionsLogic.readout(target, 2, nil, .permissionDenied)
        XCTAssertEqual(.allowLocation, DirectionsScreenUI.locationAction(denied, .permissionDenied))
        XCTAssertEqual("Allow location", DirectionsScreenUI.LocationAction.allowLocation.label)

        let off = DirectionsLogic.readout(target, 2, nil, .deviceOff)
        XCTAssertEqual(.turnOnLocation, DirectionsScreenUI.locationAction(off, .deviceOff))
        XCTAssertEqual("Turn on location", DirectionsScreenUI.LocationAction.turnOnLocation.label)

        XCTAssertNil(DirectionsScreenUI.locationAction(DirectionsLogic.readout(target, 2, nil, .searching), .searching))
        XCTAssertNil(DirectionsScreenUI.locationAction(DirectionsLogic.readout(target, 2, nil, .noFix), .noFix))
        // A fix wins over any status.
        let fixed = DirectionsLogic.readout(target, 2, southOf(120, 12), .permissionDenied)
        XCTAssertNil(DirectionsScreenUI.locationAction(fixed, .permissionDenied))
    }

    func testReadoutRuns_colours() {
        let far = DirectionsLogic.readout(target, 2, southOf(120, 12), .searching)
        XCTAssertEqual(
            [TextRun("120 M NORTH", role: .ink), TextRun(" · ", role: .muted), TextRun("±12 M", role: .muted)],
            DirectionsScreenUI.readoutRuns(far)
        )
        XCTAssertEqual("120 m north · ±12 m", far.line)
        XCTAssertEqual(32.0, DirectionsScreenUI.readoutFontSize(far))

        let weak = DirectionsLogic.readout(target, 2, southOf(300, 80), .searching)
        XCTAssertEqual(TextRun("±80 M", role: .note), DirectionsScreenUI.readoutRuns(weak).last)

        let here = DirectionsLogic.readout(target, 2, southOf(5, 10), .searching)
        XCTAssertEqual(
            [TextRun("YOU’RE ABOUT HERE", role: .you), TextRun(" · ", role: .muted), TextRun("±10 M", role: .muted)],
            DirectionsScreenUI.readoutRuns(here)
        )
        XCTAssertEqual(.you, DirectionsScreenUI.detailRole(here))
        XCTAssertEqual(.muted, DirectionsScreenUI.detailRole(far))

        let finding = DirectionsLogic.readout(target, 2, nil, .searching)
        XCTAssertEqual([TextRun("FINDING YOU…", role: .ink)], DirectionsScreenUI.readoutRuns(finding))
        XCTAssertEqual(28.0, DirectionsScreenUI.readoutFontSize(finding))
        XCTAssertEqual(.muted, DirectionsScreenUI.detailRole(finding))
    }

    func testShowsFloorInstruction_hidesTheRepeatAboutHere() {
        let plain = FloorReminder(level: 2, building: "Salt Palace", roomName: "251 A–C", action: nil)
        let up = FloorReminder(level: 2, building: "Salt Palace", roomName: "251 A–C", action: "take the North Foyer escalator up", direction: .up, hops: 1)
        let here = DirectionsLogic.readout(target, 2, southOf(5, 10), .searching)
        let far = DirectionsLogic.readout(target, 2, southOf(120, 12), .searching)
        let finding = DirectionsLogic.readout(target, 2, nil, .searching)
        XCTAssertFalse(DirectionsScreenUI.showsFloorInstruction(here, plain))
        XCTAssertTrue(DirectionsScreenUI.showsFloorInstruction(here, up))
        XCTAssertTrue(DirectionsScreenUI.showsFloorInstruction(far, plain))
        XCTAssertTrue(DirectionsScreenUI.showsFloorInstruction(finding, plain))
    }

    // ---------------------------------------------------------------- floor headline

    func testHeadline_levelInPinkAndNoBreakBeforeShortTails() {
        let f = FloorReminder.of(room251, router.route(.entrance("E200S"), "251AC"))
        XCTAssertEqual("Salt Palace · 251\u{00A0}A–C", DirectionsScreenUI.headlineRest(f))
        XCTAssertEqual(
            [TextRun("LEVEL 2", role: .you), TextRun(" · "), TextRun("SALT PALACE · 251\u{00A0}A–C")],
            DirectionsScreenUI.headlineRuns(f)
        )
        XCTAssertEqual("Level 2 · Salt Palace · 251 A–C", f.headline) // what VoiceOver reads

        let room = FloorReminder(level: 1, building: "Salt Palace", roomName: "Room 151", action: nil)
        XCTAssertEqual("Salt Palace · Room\u{00A0}151", DirectionsScreenUI.headlineRest(room))
        // A short word before " · " keeps its space too; long tails and single words are left alone.
        let mid = FloorReminder(level: 1, building: "Hall DE", roomName: "Grand Ballroom", action: nil)
        XCTAssertEqual("Hall\u{00A0}DE · Grand Ballroom", DirectionsScreenUI.headlineRest(mid))
        let ra = FloorReminder.of(try! XCTUnwrap(repo.room("RA")), nil)
        XCTAssertEqual("Hyatt Regency · Regency Ballroom\u{00A0}A", DirectionsScreenUI.headlineRest(ra))
    }

    func testHeadline_withoutALevelOrBuilding() {
        let off = FloorReminder(level: nil, building: nil, roomName: "Off-site", action: nil)
        XCTAssertEqual([TextRun("OFF-SITE")], DirectionsScreenUI.headlineRuns(off))
        let noRest = FloorReminder(level: 3, building: nil, roomName: "", action: nil)
        XCTAssertEqual([TextRun("LEVEL 3", role: .you), TextRun("")], DirectionsScreenUI.headlineRuns(noRest))
    }

    // ---------------------------------------------------------------- From picker

    func testNearestDetails_distanceAndLevel() throws {
        let e200s = try XCTUnwrap(options.entrances.first { $0.key == "E200S" })
        let item = FromMenuItem(e200s, 42.0)
        XCTAssertEqual("40 m · L1", DirectionsScreenUI.nearestDetails(item))
        XCTAssertEqual("40 m, Level 1", DirectionsScreenUI.nearestDetailsDescription(item))

        let grouped = FromMenuItem(e200s)
        XCTAssertEqual("L1", DirectionsScreenUI.nearestDetails(grouped))
        XCTAssertEqual("Level 1", DirectionsScreenUI.nearestDetailsDescription(grouped))

        let live = FromMenuItem(options.live)
        XCTAssertEqual("", DirectionsScreenUI.nearestDetails(live))
        XCTAssertEqual("", DirectionsScreenUI.nearestDetailsDescription(live))
        XCTAssertEqual("1.2 km", DirectionsScreenUI.nearestDetails(FromMenuItem(options.live, 1234.0)))
    }

    func testKindDescription() {
        XCTAssertNil(DirectionsScreenUI.kindDescription(.live))
        XCTAssertEqual("Entrance", DirectionsScreenUI.kindDescription(.entrance))
        XCTAssertEqual("Room", DirectionsScreenUI.kindDescription(.room))
    }

    // ---------------------------------------------------------------- steps

    func testStepIconRoles() {
        XCTAssertTrue(DirectionsScreenUI.stepIconRoles(.up) == (.ink, .bg))
        XCTAssertTrue(DirectionsScreenUI.stepIconRoles(.down) == (.ink, .bg))
        XCTAssertTrue(DirectionsScreenUI.stepIconRoles(.end) == (.you, .onYou))
        XCTAssertTrue(DirectionsScreenUI.stepIconRoles(.start) == (.bg, .ink))
        XCTAssertTrue(DirectionsScreenUI.stepIconRoles(.walk) == (.bg, .ink))
        XCTAssertTrue(DirectionsScreenUI.stepIsBold(.end))
        XCTAssertFalse(StepKind.allCases.filter { $0 != .end }.contains { DirectionsScreenUI.stepIsBold($0) })
    }

    // ---------------------------------------------------------------- layout

    func testCompactMapHeight_halfTheWindowClamped() {
        XCTAssertEqual(422.0, DirectionsScreenUI.compactMapHeight(windowHeight: 844.0))
        XCTAssertEqual(240.0, DirectionsScreenUI.compactMapHeight(windowHeight: 375.0))
        XCTAssertEqual(640.0, DirectionsScreenUI.compactMapHeight(windowHeight: 1366.0))
    }

    // ---------------------------------------------------------------- map

    func testStreetLabels_hideWhenZoomedOut() {
        XCTAssertTrue(DirectionsScreenUI.showsStreetLabels(0.45))
        XCTAssertTrue(DirectionsScreenUI.showsStreetLabels(2.0))
        XCTAssertFalse(DirectionsScreenUI.showsStreetLabels(0.449))
    }

    func testZoneAndHyattLabels_needRoom() {
        // A 100 × 40 m zone at 1 pt/m holds a 60 × 15 pt label (+6 pt each way)...
        XCTAssertTrue(DirectionsScreenUI.zoneLabelFits(width: 100, height: 40, z: 1, labelWidth: 60, labelHeight: 15))
        XCTAssertTrue(DirectionsScreenUI.zoneLabelFits(width: 66, height: 21, z: 1, labelWidth: 60, labelHeight: 15))
        // ...but not when zoomed out, or too narrow or too low.
        XCTAssertFalse(DirectionsScreenUI.zoneLabelFits(width: 100, height: 40, z: 0.5, labelWidth: 60, labelHeight: 15))
        XCTAssertFalse(DirectionsScreenUI.zoneLabelFits(width: 65.9, height: 40, z: 1, labelWidth: 60, labelHeight: 15))
        XCTAssertFalse(DirectionsScreenUI.zoneLabelFits(width: 100, height: 20.9, z: 1, labelWidth: 60, labelHeight: 15))

        XCTAssertTrue(DirectionsScreenUI.hyattLabelFits(width: 40, z: 1, labelWidth: 34))
        XCTAssertFalse(DirectionsScreenUI.hyattLabelFits(width: 40, z: 0.8, labelWidth: 34))
    }

    func testOutlineWidth() throws {
        let hy = try XCTUnwrap(repo.venue.buildings["HY"])
        let xs = hy.outline.map(\.x)
        XCTAssertEqual(xs.max()! - xs.min()!, DirectionsScreenUI.outlineWidth(hy.outline))
        XCTAssertGreaterThan(DirectionsScreenUI.outlineWidth(hy.outline), 0)
        XCTAssertEqual(0.0, DirectionsScreenUI.outlineWidth([]))
    }

    func testLabelLeft_textAnchor() {
        XCTAssertEqual(100.0, DirectionsScreenUI.labelLeft(.start, x: 100, width: 40))
        XCTAssertEqual(80.0, DirectionsScreenUI.labelLeft(.middle, x: 100, width: 40))
        XCTAssertEqual(60.0, DirectionsScreenUI.labelLeft(.end, x: 100, width: 40))
    }

    func testPulse_restartingLinearOutSlowIn() {
        XCTAssertEqual(1200.0, DirectionsScreenUI.pulseDurationMs(here: true))
        XCTAssertEqual(1800.0, DirectionsScreenUI.pulseDurationMs(here: false))
        XCTAssertEqual(0.0, DirectionsScreenUI.pulse(atMs: 0, here: false), accuracy: 1e-12)
        XCTAssertEqual(0.0, DirectionsScreenUI.pulse(atMs: 1800, here: false), accuracy: 1e-12) // restarts
        XCTAssertEqual(0.0, DirectionsScreenUI.pulse(atMs: 3600, here: false), accuracy: 1e-12)
        // LinearOutSlowIn: fast at first (well past half way at mid time), then slows to 1.
        let mid = DirectionsScreenUI.pulse(atMs: 900, here: false)
        XCTAssertGreaterThan(mid, 0.75)
        XCTAssertLessThan(mid, 1.0)
        XCTAssertEqual(mid, DirectionsScreenUI.pulse(atMs: 600, here: true), accuracy: 1e-12)
        XCTAssertEqual(MapCameraAnimation.cubicBezier(0, 0, 0.2, 1, 0.25), DirectionsScreenUI.pulse(atMs: 450, here: false), accuracy: 1e-12)
        XCTAssertGreaterThan(DirectionsScreenUI.pulse(atMs: 1799, here: false), 0.999)
        // Before the clock's origin (never happens) it still cycles forward.
        XCTAssertEqual(DirectionsScreenUI.pulse(atMs: 900, here: false), DirectionsScreenUI.pulse(atMs: -900, here: false), accuracy: 1e-12)
    }

    func testPulseRing() {
        XCTAssertEqual(DirectionsScreenUI.Ring(radius: 6.6, alpha: 0.8, lineWidth: 2.0), rounded(DirectionsScreenUI.pulseRing(0, here: false)))
        XCTAssertEqual(DirectionsScreenUI.Ring(radius: 24.2, alpha: 0.0, lineWidth: 2.0), rounded(DirectionsScreenUI.pulseRing(1, here: false)))
        XCTAssertEqual(DirectionsScreenUI.Ring(radius: 6.6, alpha: 0.95, lineWidth: 3.0), rounded(DirectionsScreenUI.pulseRing(0, here: true)))
        XCTAssertEqual(DirectionsScreenUI.Ring(radius: 35.2, alpha: 0.0, lineWidth: 3.0), rounded(DirectionsScreenUI.pulseRing(1, here: true)))
        XCTAssertEqual(DirectionsScreenUI.Ring(radius: 15, alpha: 0.6, lineWidth: 2), DirectionsScreenUI.pulseRing(nil, here: false))
        XCTAssertEqual(DirectionsScreenUI.Ring(radius: 20, alpha: 0.6, lineWidth: 2), DirectionsScreenUI.pulseRing(nil, here: true))
        XCTAssertEqual(10.0, DirectionsScreenUI.pinRadius(here: false))
        XCTAssertEqual(12.0, DirectionsScreenUI.pinRadius(here: true))
    }

    private func rounded(_ r: DirectionsScreenUI.Ring) -> DirectionsScreenUI.Ring {
        func r6(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }
        return DirectionsScreenUI.Ring(radius: r6(r.radius), alpha: r6(r.alpha), lineWidth: r6(r.lineWidth))
    }

    // ---------------------------------------------------------------- figure 8

    func testFigureEight_phaseAndShape() {
        XCTAssertEqual(0.0, DirectionsScreenUI.figureEightPhase(atMs: 0), accuracy: 1e-12)
        XCTAssertEqual(Double.pi, DirectionsScreenUI.figureEightPhase(atMs: 1200), accuracy: 1e-12)
        XCTAssertEqual(0.0, DirectionsScreenUI.figureEightPhase(atMs: 2400), accuracy: 1e-12)
        XCTAssertEqual(Double.pi / 2, DirectionsScreenUI.figureEightPhase(atMs: 600 + 2400 * 3), accuracy: 1e-9)

        // The lemniscate: right tip at u = 0, the crossing at the centre at u = π/2, left tip at π.
        let a = 13.0
        let right = DirectionsScreenUI.figureEightPoint(0, a: a, cx: 17, cy: 10)
        XCTAssertEqual(30.0, right.x, accuracy: 1e-12)
        XCTAssertEqual(10.0, right.y, accuracy: 1e-12)
        let centre = DirectionsScreenUI.figureEightPoint(Double.pi / 2, a: a, cx: 17, cy: 10)
        XCTAssertEqual(17.0, centre.x, accuracy: 1e-9)
        XCTAssertEqual(10.0, centre.y, accuracy: 1e-9)
        let left = DirectionsScreenUI.figureEightPoint(Double.pi, a: a, cx: 17, cy: 10)
        XCTAssertEqual(4.0, left.x, accuracy: 1e-12)
        // Stretched 1.3× vertically: at u = π/4, y = cy + a·(½)/(3/2)·1.3.
        let lobe = DirectionsScreenUI.figureEightPoint(Double.pi / 4, a: a, cx: 17, cy: 10)
        XCTAssertEqual(10.0 + a / 3.0 * 1.3, lobe.y, accuracy: 1e-9)

        let path = DirectionsScreenUI.figureEightPath(a: a, cx: 17, cy: 10)
        XCTAssertEqual(49, path.count)
        XCTAssertEqual(path.first!.x, path.last!.x, accuracy: 1e-9)
        XCTAssertEqual(path.first!.y, path.last!.y, accuracy: 1e-9)

        // At the right tip the curve runs straight down the screen: the phone lies on its side.
        XCTAssertEqual(180.0, DirectionsScreenUI.figureEightPhoneDeg(0, a: a, cx: 17, cy: 10), accuracy: 5.0)
    }

    // ---------------------------------------------------------------- camera restoration

    func testCameraStorage_perSession() {
        let stored = DirectionsScreenUI.storedCamera("1289660", "manual:1.5,2.25,0.75")
        XCTAssertEqual("manual:1.5,2.25,0.75", DirectionsScreenUI.restoredCamera("1289660", stored))
        XCTAssertNil(DirectionsScreenUI.restoredCamera("1344383", stored))
        XCTAssertNil(DirectionsScreenUI.restoredCamera("1289660", ""))
        XCTAssertEqual("follow", DirectionsScreenUI.restoredCamera("m12", DirectionsScreenUI.storedCamera("m12", "follow")))
    }

    // ---------------------------------------------------------------- heading cone

    func testConeAngle_snapsFirstThenTurnsTheShortWay() {
        let cone = ConeAngleTracker()
        XCTAssertFalse(cone.visible)
        XCTAssertEqual(.hide, cone.update(nil))
        XCTAssertEqual(.snap(-10.0), cone.update(350.0)) // the short way from 0
        XCTAssertTrue(cone.visible)
        XCTAssertEqual(.animate(10.0), cone.update(10.0)) // through north, not back round
        XCTAssertEqual(.animate(-90.0), cone.update(270.0))
        XCTAssertEqual(.animate(-200.0), cone.update(160.0)) // keeps unwrapping past ±180
        XCTAssertEqual(.hide, cone.update(nil))
        XCTAssertFalse(cone.visible)
        // Back after a gap: appears at once, still unwrapped from where it was.
        XCTAssertEqual(.snap(-270.0), cone.update(90.0))
        XCTAssertEqual(.animate(-270.0), cone.update(.nan)) // a non-finite heading keeps the angle
    }
}

/// The camera string survives the scene through ``MapCameraState/Saver`` (main actor).
@MainActor
final class DirectionsScreenUICameraTests: XCTestCase {
    func testCameraStorage_roundTripsThroughTheSaver() throws {
        let cam = MapCameraState(false, MapCamera(301.25, 155.5, 1.75))
        let stored = DirectionsScreenUI.storedCamera("1289660", MapCameraState.Saver.save(cam))
        let back = try XCTUnwrap(DirectionsScreenUI.restoredCamera("1289660", stored).flatMap { MapCameraState.Saver.restore($0) })
        XCTAssertFalse(back.follow)
        XCTAssertEqual(MapCamera(301.25, 155.5, 1.75), back.camera)

        let following = DirectionsScreenUI.storedCamera("1289660", MapCameraState.Saver.save(MapCameraState()))
        let fresh = try XCTUnwrap(DirectionsScreenUI.restoredCamera("1289660", following).flatMap { MapCameraState.Saver.restore($0) })
        XCTAssertTrue(fresh.follow)
        XCTAssertNil(fresh.camera)
    }
}
