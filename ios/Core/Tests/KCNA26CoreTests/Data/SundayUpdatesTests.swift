import Foundation
import XCTest
@testable import KCNA26Core

/// Port of data/SundayUpdatesTest.kt: the Sunday updates (data/updates/2026-11-08-sunday.json,
/// applied by scripts/apply_updates.py) as the app sees them: through the parsed bundled data
/// (ios/KCNA26/Resources/Data, the copy of android/app/src/main/assets).
///
/// Only its sessionUpdates matter: the unconference (voting) feature and unconference.json were
/// removed once the Summit's voting was over, so its topicUpdates are skipped by the script.
final class SundayUpdatesTests: XCTestCase {
    private let repo = TestData.repo

    private let unconfIds = [
        "m1318474", "m1318479", "m1318476", "m1318475", "m1318482",
        "m1318481", "m1318480", "m1318486", "m1318484", "m1318483",
    ]

    /// The file's topicUpdates are ignored (unknown keys).
    private struct Updates: JSONDecodable {
        let sessionUpdates: [SessionUpdate]

        init(json: JSONValue) throws {
            let o = try JSONFields(json, "Updates")
            sessionUpdates = try o.required("sessionUpdates")
        }
    }

    private struct SessionUpdate: JSONDecodable {
        let id: String
        let start: String
        let end: String?
        let endIsEstimate: Bool
        let room: String
        let title: String
        let speakers: [String]
        let description: String?
        let discussionUrl: String?

        init(json: JSONValue) throws {
            let o = try JSONFields(json, "SessionUpdate")
            id = try o.required("id")
            start = try o.required("start")
            end = try o.optional("end")
            endIsEstimate = try o.value("endIsEstimate", default: false)
            room = try o.required("room")
            title = try o.required("title")
            speakers = try o.required("speakers")
            description = try o.optional("description")
            discussionUrl = try o.optional("discussionUrl")
        }
    }

    /// A file under the repository's data/ folder, or nil.
    private func dataFile(_ name: String) -> URL? {
        let url = TestData.publishedDataDir.appendingPathComponent(name)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue ? url : nil
    }

    private func updates() throws -> Updates {
        let f = try XCTUnwrap(dataFile("updates/2026-11-08-sunday.json"), "data/updates/2026-11-08-sunday.json not found")
        return try JSON.decode(Updates.self, from: Data(contentsOf: f))
    }

    private func instant(_ iso: String) -> Date { TestData.instant(iso) }

    func testTheTenUnconferenceSessionsHaveTheirNewTitlesAndSpeakers() throws {
        let updates = try updates()
        XCTAssertEqual(Set(unconfIds), Set(updates.sessionUpdates.map(\.id)))
        for u in updates.sessionUpdates {
            let s = try XCTUnwrap(repo.session(u.id), u.id)
            XCTAssertEqual(u.title, s.title, u.id)
            XCTAssertEqual(u.speakers, s.speakers, u.id)
            XCTAssertEqual(instant(u.start), s.start, u.id)
            XCTAssertEqual(u.end.map(instant), s.end, u.id)
            XCTAssertEqual(u.endIsEstimate, s.endIsEstimate, u.id)
            XCTAssertEqual(u.room, s.room, u.id)
            XCTAssertEqual(u.description, s.description, u.id)
            XCTAssertEqual(u.discussionUrl, s.discussionUrl, u.id)
            XCTAssertTrue(s.title.kotlinStartsWith("Unconference: "), u.id)
            XCTAssertTrue(!s.speakers.isEmpty, u.id)
            // Still ordinary Maintainer Summit sessions tagged "Unconference".
            XCTAssertEqual("Unconference", s.note)
            XCTAssertTrue(s.isMaintainerSummit)
            // Recomputed at runtime as usual: none of them is mine or has an Anthropic speaker.
            XCTAssertFalse(isMine(s, repo.defaultMe))
            XCTAssertFalse(repo.hasAnthropic(s, repo.defaultMe))
        }
        XCTAssertEqual(615, repo.sessions.count { !$0.isColocated }) // schedule.json; colocated.json's follow
        let placeholder = KRegex("Unconference Session \\d+")
        XCTAssertTrue(!repo.sessions.contains { placeholder.matches($0.title) })
    }

    func testFirstUnconferenceSessionEndsAt210() throws {
        let s = try XCTUnwrap(repo.session("m1318474"))
        XCTAssertEqual("Unconference: Surviving the CVE vulnpocalypse", s.title)
        XCTAssertEqual(["Samuel Karp"], s.speakers)
        XCTAssertEqual(instant("2026-11-08T13:35:00-07:00"), s.start)
        XCTAssertEqual(instant("2026-11-08T14:10:00-07:00"), s.end)
        XCTAssertFalse(s.endIsEstimate)
        XCTAssertEqual("1:35–2:10 PM", TimeFormat.range(s))
        XCTAssertEqual("35 min", TimeFormat.dur(s))
        // The other nine keep estimated ends ("~45 min").
        XCTAssertTrue(unconfIds.dropFirst().allSatisfy { repo.session($0)?.endIsEstimate == true })
    }

    func testSpeakersAreSearchableAndPickable() {
        for name in ["Samuel Karp", "Antonio Ojea", "Filip Křepinský", "Diana Todea"] {
            XCTAssertTrue(repo.allSpeakers.contains(name), name)
        }
    }

    func testAssetsMatchTheDataFolder() throws {
        for name in [Repository.SCHEDULE, Repository.SUMMIT_DETAILS] {
            let data = try XCTUnwrap(dataFile(name), "data/\(name) not found")
            // Byte equality (Kotlin compares the decoded texts; equal bytes are equal texts).
            XCTAssertEqual(try Data(contentsOf: data), TestData.data(name), name)
        }
    }

    func testUnconferenceDataIsGone() throws {
        // The unconference (voting) feature was removed: no unconference.json anywhere...
        XCTAssertFalse(FileManager.default.fileExists(atPath: TestData.assetsDir.appendingPathComponent("unconference.json").path))
        XCTAssertNil(dataFile("unconference.json"))
        // ...and loading never asks for it.
        let opened = Locked<[String]>([])
        let dir = TestData.assetsDir
        let loaded = try Repository.load { name in
            opened.withLock { $0.append(name) }
            return try Data(contentsOf: dir.appendingPathComponent(name))
        }
        XCTAssertEqual(615, loaded.sessions.count { !$0.isColocated })
        XCTAssertFalse(opened.value.contains("unconference.json"), "\(opened.value)")
    }

    // MARK: - parsing the new optional field

    private func loadWith(_ schedule: String) throws -> Repository {
        let dir = TestData.assetsDir
        let bytes = Data(schedule.utf8)
        return try Repository.load { name in
            name == Repository.SCHEDULE ? bytes : try Data(contentsOf: dir.appendingPathComponent(name))
        }
    }

    func testDiscussionUrlIsParsedAndOptional() throws {
        XCTAssertEqual("https://github.com/cncf/maintainer-summit/discussions/117", repo.session("m1318474")?.discussionUrl)
        XCTAssertEqual(10, repo.sessions.count { $0.discussionUrl != nil })
        XCTAssertEqual(Set(unconfIds), Set(repo.sessions.filter { $0.discussionUrl != nil }.map(\.id)))
        XCTAssertTrue(repo.sessions.allSatisfy { $0.discussionUrl?.kotlinStartsWith("https://github.com/") ?? true })
        XCTAssertNil(try XCTUnwrap(repo.session("m1318417")).discussionUrl) // the reception has none
        XCTAssertTrue(repo.sessions.filter { !$0.isMaintainerSummit }.allSatisfy { $0.discussionUrl == nil })

        // Absent, null or blank: nil. Present: kept as is.
        let text = TestData.text(Repository.SCHEDULE)
        let url = "\"discussionUrl\": \"https://github.com/cncf/maintainer-summit/discussions/117\""
        XCTAssertTrue(text.kotlinContains(url))
        XCTAssertNil(try XCTUnwrap(try loadWith(text.kotlinReplace(url, "\"discussionUrl\": null")).session("m1318474")).discussionUrl)
        XCTAssertNil(try XCTUnwrap(try loadWith(text.kotlinReplace(url, "\"discussionUrl\": \"\"")).session("m1318474")).discussionUrl)
        XCTAssertNil(try XCTUnwrap(try loadWith(text.kotlinReplace(",\n   \(url)", "")).session("m1318474")).discussionUrl)
        let other = try loadWith(text.kotlinReplace(url, "\"discussionUrl\": \"https://example.com/d/1\""))
        XCTAssertEqual("https://example.com/d/1", try XCTUnwrap(other.session("m1318474")).discussionUrl)
    }

    func testDetailsLinkWording() {
        XCTAssertEqual("Proposal and replies on GitHub ↗", SessionText.DISCUSSION)
        // No "See and vote on the topics" link is left in the data.
        XCTAssertTrue(!repo.summitDetails.values.contains { $0.linkText != nil || $0.link != nil })
        XCTAssertFalse(TestData.text(Repository.SUMMIT_DETAILS).kotlinContains("See and vote"))
    }
}
