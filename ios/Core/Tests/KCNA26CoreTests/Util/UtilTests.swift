import XCTest
@testable import KCNA26Core

/// Locked, SynchronizedLazy, SHA256 and the test CRC32 helper.
final class UtilTests: XCTestCase {

    func testLockedIsThreadSafe() {
        let counter = Locked(0)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in counter.withLock { $0 += 1 } }
        XCTAssertEqual(counter.value, 1000)
        counter.value = 5
        XCTAssertEqual(counter.value, 5)
    }

    func testSynchronizedLazyRunsOnce() {
        let runs = Locked(0)
        let lazy = SynchronizedLazy { () -> Int in
            runs.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.01)
            return 42
        }
        XCTAssertFalse(lazy.isInitialized)
        DispatchQueue.concurrentPerform(iterations: 50) { _ in XCTAssertEqual(lazy.value, 42) }
        XCTAssertEqual(runs.value, 1)
        XCTAssertTrue(lazy.isInitialized)
    }

    func testIsInitializedDoesNotWaitForARunningInitializer() {
        // Kotlin's Lazy.isInitialized() is a volatile read: false at once while another thread
        // is inside the initializer (the splash asks this on the main thread during the parse).
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let lazy = SynchronizedLazy { () -> Int in
            started.signal()
            release.wait()
            return 7
        }
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = lazy.value
            done.signal()
        }
        started.wait()
        let answer = Locked<Bool?>(nil)
        let answered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            answer.value = lazy.isInitialized
            answered.signal()
        }
        let waited = answered.wait(timeout: .now() + 2)
        release.signal()
        XCTAssertEqual(waited, .success, "isInitialized blocked while the initializer was running")
        XCTAssertEqual(answer.value, false)
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(lazy.isInitialized)
        XCTAssertEqual(lazy.value, 7)
    }

    func testThreadsArrivingDuringTheInitializerWaitForItsValue() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let runs = Locked(0)
        let lazy = SynchronizedLazy { () -> String in
            runs.withLock { $0 += 1 }
            started.signal()
            release.wait()
            return "v"
        }
        let results = Locked<[String]>([])
        let group = DispatchGroup()
        let ask: @Sendable () -> Void = {
            let v = lazy.value // outside the results lock
            results.withLock { $0.append(v) }
        }
        DispatchQueue.global().async(group: group, execute: ask)
        started.wait()
        for _ in 0..<8 { DispatchQueue.global().async(group: group, execute: ask) }
        Thread.sleep(forTimeInterval: 0.05) // let the latecomers block on the running initializer
        XCTAssertEqual(results.value, [])
        release.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(results.value, Array(repeating: "v", count: 9))
        XCTAssertEqual(runs.value, 1)
    }

    private struct Boom: Error {}

    func testAThrowingLazyIsRetried() throws {
        let attempts = Locked(0)
        let lazy = SynchronizedLazy { () throws -> String in
            let n = attempts.withLock { a -> Int in
                a += 1
                return a
            }
            if n < 3 { throw Boom() }
            return "ok"
        }
        XCTAssertThrowsError(try lazy.get())
        XCTAssertThrowsError(try lazy.get())
        XCTAssertFalse(lazy.isInitialized)
        XCTAssertEqual(try lazy.get(), "ok")
        XCTAssertEqual(try lazy.get(), "ok")
        XCTAssertEqual(attempts.value, 3)
    }

    func testSHA256KnownAnswers() {
        XCTAssertEqual(SHA256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256.hex(String(repeating: "a", count: 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
        // Lengths around the padding boundary (55, 56, 63, 64 bytes) and binary data.
        XCTAssertEqual(SHA256.hex(Data((0..<256).map(UInt8.init) + (0..<256).map(UInt8.init) + (0..<256).map(UInt8.init))),
                       "f3a25aa93aa2fbba28d79260535bbd6a5eb0fc1c24a8b0f04e12b484c1dfe363")
        XCTAssertEqual(SHA256.digest(Data()).count, 32)
    }

    func testSHA256MatchesTheBundledManifest() throws {
        // manifest.json lists every data file's sha256 and size (DataManifest).
        let files = try XCTUnwrap(TestData.json("manifest.json")["files"]?.objectValue)
        XCTAssertFalse(files.isEmpty)
        for (name, entry) in files {
            let data = TestData.data(name)
            XCTAssertEqual(Int64(data.count), entry["bytes"]?.int64Value, name)
            XCTAssertEqual(SHA256.hex(data), entry["sha256"]?.stringValue, name)
        }
    }

    func testCRC32() {
        // java.util.zip.CRC32 of "123456789" is cbf43926.
        XCTAssertEqual(TestData.crc32Hex("123456789"), "cbf43926")
        XCTAssertEqual(TestData.crc32Hex(""), "00000000")
    }
}
