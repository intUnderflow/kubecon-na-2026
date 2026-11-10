import XCTest
@testable import KCNA26Core

/// Port of data/RepositoryTest.kt.
final class RepositoryTests: XCTestCase {
    private let repo = TestData.repo

    func testLoadsAllSessions() {
        // schedule.json's 615, then colocated.json's 223 (see ColocatedRepositoryTests).
        XCTAssertEqual(838, repo.sessions.count)
        XCTAssertEqual(838, repo.sessionsById.count)
        XCTAssertEqual(615, repo.sessions.filter { !$0.isColocated }.count)
        XCTAssertTrue(repo.sessions.prefix(615).allSatisfy { !$0.isColocated })
    }

    func testLoadsDaysCategoriesAndSpeakers() {
        XCTAssertEqual(["sun", "mon", "tue", "wed", "thu"], repo.days.map(\.key))
        XCTAssertEqual(LocalDate(2026, 11, 8), repo.days[0].date)
        XCTAssertEqual("Sun", repo.days[0].dow)
        XCTAssertEqual(8, repo.days[0].num)
        XCTAssertEqual(9, repo.categories.count)
        XCTAssertEqual("Lucy Sweet", repo.defaultMe)
        XCTAssertTrue(repo.anthropicSpeakers.contains("Lucy Sweet"))
        XCTAssertTrue(repo.allSpeakers.contains("Lucy Sweet"))
    }

    func testSessionFields() throws {
        let open = repo.sessions.filter { $0.end == nil }
        XCTAssertEqual(1, open.count) // Kotlin single { }
        XCTAssertEqual("m1318417", open[0].id)
        XCTAssertEqual(open[0].start.plusSeconds(90 * 60), open[0].effectiveEnd)
        XCTAssertTrue(open[0].isMaintainerSummit)
        let grouped = try XCTUnwrap(repo.session("1289955"))
        XCTAssertEqual(SessionGroup("mon-plt", "Project Lightning Talks"), grouped.group)
        XCTAssertEqual("RBD", grouped.room)
        XCTAssertTrue(repo.sessions.contains { $0.slidesUrl != nil })
        XCTAssertTrue(repo.sessions.filter { $0.description != nil }.count > 0)
    }

    func testRoomsIncludingOffSite() throws {
        XCTAssertEqual(40, repo.rooms.count)
        let off = try XCTUnwrap(repo.room("OFF"))
        XCTAssertEqual("Off-site", off.name)
        XCTAssertFalse(off.hasPosition)
        XCTAssertNil(off.pos)
        XCTAssertNil(off.level)
        let r = try XCTUnwrap(repo.room("251AC"))
        XCTAssertEqual(2, r.level)
        XCTAssertEqual("UC", r.attachNode)
        XCTAssertTrue(r.hasPosition)
        XCTAssertNil(try XCTUnwrap(repo.room("HL")).buildingLabel)
        // Every session's room exists.
        XCTAssertTrue(repo.sessions.allSatisfy { repo.room($0.room) != nil })
    }

    func testWayfindingAndVenue() {
        let w = repo.wayfinding
        XCTAssertEqual(["E200S", "EWT", "EHY", "E200W"], w.entrances.keys)
        XCTAssertEqual(18, w.nodes.count)
        XCTAssertEqual(19, w.edges.count)
        XCTAssertEqual(84300.0, w.origin.metersPerDegLon, accuracy: 0.0)
        XCTAssertEqual(["S200", "LCS", "LCM", "NF"], w.routing.lowerConcourseMerge.nodes)
        XCTAssertEqual(Set(["SP", "HY"]), Set(repo.venue.buildings.keys))
        XCTAssertEqual(6, repo.venue.streets.count)
        XCTAssertEqual(5, repo.venue.zones.count)
    }

    func testDetailsAndSummitDetails() throws {
        let details = try repo.details
        XCTAssertEqual(562 + 223, details.count) // details.json + colocated_details.json
        XCTAssertEqual(562, details.keys.filter { repo.session($0)?.isColocated != true }.count)
        let d = try XCTUnwrap(details["1203350"])
        XCTAssertEqual("Vinayak Goyal", d.speakers[0].name)
        XCTAssertEqual("Cluster Security @ Anthropic", d.speakers[0].tagline)
        XCTAssertEqual(14, repo.summitDetails.count)
        XCTAssertTrue(repo.summitDetails.keys.allSatisfy { repo.session($0) != nil })
        // The unconference feature is gone: no "UNCONF" entry ("See and vote on the topics").
        XCTAssertFalse(repo.summitDetails.containsKey("UNCONF"))
        XCTAssertTrue(repo.summitDetails.values.allSatisfy { $0.link == nil && $0.linkText == nil })
        XCTAssertFalse(repo.summitDetails.containsKey("_about"))
    }

    /// iOS addition: the main thread may ask `isDetailsLoaded` while a background thread parses.
    func testIsDetailsLoadedDoesNotWaitForTheParse() throws {
        let reading = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let r = try Repository.load { name in
            if name == Repository.DETAILS {
                reading.signal()
                release.wait()
            }
            return try Data(contentsOf: TestData.dataDir.appendingPathComponent(name))
        }
        XCTAssertFalse(r.isDetailsLoaded)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? r.details
            done.signal()
        }
        reading.wait()
        let answered = DispatchSemaphore(value: 0)
        let answer = Locked<Bool?>(nil)
        DispatchQueue.global().async {
            answer.value = r.isDetailsLoaded
            answered.signal()
        }
        let waited = answered.wait(timeout: .now() + 2)
        release.signal()
        XCTAssertEqual(waited, .success, "isDetailsLoaded blocked on the running parse")
        XCTAssertEqual(answer.value, false)
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(r.isDetailsLoaded)
        XCTAssertEqual(562 + 223, try r.details.count)
    }

    func testBuiltInCategoryColoursMatchScheduleJson() throws {
        for (k, c) in repo.categories {
            XCTAssertEqual(try c.lightArgb, CategoryLight[k], k)
            XCTAssertEqual(try c.darkArgb, CategoryDark[k], k)
        }
    }

    func testMineAndAnthropicAtRuntime() {
        let mine = repo.mySessions("Lucy Sweet")
        XCTAssertEqual(3, mine.count)
        XCTAssertTrue(mine.allSatisfy { $0.day == "wed" })
        XCTAssertTrue(repo.mySessions(nil).isEmpty)
        // Matches the precomputed flags for the default setting.
        for s in repo.sessions {
            XCTAssertEqual(s.precomputedIsMine, isMine(s, "Lucy Sweet"), s.id)
            XCTAssertEqual(s.precomputedHasAnthropic, repo.hasAnthropic(s, "Lucy Sweet"), s.id)
        }
        // With None, Lucy's own sessions count as Anthropic sessions.
        XCTAssertTrue(mine.allSatisfy { repo.hasAnthropic($0, nil) })
        XCTAssertEqual("You", speakerLabel("Lucy Sweet", "Lucy Sweet"))
        XCTAssertEqual("Lucy Sweet", speakerLabel("Lucy Sweet", nil))
    }
}
