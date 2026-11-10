import Foundation
import XCTest
@testable import KCNA26Core

/// iOS-only tests of DataValidator's own rules (Kotlin's DataSyncTest checks single problems
/// through published sets).
final class DataValidatorTests: XCTestCase {
    func testValidatorReportsAtMostTwentyProblems() throws {
        // Every session in an unknown room: one problem each, but the list stops at 20.
        let doc = try XCTUnwrap(TestData.json(Repository.SCHEDULE).objectValue)
        let sessions = (doc["sessions"]?.arrayValue ?? []).map { s in JSONValue.object((s.objectValue ?? [:]).with("room", .string("NOPE"))) }
        let schedule = JSON.serializedData(.object(doc.with("sessions", .array(sessions))))
        let dir = TestData.dataDir
        let repo = try Repository.load { name in
            name == Repository.SCHEDULE ? schedule : try Data(contentsOf: dir.appendingPathComponent(name))
        }
        let problems = try DataValidator.problems(repo, includeDetails: false)
        XCTAssertEqual(20, problems.count)
        XCTAssertEqual("session \(repo.sessions[0].id): unknown room 'NOPE'", problems[0])
        XCTAssertTrue(problems.allSatisfy { $0.hasSuffix(": unknown room 'NOPE'") })
    }

    func testCoLocatedFilesMustDeliverOnlyWhenTheSetListsThem() throws {
        let dir = TestData.dataDir
        func repo(broken: String) throws -> Repository {
            try Repository.load { name in
                name == broken ? Data("{ oops".utf8) : try Data(contentsOf: dir.appendingPathComponent(name))
            }
        }
        // Repository.load quietly drops an unreadable co-located file.
        let noEvents = try repo(broken: Repository.COLOCATED)
        XCTAssertTrue(noEvents.coloEvents.isEmpty)
        XCTAssertTrue(try DataValidator.problems(noEvents, files: [Repository.COLOCATED]).contains("colocated.json: no usable events"))
        XCTAssertFalse(try DataValidator.problems(noEvents).contains("colocated.json: no usable events"))

        let noDescriptions = try repo(broken: Repository.COLOCATED_DETAILS)
        XCTAssertFalse(noDescriptions.coloEvents.isEmpty)
        XCTAssertEqual(["colocated_details.json: no descriptions"], try DataValidator.problems(noDescriptions, files: [Repository.COLOCATED_DETAILS]))
        XCTAssertEqual([String](), try DataValidator.problems(noDescriptions))
        XCTAssertEqual([String](), try DataValidator.problems(noDescriptions, includeDetails: false, files: [Repository.COLOCATED_DETAILS]))
    }

    func testABrokenDetailsFileThrowsLikeKotlin() throws {
        let dir = TestData.dataDir
        let repo = try Repository.load { name in
            name == Repository.DETAILS ? Data("[".utf8) : try Data(contentsOf: dir.appendingPathComponent(name))
        }
        XCTAssertThrowsError(try DataValidator.problems(repo))
        XCTAssertEqual([String](), try DataValidator.problems(repo, includeDetails: false))
    }
}
