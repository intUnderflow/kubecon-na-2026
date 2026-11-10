import XCTest
@testable import KCNA26Core

/// Port of reminders/ReminderPlannerTest.kt.
final class ReminderPlannerTests: XCTestCase {

    private let repo = TestData.repo
    private let lucy = "Lucy Sweet"

    private func plan(_ me: String?, _ clock: FixedClock) -> [PlannedReminder] {
        ReminderPlanner.plan(repo.sessions, repo.rooms, me, clock.now())
    }

    private func at(_ iso: String) -> Date { TestData.instant(iso) }

    /// Kotlin `Triple(sessionId, triggerAt, minutesBefore)`.
    private struct Trio: Equatable {
        let id: String
        let at: Date
        let minutes: Int
    }

    func testLucysThreeWednesdayTalksGiveSixRemindersOnTuesday() {
        let reminders = plan(lucy, TestData.clockAt("2026-11-10T12:00:00-07:00"))
        XCTAssertEqual(6, reminders.count)
        XCTAssertEqual(
            [
                Trio(id: "1363905", at: at("2026-11-11T09:15:00-07:00"), minutes: 30),
                Trio(id: "1363905", at: at("2026-11-11T09:35:00-07:00"), minutes: 10),
                Trio(id: "1249844", at: at("2026-11-11T13:50:00-07:00"), minutes: 30),
                Trio(id: "1249844", at: at("2026-11-11T14:10:00-07:00"), minutes: 10),
                Trio(id: "1289660", at: at("2026-11-11T16:30:00-07:00"), minutes: 30),
                Trio(id: "1289660", at: at("2026-11-11T16:50:00-07:00"), minutes: 10),
            ],
            reminders.map { Trio(id: $0.sessionId, at: $0.triggerAt, minutes: $0.minutesBefore) }
        )
        XCTAssertEqual(
            [
                "Your talk in 30 min · Hall DE, Level 1",
                "Your talk in 10 min · Hall DE, Level 1",
                "Your talk in 30 min · Grand Ballroom GI, Level 1",
                "Your talk in 10 min · Grand Ballroom GI, Level 1",
                "Your talk in 30 min · 251 A–C, Level 2",
                "Your talk in 10 min · 251 A–C, Level 2",
            ],
            reminders.map(\.text)
        )
        XCTAssertEqual(
            [
                "A Tribute to Open Source",
                "A Tribute to Open Source",
                "Kubernetes The Hard Way - Live",
                "Kubernetes The Hard Way - Live",
                "The Future of Kubernetes Eviction and Node Lifecycle",
                "The Future of Kubernetes Eviction and Node Lifecycle",
            ],
            reminders.map(\.title)
        )
    }

    func testTriggerTimesAreStartMinusOffset() {
        for r in plan(lucy, TestData.clockAt("2026-11-08T13:00")) {
            let s = repo.session(r.sessionId)!
            XCTAssertEqual(s.start.plusSeconds(-Int64(r.minutesBefore) * 60), r.triggerAt)
        }
    }

    func testTheExampleTextMatchesExactly() throws {
        let gi10s = plan(lucy, TestData.clockAt("2026-11-10T12:00")).filter { $0.sessionId == "1249844" && $0.minutesBefore == 10 }
        XCTAssertEqual(1, gi10s.count)
        let gi10 = try XCTUnwrap(gi10s.first)
        XCTAssertEqual("Your talk in 10 min · Grand Ballroom GI, Level 1", gi10.text)
        XCTAssertEqual("1249844/10", gi10.key)
    }

    func testNoneGivesNoReminders() {
        XCTAssertEqual(0, plan(nil, TestData.clockAt("2026-11-10T12:00")).count)
        XCTAssertEqual(0, plan(nil, TestData.clockAt("2026-11-08T08:00")).count)
    }

    func testUnknownSpeakerGivesNoReminders() {
        XCTAssertEqual(0, plan("Nobody At All", TestData.clockAt("2026-11-10T12:00")).count)
    }

    func testFollowsTheSpeakingAsSetting() {
        // Ryan Hallisey: two talks in CC plus the 5:00 PM one shared with Lucy.
        let ryan = plan("Ryan Hallisey", TestData.clockAt("2026-11-10T12:00"))
        XCTAssertEqual(6, ryan.count)
        XCTAssertEqual(Set(["1334847", "1334856", "1289660"]), Set(ryan.map(\.sessionId)))
        XCTAssertTrue(ryan.allSatisfy { $0.sessionId != "1249844" })
    }

    func testPastRemindersAreDropped() {
        // 9:20: the 9:45 keynote's 30-min reminder (9:15) is gone, its 10-min one (9:35) stays.
        let morning = plan(lucy, TestData.clockAt("2026-11-11T09:20"))
        XCTAssertEqual(5, morning.count)
        XCTAssertEqual("1363905/10", morning.first?.key)

        // 14:15: both 2:20 PM reminders are past; only the 5:00 PM talk is left.
        let afternoon = plan(lucy, TestData.clockAt("2026-11-11T14:15"))
        XCTAssertEqual(["1289660/30", "1289660/10"], afternoon.map(\.key))

        // 16:55: the last 10-min reminder fired at 16:50.
        XCTAssertEqual(0, plan(lucy, TestData.clockAt("2026-11-11T16:55")).count)
        XCTAssertEqual(0, plan(lucy, TestData.clockAt("2026-11-12T09:00")).count)
    }

    func testAReminderExactlyNowIsNotFuture() {
        let r = plan(lucy, TestData.clockAt("2026-11-11T16:30"))
        XCTAssertEqual(["1289660/10"], r.map(\.key))
        let justBefore = plan(lucy, FixedClock(at("2026-11-11T16:30").plusMillis(-1)))
        XCTAssertEqual(["1289660/30", "1289660/10"], justBefore.map(\.key))
    }

    func testPlanIsSortedByTriggerTime() {
        let r = plan("Ryan Hallisey", TestData.clockAt("2026-11-08T13:00"))
        XCTAssertEqual(r.stableSorted(on: { $0.triggerAt }), r)
    }

    func testTextUsesRoomNameAndLevelFromRooms() {
        XCTAssertEqual("Your talk in 10 min · 251 A–C, Level 2", ReminderPlanner.text(10, repo.room("251AC")))
        XCTAssertEqual("Your talk in 30 min · Hyatt lobby, Level 1", ReminderPlanner.text(30, repo.room("HL")))
        for room in repo.rooms.values {
            let t = ReminderPlanner.text(10, room)
            if let level = room.level {
                XCTAssertEqual("Your talk in 10 min · \(room.name), Level \(level)", t)
            }
        }
    }

    func testTextWithoutLevelOrRoom() {
        XCTAssertEqual("Your talk in 10 min · Off-site", ReminderPlanner.text(10, repo.room("OFF")))
        XCTAssertEqual("Your talk in 10 min", ReminderPlanner.text(10, nil))
        // A session of mine in a room code the data doesn't know still plans, with the short text.
        let s = repo.session("1249844")!.withRoom("NOPE")
        let r = ReminderPlanner.plan([s], repo.rooms, lucy, at("2026-11-10T12:00"))
        XCTAssertEqual(["Your talk in 30 min", "Your talk in 10 min"], r.map(\.text))
        let off = ReminderPlanner.plan([s.withRoom("OFF")], repo.rooms, lucy, at("2026-11-10T12:00"))
        XCTAssertEqual("Your talk in 10 min · Off-site", off.last?.text)
    }

    func testFiringOnTimeShowsThePlannedMinutes() {
        let start = at("2026-11-11T17:00")
        XCTAssertEqual(30, ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:30")))
        XCTAssertEqual(10, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:50")))
        // An exact alarm delivered a few hundred ms late still says 10.
        XCTAssertEqual(10, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:50").plusMillis(400)))
    }

    func testALateAlarmShowsTheRealMinutesLeft() {
        let start = at("2026-11-11T17:00")
        XCTAssertEqual(12, ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:48")))
        XCTAssertEqual(3, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:57")))
        XCTAssertEqual(1, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:59:59")))
    }

    func testStaleRemindersAreSkipped() {
        let start = at("2026-11-11T17:00")
        // The session has started (or is over): never notify, e.g. after a boot.
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 10, start))
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T17:05")))
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-12T09:00")))
        // A 30-min reminder so late that the 10-min one is due anyway is dropped (no double alert).
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:50")))
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:55")))
    }

    func testKeysRoundTrip() {
        XCTAssertTrue(ReminderPlanner.parseKey(ReminderPlanner.key("m1318417", 30)).map { $0 == ("m1318417", 30) } ?? false)
        XCTAssertTrue(ReminderPlanner.parseKey("1289660/10").map { $0 == ("1289660", 10) } ?? false)
        XCTAssertNil(ReminderPlanner.parseKey(""))
        XCTAssertNil(ReminderPlanner.parseKey("1289660"))
        XCTAssertNil(ReminderPlanner.parseKey("1289660/"))
        XCTAssertNil(ReminderPlanner.parseKey("/10"))
        XCTAssertNil(ReminderPlanner.parseKey("1289660/x"))
    }

    func testRequestCodesDifferPerOffset() {
        for s in repo.sessions {
            XCTAssertNotEqual(ReminderPlanner.requestCode(s.id, 30), ReminderPlanner.requestCode(s.id, 10))
        }
        let lucysCodes = plan(lucy, TestData.clockAt("2026-11-10T12:00")).map { ReminderPlanner.requestCode($0.sessionId, $0.minutesBefore) }
        XCTAssertEqual(6, Set(lucysCodes).count)
        XCTAssertEqual(ReminderPlanner.requestCode("1249844", 10), ReminderPlanner.requestCode("1249844", 10))
    }

    func testStoreTracksArmedKeys() {
        let store = ReminderStore(InMemoryStore())
        XCTAssertEqual(Set<String>(), store.armed())
        store.setArmed(["1249844/30", "1249844/10"])
        XCTAssertEqual(Set(["1249844/30", "1249844/10"]), store.armed())
        // Switching to None: everything armed is stale and the store empties.
        let next = Set(plan(nil, TestData.clockAt("2026-11-10T12:00")).map(\.key))
        XCTAssertEqual(Set(["1249844/30", "1249844/10"]), store.armed().subtracting(next))
        store.setArmed(next)
        XCTAssertEqual(Set<String>(), store.armed())
    }

    // Not in the Kotlin test: the Swift port's own pieces of Kotlin behaviour.

    func testParseKeyReadsMinutesLikeKotlinToIntOrNull() {
        XCTAssertTrue(ReminderPlanner.parseKey("a/b/15").map { $0 == ("a/b", 15) } ?? false) // last "/"
        XCTAssertTrue(ReminderPlanner.parseKey("1/+5").map { $0 == ("1", 5) } ?? false)
        XCTAssertTrue(ReminderPlanner.parseKey("1/-5").map { $0 == ("1", -5) } ?? false)
        XCTAssertTrue(ReminderPlanner.parseKey("1/\u{FF11}\u{FF10}").map { $0 == ("1", 10) } ?? false) // fullwidth digits
        XCTAssertTrue(ReminderPlanner.parseKey("1/2147483647").map { $0 == ("1", Int(Int32.max)) } ?? false)
        XCTAssertTrue(ReminderPlanner.parseKey("1/-2147483648").map { $0 == ("1", Int(Int32.min)) } ?? false)
        XCTAssertNil(ReminderPlanner.parseKey("1/2147483648"))
        XCTAssertNil(ReminderPlanner.parseKey("1/+"))
        XCTAssertNil(ReminderPlanner.parseKey("1/ 5"))
    }

    func testRequestCodeIsJavaStringHashCode() {
        // "1249844".hashCode() == 2_019_241_618 on the JVM; × 31 + 10 wraps around like Kotlin's Int.
        XCTAssertEqual(-1_828_019_272, ReminderPlanner.requestCode("1249844", 10))
        XCTAssertEqual(0 * 31 + 5, ReminderPlanner.requestCode("", 5))
    }
}

private extension Session {
    /// Kotlin `copy(room = …)`.
    func withRoom(_ room: String) -> Session {
        Session(
            id: id, event: event, day: day, start: start, end: end, endIsEstimate: endIsEstimate, room: room,
            title: title, speakers: speakers, note: note, category: category, group: group,
            precomputedIsMine: precomputedIsMine, precomputedHasAnthropic: precomputedHasAnthropic,
            officialUrl: officialUrl, description: description, slidesUrl: slidesUrl, discussionUrl: discussionUrl,
            coloEvent: coloEvent, coloEvents: coloEvents, format: format, level: level, sponsored: sponsored, topic: topic
        )
    }
}
