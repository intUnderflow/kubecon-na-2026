import Foundation
import XCTest
@testable import KCNA26Core

final class FloorReminderTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var router = Router(repo)

    private func reminder(_ from: RouteFrom, _ to: String) -> FloorReminder {
        let room = repo.room(to)!
        return FloorReminder.of(room, router.route(from, to))
    }

    func testRoute251AC() {
        let f = reminder(.entrance("E200S"), "251AC")
        XCTAssertEqual(f, FloorReminder(2, "Salt Palace", "251 A–C", "take the North Foyer escalator up", .up, 1))
        XCTAssertEqual(f.headline, "Level 2 · Salt Palace · 251 A–C")
        XCTAssertEqual(f.instruction, "Room is on Level 2: take the North Foyer escalator up")
        XCTAssertEqual(f.levelLabel, "Level 2")
        XCTAssertEqual(f.buildingAndRoom, "Salt Palace · 251 A–C")
    }

    func testRouteRA() {
        let f = reminder(.entrance("E200S"), "RA")
        XCTAssertEqual(f.headline, "Level 4 · Hyatt Regency · Regency Ballroom A")
        XCTAssertEqual(f.instruction, "Room is on Level 4: take the Hyatt escalators or an elevator up")
        XCTAssertEqual(f.direction, .up)
        // The same from the live position in the Hyatt lobby (test vector).
        let v = TestData.vectors.compass[2]
        let live = FloorReminder.of(repo.room("RA")!, router.route(.myLocation(router.myLocation(v.lat, v.lng, 12.0)), "RA"))
        XCTAssertEqual(live, f)
    }

    func testGoingDown() {
        let f = reminder(.room("251AC"), "GI")
        XCTAssertEqual(f.instruction, "Room is on Level 1: take the escalator down to the North Foyer")
        XCTAssertEqual(f.direction, .down)
        XCTAssertEqual(f.headline, "Level 1 · Salt Palace · Grand Ballroom GI")
        XCTAssertEqual(reminder(.room("CR"), "RB").instruction, "Room is on Level 4: take a Hyatt elevator down")
        XCTAssertEqual(reminder(.room("SLC"), "HL").instruction, "Room is on Level 1: take the Hyatt escalator down to the lobby")
    }

    func testNoLevelChange() {
        // Level 1 room from street level.
        let de = reminder(.entrance("E200S"), "DE")
        XCTAssertNil(de.action)
        XCTAssertNil(de.direction)
        XCTAssertEqual(de.hops, 0)
        XCTAssertEqual(de.instruction, "Room is on Level 1")
        XCTAssertEqual(de.headline, "Level 1 · Salt Palace · Hall DE")
        // Already on the right level: the West Temple entrance is on Level 2.
        let ef = reminder(.entrance("EWT"), "255EF")
        XCTAssertNil(ef.action)
        XCTAssertEqual(ef.instruction, "Room is on Level 2")
        // Starting in the room itself.
        XCTAssertNil(reminder(.room("RA"), "RA").action)
        // No route at all.
        XCTAssertEqual(FloorReminder.of(repo.room("251AC")!, nil).instruction, "Room is on Level 2")
    }

    func testMultiHop() {
        // 200 South → Capitol Reef (Level 5): two hops up, joined.
        let cr = reminder(.entrance("E200S"), "CR")
        XCTAssertEqual(
            cr.instruction,
            "Room is on Level 5: take the Hyatt escalators or an elevator up, then take a Hyatt elevator up one level"
        )
        XCTAssertEqual(cr.hops, 2)
        // Capitol Reef → Salt Lake Ballroom C (Level 2): two hops down.
        let slc = reminder(.room("CR"), "SLC")
        XCTAssertEqual(slc.instruction, "Room is on Level 2: take a Hyatt elevator down, then take the escalator down")
        XCTAssertEqual(slc.direction, .down)
        // Down then up (Park City → Regency A): only the hops that end on the room's level count.
        let ra = reminder(.room("PC"), "RA")
        XCTAssertEqual(ra.instruction, "Room is on Level 4: take the Hyatt escalators or an elevator up")
        XCTAssertEqual(ra.hops, 1)
        // Hyatt Level 2 → Salt Palace Level 2: same level overall, but you go down and back up.
        let sp = reminder(.room("SLC"), "251AC")
        XCTAssertEqual(router.route(.room("SLC"), "251AC")!.levelsChanged, 0)
        XCTAssertEqual(sp.instruction, "Room is on Level 2: take the North Foyer escalator up")
    }

    func testOffSiteAndHyattLobby() {
        let off = FloorReminder.of(repo.room("OFF")!, nil)
        XCTAssertNil(off.level)
        XCTAssertNil(off.building)
        XCTAssertNil(off.instruction)
        XCTAssertEqual(off.headline, "Off-site")
        let hl = FloorReminder.of(repo.room("HL")!, router.route(.entrance("E200S"), "HL"))
        XCTAssertEqual(hl.headline, "Level 1 · Hyatt Regency · Hyatt lobby")
        XCTAssertEqual(hl.instruction, "Room is on Level 1")
    }

    func testActionFromEveryUpDownEdgeText() {
        let expected: OrderedMap<String, String> = [
            "Take the North Foyer escalator up to Level 2. You arrive on the Upper Concourse.": "take the North Foyer escalator up",
            "Take the escalator down to the North Foyer on Level 1.": "take the escalator down to the North Foyer",
            "Take the escalator by Rooms 155 up to Level 2. You arrive on the Upper Mezzanine.": "take the escalator by Rooms 155 up",
            "Take the escalator by Rooms 255 down to Level 1, by the Secondary Entrance.": "take the escalator by Rooms 255 down, by the Secondary Entrance",
            "Take the Hyatt escalator up to Level 2.": "take the Hyatt escalator up",
            "Take the Hyatt escalator down to the lobby.": "take the Hyatt escalator down to the lobby",
            "Take a Hyatt elevator up to Level 3.": "take a Hyatt elevator up",
            "Take a Hyatt elevator down to the lobby.": "take a Hyatt elevator down to the lobby",
            "Take the escalator up two more levels to Level 4. You arrive in the Regency Foyer.": "take the escalator up two more levels",
            "Take the escalator down to Level 2.": "take the escalator down",
            "Take the Hyatt escalators or an elevator up to Level 4. You arrive in the Regency Foyer.": "take the Hyatt escalators or an elevator up",
            "Take the escalators or an elevator down to the Hyatt lobby.": "take the escalators or an elevator down to the Hyatt lobby",
            "Take a Hyatt elevator up one level to Level 5.": "take a Hyatt elevator up one level",
            "Take a Hyatt elevator down to Level 4.": "take a Hyatt elevator down",
        ]
        // Every level-changing edge text in wayfinding.json is covered.
        let nodes = repo.wayfinding.nodes
        let texts = repo.wayfinding.edges
            .filter { nodes[$0.a]!.level != nodes[$0.b]!.level }
            .flatMap { [$0.textAB, $0.textBA] }
        XCTAssertEqual(Set(texts), Set(expected.keys))
        for (text, action) in expected { XCTAssertEqual(FloorReminder.actionOf(text), action, text) }
        XCTAssertNil(FloorReminder.actionOf(""))
        XCTAssertNil(FloorReminder.actionOf(" . "))
        XCTAssertEqual(FloorReminder.actionOf("Go up"), "go up")
    }

    func testEveryRouteGivesAReminderThatEndsOnTheRoomsLevel() {
        let starts: [RouteFrom] = router.startEntrances.map { .entrance($0.key) } + router.startRooms.map { .room($0.code) }
        for from in starts {
            for room in router.startRooms {
                let route = router.route(from, room.code)!
                let f = FloorReminder.of(room, route)
                XCTAssertEqual(f.level, room.level)
                XCTAssertNotNil(f.instruction)
                let changes = route.steps.contains { $0.kind.changesLevel }
                XCTAssertEqual(f.action != nil, changes, "\(from) → \(room.code)")
                if let it = f.action {
                    XCTAssertTrue(it.first!.isLowercase, it)
                    XCTAssertTrue(!it.kotlinEndsWith("."), it)
                    XCTAssertTrue(!it.kotlinContains("Level \(room.level!)"), it)
                }
            }
        }
    }
}
