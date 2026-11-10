import XCTest
@testable import KCNA26Core

/// InMemoryStore and UserDefaultsStore (the SharedPreferences port).
final class KeyValueStoreTests: XCTestCase {

    /// The same behaviour checks for any store.
    private func exercise(_ s: KeyValueStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(s.contains("str"), file: file, line: line)
        XCTAssertNil(s.string(forKey: "str"), file: file, line: line)
        s.set("EWT", forKey: "str")
        s.set(["b", "a"], forKey: "set")
        s.set(15, forKey: "int")
        s.set(Int64(1_794_412_800_000), forKey: "long")
        s.set(true, forKey: "bool")
        s.set(2.5, forKey: "double")
        s.set("", forKey: "empty")
        XCTAssertTrue(s.contains("str"), file: file, line: line)
        XCTAssertEqual(s.string(forKey: "str"), "EWT", file: file, line: line)
        XCTAssertEqual(s.stringSet(forKey: "set"), ["a", "b"], file: file, line: line)
        XCTAssertEqual(s.int(forKey: "int"), 15, file: file, line: line)
        XCTAssertEqual(s.int64(forKey: "long"), 1_794_412_800_000, file: file, line: line)
        XCTAssertEqual(s.bool(forKey: "bool"), true, file: file, line: line)
        XCTAssertEqual(s.double(forKey: "double"), 2.5, file: file, line: line)
        // An empty string is a value ("None" in SettingsStore), not an absence.
        XCTAssertTrue(s.contains("empty"), file: file, line: line)
        XCTAssertEqual(s.string(forKey: "empty"), "", file: file, line: line)
        // Absent keys.
        XCTAssertNil(s.int(forKey: "nope"), file: file, line: line)
        XCTAssertNil(s.bool(forKey: "nope"), file: file, line: line)
        XCTAssertNil(s.stringSet(forKey: "nope"), file: file, line: line)
        // Overwrite and remove.
        s.set(false, forKey: "bool")
        XCTAssertEqual(s.bool(forKey: "bool"), false, file: file, line: line)
        s.set(Set<String>(), forKey: "set")
        XCTAssertEqual(s.stringSet(forKey: "set"), [], file: file, line: line)
        s.removeValue(forKey: "str")
        XCTAssertFalse(s.contains("str"), file: file, line: line)
        // A batch applies in order.
        s.edit { e in
            e.set(1, forKey: "a")
            e.set(Int64(2), forKey: "b")
            e.removeValue(forKey: "a")
            e.set("c", forKey: "c")
            e.removeValue(forKey: "x")
            e.set("x", forKey: "x")
        }
        XCTAssertFalse(s.contains("a"), file: file, line: line)
        XCTAssertEqual(s.int64(forKey: "b"), 2, file: file, line: line)
        XCTAssertEqual(s.string(forKey: "c"), "c", file: file, line: line)
        XCTAssertEqual(s.string(forKey: "x"), "x", file: file, line: line)
    }

    /// Typed like SharedPreferences (where another type's getter throws ClassCastException):
    /// another kind's getter finds nothing, in both stores.
    private func crossTypeReads(_ s: KeyValueStore, file: StaticString = #filePath, line: UInt = #line) {
        s.set(42, forKey: "n")
        XCTAssertEqual(s.int(forKey: "n"), 42, file: file, line: line)
        XCTAssertNil(s.bool(forKey: "n"), file: file, line: line)
        XCTAssertNil(s.double(forKey: "n"), file: file, line: line)
        XCTAssertNil(s.string(forKey: "n"), file: file, line: line)
        XCTAssertNil(s.stringSet(forKey: "n"), file: file, line: line)
        s.set(1, forKey: "one")
        XCTAssertNil(s.bool(forKey: "one"), file: file, line: line)
        s.set(true, forKey: "t")
        s.set(false, forKey: "f")
        XCTAssertEqual(s.bool(forKey: "t"), true, file: file, line: line)
        XCTAssertEqual(s.bool(forKey: "f"), false, file: file, line: line)
        for k in ["t", "f"] {
            XCTAssertNil(s.int(forKey: k), k, file: file, line: line)
            XCTAssertNil(s.int64(forKey: k), k, file: file, line: line)
            XCTAssertNil(s.double(forKey: k), k, file: file, line: line)
            XCTAssertNil(s.string(forKey: k), k, file: file, line: line)
        }
        s.set(2.75, forKey: "d")
        s.set(2.0, forKey: "whole")
        XCTAssertEqual(s.double(forKey: "d"), 2.75, file: file, line: line)
        XCTAssertEqual(s.double(forKey: "whole"), 2.0, file: file, line: line)
        for k in ["d", "whole"] {
            XCTAssertNil(s.int(forKey: k), k, file: file, line: line)
            XCTAssertNil(s.int64(forKey: k), k, file: file, line: line)
            XCTAssertNil(s.bool(forKey: k), k, file: file, line: line)
        }
        s.set(Int64(1_794_412_800_000), forKey: "long")
        XCTAssertNil(s.double(forKey: "long"), file: file, line: line)
        XCTAssertNil(s.bool(forKey: "long"), file: file, line: line)
        s.set("42", forKey: "s")
        XCTAssertNil(s.int(forKey: "s"), file: file, line: line)
        XCTAssertNil(s.bool(forKey: "s"), file: file, line: line)
        XCTAssertNil(s.stringSet(forKey: "s"), file: file, line: line)
        s.set(["x"], forKey: "set")
        XCTAssertNil(s.string(forKey: "set"), file: file, line: line)
    }

    func testInMemoryStore() {
        let s = InMemoryStore()
        exercise(s)
        crossTypeReads(s)
        // Int and Int64 are distinct types too (UserDefaultsStore cannot tell them apart).
        s.set(42, forKey: "n")
        XCTAssertNil(s.int64(forKey: "n"))
        s.set(Int64(7), forKey: "l")
        XCTAssertNil(s.int(forKey: "l"))
        XCTAssertNil(s.string(forKey: "n"))
        XCTAssertEqual(s.all["n"], .int(42))
        let seeded = InMemoryStore(["k": .string("v")])
        XCTAssertEqual(seeded.string(forKey: "k"), "v")
    }

    func testInMemoryStoreIsThreadSafe() {
        let s = InMemoryStore()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            s.set(i, forKey: "k\(i % 10)")
            _ = s.int(forKey: "k\((i + 3) % 10)")
        }
        XCTAssertEqual(s.all.count, 10)
    }

    func testUserDefaultsStore() {
        let suite = "kcna26.test.\(UUID().uuidString)"
        let s = UserDefaultsStore(suiteName: suite)
        defer { s.removeAll() }
        exercise(s)
        crossTypeReads(s)
        // The one documented gap: a plist integer is an Int and an Int64.
        XCTAssertEqual(s.int64(forKey: "n"), 42)
        XCTAssertEqual(s.int(forKey: "long"), 1_794_412_800_000)
        // Another instance on the same suite (an app restart) sees the values.
        let again = UserDefaultsStore(suiteName: suite)
        XCTAssertEqual(again.int64(forKey: "b"), 2)
        XCTAssertEqual(again.string(forKey: "c"), "c")
        XCTAssertEqual(again.stringSet(forKey: "set"), ["x"])
        XCTAssertEqual(again.bool(forKey: "t"), true)
        XCTAssertNil(again.int(forKey: "t"))
        XCTAssertNil(again.int(forKey: "d"))
        XCTAssertNil(again.bool(forKey: "one"))
        s.removeAll()
        XCTAssertFalse(UserDefaultsStore(suiteName: suite).contains("c"))
    }

    func testStoresBackTheKotlinPrefsFiles() {
        // Same file and key names as Android.
        XCTAssertEqual(SettingsStore.PREFS, "kcna26.settings")
        XCTAssertEqual(GoingStore.PREFS, "kcna26.going")
        XCTAssertEqual(ReminderStore.PREFS, "kcna26.reminders")
        XCTAssertEqual(FakeableClock.PREFS, "kcna26.debug")
        XCTAssertEqual(FakeableClock.KEY_OFFSET, "fakeNowOffsetMs")
    }

    func testReminderStore() {
        let prefs = InMemoryStore()
        let r = ReminderStore(prefs)
        XCTAssertEqual(r.armed(), [])
        r.setArmed(["a", "b"])
        XCTAssertEqual(ReminderStore(prefs).armed(), ["a", "b"])
        XCTAssertEqual(prefs.stringSet(forKey: "armed"), ["a", "b"])
        r.setArmed([])
        XCTAssertFalse(prefs.contains("armed"))
        XCTAssertEqual(r.armed(), [])
    }

    func testFakeableClockStoresTheOffsetAsALong() {
        let prefs = InMemoryStore()
        let c = FakeableClock(prefs, allowFake: true)
        c.setFakeNow(Date().plusMinutes(60))
        let stored = prefs.int64(forKey: FakeableClock.KEY_OFFSET)
        XCTAssertNotNil(stored)
        XCTAssertLessThan(abs(stored! - 3_600_000), 2_000)
        XCTAssertTrue(c.isFaked)
        c.clearFakeNow()
        XCTAssertFalse(prefs.contains(FakeableClock.KEY_OFFSET))
        // A release build ignores a stored offset.
        prefs.set(Int64(3_600_000), forKey: FakeableClock.KEY_OFFSET)
        XCTAssertFalse(FakeableClock(prefs, allowFake: false).isFaked)
        XCTAssertTrue(FakeableClock(prefs, allowFake: true).isFaked)
        XCTAssertFalse(FakeableClock(prefs, allowFake: true).applyFakeNowArg("   "))
        XCTAssertFalse(FakeableClock(prefs, allowFake: true).applyFakeNowArg(nil))
        XCTAssertTrue(FakeableClock(prefs, allowFake: true).applyFakeNowArg(" OFF "))
        XCTAssertFalse(prefs.contains(FakeableClock.KEY_OFFSET))
    }
}
