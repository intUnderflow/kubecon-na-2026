import Foundation
import XCTest
@testable import KCNA26Core

/// iOS-only tests (Kotlin has none for RepositoryScoped).
final class RepositoryScopedTests: XCTestCase {
    private final class Box: Sendable {
        let repo: Repository
        init(_ repo: Repository) { self.repo = repo }
    }

    func testOneValuePerRepositoryRebuiltWhenTheRepositoryChanges() throws {
        let made = Locked(0)
        let scoped = RepositoryScoped<Box> { r in
            made.withLock { $0 += 1 }
            return Box(r)
        }
        let a = TestData.repo
        let va = scoped[a]
        XCTAssertTrue(va.repo === a)
        XCTAssertTrue(scoped[a] === va)
        XCTAssertEqual(1, made.value)

        let b = try Repository.fromDirectory(TestData.dataDir) // a swapped-in data set
        let vb = scoped[b]
        XCTAssertTrue(vb.repo === b)
        XCTAssertTrue(scoped[b] === vb)
        XCTAssertEqual(2, made.value)

        XCTAssertFalse(scoped[a] === va) // only the latest is kept
        XCTAssertEqual(3, made.value)
    }

    func testConcurrentReadersShareOneValue() {
        let made = Locked(0)
        let scoped = RepositoryScoped<Box> { r in
            made.withLock { $0 += 1 }
            return Box(r)
        }
        let repo = TestData.repo
        let seen = Locked<Set<ObjectIdentifier>>([])
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let v = scoped[repo]
            seen.withLock { _ = $0.insert(ObjectIdentifier(v)) }
        }
        XCTAssertEqual(1, made.value)
        XCTAssertEqual(1, seen.value.count)
    }
}
