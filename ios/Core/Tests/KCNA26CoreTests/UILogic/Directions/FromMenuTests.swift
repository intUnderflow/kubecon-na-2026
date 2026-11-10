import Foundation
import XCTest
@testable import KCNA26Core

/// The From menu's order: nearest first with a fix, grouped like the web without one.
final class FromMenuTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var options = FromOptions.from(Router(repo), repo.wayfinding)

    private func at(_ lat: Double, _ lng: Double) -> PointXY { Geo.toLocal(lat, lng, repo.wayfinding.origin) }

    /// test_vectors.json compass points.
    private lazy var sidewalk200South = at(40.76538, -111.89509)
    private lazy var hyattLobby = at(40.765558, -111.894474)
    private lazy var grandBallroomGI = at(40.76628, -111.89505)
    private lazy var templeSquare = at(40.77005, -111.8917)

    /// The Utah State Capitol, about 1.1–1.5 km from the venue.
    private lazy var capitol = at(40.7774, -111.8882)

    private lazy var allKeys: Set<String> = Set((options.entrances + options.rooms).map(\.key))

    // ---------------------------------------------------------------- options

    func testOptions_carryKindPositionAndLevel() throws {
        let e200s = try XCTUnwrap(options.entrances.first { $0.key == "E200S" })
        XCTAssertEqual(FromKind.entrance, e200s.kind)
        XCTAssertEqual(PointXY(-92.0, 45.0), e200s.pos) // node S200
        XCTAssertEqual(1, e200s.level)
        XCTAssertEqual(2, options.entrances.first { $0.key == "EWT" }?.level) // the West Temple doors are on Level 2

        let r251 = try XCTUnwrap(options.rooms.first { $0.key == "251AC" })
        XCTAssertEqual(FromKind.room, r251.kind)
        XCTAssertEqual(PointXY(-73.0, 286.0), r251.pos)
        XCTAssertEqual(2, r251.level)

        XCTAssertEqual(FromKind.live, options.live.kind)
        XCTAssertNil(options.live.pos)
        XCTAssertTrue(options.entrances.allSatisfy { $0.pos != nil && $0.level != nil })
        XCTAssertTrue(options.rooms.allSatisfy { $0.pos != nil && $0.level != nil })
    }

    // ---------------------------------------------------------------- nearest first

    func testFixAt200South_200SouthFirst() {
        let menu = options.menu(sidewalk200South)
        XCTAssertTrue(menu.byDistance)
        XCTAssertEqual(SettingsStore.FROM_LIVE, menu.live.key)
        XCTAssertEqual([DirectionsText.NEAREST], menu.sections.map(\.title))
        let top = Array(menu.items.prefix(12))
        XCTAssertEqual(
            ["E200S", "SLF", "RA", "SLC", "RB", "RBD", "EHY", "HL", "SLDE", "RCD", "PC", "CR"],
            top.map(\.key)
        )
        XCTAssertEqual(
            ["10 m", "30 m", "40 m", "50 m", "50 m", "50 m", "60 m", "60 m", "60 m", "60 m", "70 m", "70 m"],
            top.map(\.distance)
        )
        XCTAssertEqual(["L1", "L2", "L4", "L2", "L4", "L4", "L1", "L1", "L2", "L4", "L3", "L5"], top.map(\.level))
        XCTAssertEqual("200 South entrance (badge pick-up)", top.first?.option.label)
    }

    func testFixOnThe200SouthEntranceNode_200SouthFirst() throws {
        let first = try XCTUnwrap(options.menu(PointXY(-92.0, 45.0)).items.first)
        XCTAssertEqual("E200S", first.key)
        XCTAssertEqual(0.0, try XCTUnwrap(first.distanceM), accuracy: 1e-9)
        XCTAssertEqual("10 m", first.distance) // r10: never under 10 m, like the readout
    }

    func testFixInTheGrandBallroom_nearestRoomsFirst() {
        let keys = options.menu(grandBallroomGI).items.prefix(5).map(\.key)
        XCTAssertEqual(["H", "J", "BDF", "GI", "ACE"], keys)
    }

    func testEveryEntranceAndRoomOnce_inOneList() {
        for p in [sidewalk200South, hyattLobby, grandBallroomGI, templeSquare, capitol] {
            let menu = options.menu(p)
            XCTAssertEqual(1, menu.sections.count)
            let keys = menu.items.map(\.key)
            XCTAssertEqual(41, keys.count)
            XCTAssertEqual(allKeys, Set(keys))
            XCTAssertFalse(keys.contains(SettingsStore.FROM_LIVE)) // "My location" is apart, always first
            XCTAssertTrue(menu.items.allSatisfy { $0.distanceM != nil && $0.distance != nil && $0.level != nil })
        }
    }

    func testShownDistancesNeverDecrease() {
        for p in [sidewalk200South, hyattLobby, grandBallroomGI, templeSquare, capitol] {
            let shown = options.menu(p).items.map { FromMenu.shownMetres($0.distanceM!) }
            XCTAssertEqual(shown.sorted(), shown)
        }
    }

    func testDistancesAreStraightLineFromTheFix() throws {
        let item = try XCTUnwrap(options.menu(templeSquare).items.first { $0.key == "EWT" })
        // test_vectors.json: the West Temple entrance is 386 m from Temple Square's south gate.
        XCTAssertEqual(386.0, try XCTUnwrap(item.distanceM), accuracy: 3.0)
        XCTAssertEqual("390 m", item.distance)
        let room = try XCTUnwrap(options.menu(templeSquare).items.first { $0.key == "251AC" })
        XCTAssertEqual(Geo.distance(templeSquare, PointXY(-73.0, 286.0)), try XCTUnwrap(room.distanceM), accuracy: 1e-9)
    }

    func testTiesBreakByLevelThenName() throws {
        // From the Hyatt lobby five options show "20 m". Regency Ballroom B is nearest (16 m) but
        // Salt Lake Ballroom C (L2) comes first; the three L4 ballrooms follow by name, then L5.
        let items = options.menu(hyattLobby).items
        let twenty = items.filter { $0.distance == "20 m" }
        XCTAssertEqual(["SLC", "RA", "RB", "RBD", "CR"], twenty.map(\.key))
        XCTAssertEqual(["L2", "L4", "L4", "L4", "L5"], twenty.map(\.level))
        let rb = try XCTUnwrap(twenty.first { $0.key == "RB" })
        XCTAssertTrue(twenty.allSatisfy { $0.distanceM! >= rb.distanceM! })

        // The Hyatt lobby is both an entrance and a room, at the same spot: the entrance first.
        XCTAssertEqual(["EHY", "HL"], items.prefix(2).map(\.key))
        XCTAssertEqual([FromKind.entrance, FromKind.room], items.prefix(2).map(\.option.kind))
    }

    func testTiesBreakByLevelThenName_synthetic() {
        let o = FromOptions(
            entrances: [FromOption("E", "Zeta doors", .entrance, PointXY(0.0, 41.0), 2)],
            rooms: [
                FromOption("b", "Beta", .room, PointXY(38.0, 0.0), 1),
                FromOption("a", "alpha", .room, PointXY(0.0, -44.0), 1),
                FromOption("c", "Gamma", .room, PointXY(-36.0, 0.0), 3),
                FromOption("n", "Near", .room, PointXY(0.0, 20.0), 5),
            ]
        )
        let items = o.menu(PointXY(0.0, 0.0)).items
        // 20 m first; then the four "40 m" options: L1 by name (case-insensitive), then L2, then L3.
        XCTAssertEqual(["n", "a", "b", "E", "c"], items.map(\.key))
        XCTAssertTrue(items.dropFirst().allSatisfy { $0.distance == "40 m" })
    }

    func testFarAway_kilometres() {
        let items = options.menu(capitol).items
        XCTAssertEqual("255BC", items.first?.key)
        XCTAssertEqual("1.1 km", items.first?.distance)
        XCTAssertEqual("E200S", items.last?.key)
        XCTAssertEqual("1.5 km", items.last?.distance)
        XCTAssertTrue(items.allSatisfy { $0.distance!.hasSuffix(" km") })
    }

    func testDistanceLabel_r10ThenKilometres() {
        XCTAssertEqual("10 m", FromMenu.distanceLabel(0.0))
        XCTAssertEqual("10 m", FromMenu.distanceLabel(14.9))
        XCTAssertEqual("20 m", FromMenu.distanceLabel(15.0))
        XCTAssertEqual("30 m", FromMenu.distanceLabel(34.0))
        XCTAssertEqual("40 m", FromMenu.distanceLabel(35.0)) // halves round up, like the web's Math.round
        XCTAssertEqual("120 m", FromMenu.distanceLabel(123.0))
        XCTAssertEqual("990 m", FromMenu.distanceLabel(994.9))
        XCTAssertEqual("1.0 km", FromMenu.distanceLabel(995.0))
        XCTAssertEqual("1.0 km", FromMenu.distanceLabel(1000.0))
        XCTAssertEqual("1.0 km", FromMenu.distanceLabel(1049.0))
        XCTAssertEqual("1.1 km", FromMenu.distanceLabel(1050.0))
        XCTAssertEqual("1.2 km", FromMenu.distanceLabel(1234.0))
        XCTAssertEqual("12.3 km", FromMenu.distanceLabel(12_345.0))
        XCTAssertEqual("7.0 km", FromMenu.distanceLabel(7_012.0))
        XCTAssertEqual("10 m", FromMenu.distanceLabel(Double.nan)) // never throws
        XCTAssertEqual(990, FromMenu.shownMetres(994.9))
        XCTAssertEqual(1200, FromMenu.shownMetres(1234.0))
    }

    func testLevelLabel() {
        XCTAssertEqual("L1", FromMenu.levelLabel(1))
        XCTAssertEqual("L5", FromMenu.levelLabel(5))
        XCTAssertNil(FromMenu.levelLabel(nil))
    }

    // ---------------------------------------------------------------- no fix

    func testNoFix_groupedLikeBefore() {
        for menu in [options.menu(nil), options.menu(PointXY(Double.nan, 3.0)), options.menu(PointXY(1.0, Double.infinity))] {
            XCTAssertFalse(menu.byDistance)
            XCTAssertEqual(SettingsStore.FROM_LIVE, menu.live.key)
            XCTAssertEqual([DirectionsText.ENTRANCES, DirectionsText.ROOMS], menu.sections.map(\.title))
            XCTAssertEqual(["E200S", "EWT", "EHY", "E200W"], menu.sections[0].items.map(\.key))
            XCTAssertEqual(options.rooms, menu.sections[1].items.map(\.option)) // by name, as the engine lists them
            XCTAssertEqual(37, menu.sections[1].items.count)
            XCTAssertTrue(menu.items.allSatisfy { $0.distanceM == nil && $0.distance == nil })
        }
        XCTAssertEqual("250 A–C", options.menu(nil).sections[1].items.first?.option.label)
    }

    // ---------------------------------------------------------------- exclusions

    func testOffAndRoomsWithoutAPositionAreLeftOut() throws {
        for menu in [options.menu(nil), options.menu(sidewalk200South)] {
            let keys = menu.items.map(\.key)
            XCTAssertFalse(keys.contains("OFF"))
            XCTAssertFalse(keys.contains("REG")) // no sessions use them, so the web leaves them out too
            XCTAssertFalse(keys.contains("COAT"))
        }

        let off = try XCTUnwrap(repo.room("OFF"))
        XCTAssertFalse(off.hasPosition)
        let o = FromOptions(
            entrances: [FromOption("E", "Doors", .entrance, PointXY(0.0, 0.0), 1)],
            rooms: [
                FromOption(off.code, off.name, .room, off.pos, off.level),
                FromOption("nan", "Broken", .room, PointXY(Double.nan, 0.0), 1),
                FromOption("r", "Room", .room, PointXY(30.0, 0.0), 2),
            ]
        )
        XCTAssertEqual(["E", "r"], o.menu(PointXY(0.0, 0.0)).items.map(\.key))
        XCTAssertEqual(["E", "r"], o.menu(nil).items.map(\.key))
    }

    func testAnEntranceWithoutAPositionStaysSelectable_atTheEnd() {
        let o = FromOptions(
            entrances: [
                FromOption("lost", "Lost doors", .entrance, nil, nil),
                FromOption("E", "Doors", .entrance, PointXY(500.0, 0.0), 1),
            ],
            rooms: [FromOption("r", "Room", .room, PointXY(30.0, 0.0), 2)]
        )
        let items = o.menu(PointXY(0.0, 0.0)).items
        XCTAssertEqual(["r", "E", "lost"], items.map(\.key))
        XCTAssertNil(items.last?.distance)
        XCTAssertNil(items.last?.level)
    }

    // ---------------------------------------------------------------- stability

    func testSameFix_sameOrder_newFix_reSorted() {
        // The screen freezes the point when the menu opens; the same point always gives the same menu.
        XCTAssertEqual(options.menu(sidewalk200South), options.menu(sidewalk200South))
        let other = options.menu(grandBallroomGI).items.map(\.key)
        XCTAssertFalse(other == options.menu(sidewalk200South).items.map(\.key))
    }
}
