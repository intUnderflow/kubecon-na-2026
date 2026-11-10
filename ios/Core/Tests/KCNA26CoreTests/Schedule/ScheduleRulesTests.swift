import XCTest
@testable import KCNA26Core

/// Port of schedule/ScheduleRulesTest.kt.
final class ScheduleRulesTests: XCTestCase {
    private let repo = TestData.repo

    /// schedule.json's sessions: the web rules made their category and group. (colocated.json's come precomputed.)
    private var web: [Session] { repo.sessions.filter { !$0.isColocated && !$0.id.hasPrefix(TestData.PARTY_ID_PREFIX) } }

    /// The three talks the web's /^(…|Break|…)/ files as breaks, with the category (and group)
    /// they get with a word-bounded "Break". schedule.json may carry either value for these, so
    /// the tests accept both.
    private let misfiled: [String: String] = ["1289638": "mnt", "1336101": "show", "1289733": "mnt"]

    func testWebExactPortReproducesTheJsonCategoriesAndGroups() {
        for s in web {
            if misfiled[s.id] != nil { continue }
            let cat = ScheduleRules.catOf(s, webExact: true)
            XCTAssertEqual(s.category, cat, "category of \(s.id) \(s.title)")
            XCTAssertEqual(s.group, ScheduleRules.seriesOf(s, cat), "group of \(s.id) \(s.title)")
        }
        for id in misfiled.keys { XCTAssertEqual("log", ScheduleRules.catOf(repo.session(id)!, webExact: true)) }
    }

    func testFixedRegexOnlyChangesTheMisfiledBreakingTalks() {
        for s in web {
            let expected = misfiled[s.id] ?? s.category
            XCTAssertEqual(expected, ScheduleRules.catOf(s), "\(s.id) \(s.title)")
        }
        XCTAssertTrue(web.filter { ScheduleRules.isMisfiledBreak($0) }.allSatisfy { misfiled[$0.id] != nil })
        // Real breaks keep "log" and never list speakers (the co-located ones too).
        for s in repo.sessions.filter({ $0.category == "log" && misfiled[$0.id] == nil }) {
            XCTAssertEqual("log", ScheduleRules.catOf(s), s.title)
            XCTAssertTrue(s.speakers.isEmpty)
        }
    }

    func testIndexCorrectsTheMisfiledTalks() {
        let idx = ScheduleIndex.of(repo)
        let helm = repo.session("1289638")! // Tue 250 D–F
        let istio = repo.session("1336101")! // Wed Cosmic Canyon 3:55 PM
        let metal = repo.session("1289733")! // Thu 251 A–C
        XCTAssertEqual("mnt", idx.category(helm))
        XCTAssertEqual(nil, idx.group(helm))
        XCTAssertEqual("show", idx.category(istio))
        XCTAssertEqual("wed-istio", idx.group(istio)?.key)
        XCTAssertEqual("Istio Day", idx.group(istio)?.title)
        XCTAssertTrue(idx.groups["wed-istio"]!.kids.contains { $0.id == "1336101" })
        XCTAssertEqual("mnt", idx.category(metal))
        // Everything else is the JSON value, co-located sessions included ("colo" talks, "log" breaks).
        for s in repo.sessions.filter({ misfiled[$0.id] == nil }) {
            XCTAssertEqual(s.category, idx.category(s))
            XCTAssertEqual(s.group, idx.group(s))
        }
        XCTAssertEqual(212, repo.sessions.filter { $0.isColocated && idx.category($0) == "colo" }.count)
    }
}
