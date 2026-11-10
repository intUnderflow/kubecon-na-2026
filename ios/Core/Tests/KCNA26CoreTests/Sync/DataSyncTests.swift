import Foundation
import Observation
import XCTest
@testable import KCNA26Core

/// Port of sync/DataSyncTest.kt (same tests, same expectations), plus a few iOS-only tests of
/// the crash guard's launch marker at the end.
///
/// Crashes: Kotlin calls `sync.onCrash()` (its uncaught-exception handler). iOS can't run code
/// when the app crashes, so the guard counts a crash at the next launch from the launch marker
/// the dead process left behind; ``crashAndRelaunch(_:appVersion:)`` is that: `sync`'s process
/// ends without `onBackground()`, and the next launch's `installCrashGuard()` returns what
/// Kotlin's `onCrash()` would have.
final class DataSyncTests: XCTestCase {
    private typealias JObject = OrderedMap<String, JSONValue>

    // Kotlin @Before + TemporaryFolder: XCTest makes one instance per test, so these are per
    // test; the folders are made on first use and deleted after the test.
    private lazy var tmp: URL = makeTemporaryFolder()
    private lazy var bundledDir: URL = makeBundledDir()
    private lazy var root: URL = tmp.appendingPathComponent("files/data", isDirectory: true)
    private let prefs = InMemoryStore()
    private let fetcher = FakeFetcher()
    private let now = Locked<Int64>(1_000_000)
    private let swapped = Locked<[ActiveData]>([])
    private let logs = Locked<[String]>([])

    private static let BASE = "https://example.test/data/"

    /// What the bundled manifest lists (make_manifest.py): the files a published set must have.
    private static let BUNDLED_NAMES: [String] = {
        do {
            return try DataManifest.parse(Data(contentsOf: TestData.assetsDir.appendingPathComponent(DataManifest.FILE))).files.keys
        } catch {
            fatalError("bundled manifest: \(error)")
        }
    }()

    // MARK: - Helpers

    private func makeTemporaryFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataSyncTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fatalError("temporary folder: \(error)")
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeBundledDir() -> URL {
        let dir = tmp.appendingPathComponent("assets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in DataSyncTests.BUNDLED_NAMES {
                try FileManager.default.copyItem(at: TestData.assetsDir.appendingPathComponent(name), to: dir.appendingPathComponent(name))
            }
            try Data(manifestJson(bundledFiles(in: dir), version: 1).utf8).write(to: dir.appendingPathComponent(DataManifest.FILE))
        } catch {
            fatalError("bundled folder: \(error)")
        }
        return dir
    }

    private func newSync(appVersion: Int = 1) -> DataSync {
        let dir = bundledDir
        let swapped = swapped
        let now = now
        let logs = logs
        return DataSync(
            root: root,
            bundled: { name in try Data(contentsOf: dir.appendingPathComponent(name)) },
            fetcher: fetcher,
            prefs: prefs,
            baseUrl: DataSyncTests.BASE,
            onSwapped: { a in swapped.withLock { $0.append(a) } },
            nowMillis: { now.value },
            appVersion: appVersion,
            log: { m in logs.withLock { $0.append(m) } }
        )
    }

    private func advance(_ ms: Int64) { now.withLock { $0 += ms } }

    private func bundledFiles(in dir: URL? = nil) -> OrderedMap<String, Data> {
        let d = dir ?? bundledDir
        return DataSyncTests.BUNDLED_NAMES.associateWith { name in read(d.appendingPathComponent(name)) }
    }

    private func read(_ url: URL) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("read \(url.path): \(error)")
        }
    }

    private func manifestJson(_ files: OrderedMap<String, Data>, version: Int) -> String {
        let m = DataManifest(
            version: version,
            updatedAt: "2026-11-08T21:15:00Z",
            files: files.mapValues { b in ManifestEntry(sha256: DataManifest.sha256(b), bytes: Int64(b.count)) }
        )
        return JSON.encode(m)
    }

    /// Publishes the bundled files with `changes` applied, as manifest `version`. Returns the served files.
    @discardableResult
    private func publish(_ version: Int, _ etag: String, _ changes: OrderedMap<String, Data> = [:]) -> OrderedMap<String, Data> {
        let files = bundledFiles().merging(changes)
        fetcher.served = [:]
        for (name, b) in files { fetcher.served[DataSyncTests.BASE + name] = b }
        fetcher.served[DataSyncTests.BASE + DataManifest.FILE] = Data(manifestJson(files, version: version).utf8)
        fetcher.etag = etag
        return files
    }

    private func object(_ name: String) -> JObject {
        do {
            guard let o = try JSON.parse(read(bundledDir.appendingPathComponent(name))).objectValue else { fatalError("\(name): not an object") }
            return o
        } catch {
            fatalError("\(name): \(error)")
        }
    }

    /// schedule.json with the first session edited by `edit`.
    private func scheduleWithFirstSession(_ edit: (JObject) -> JObject) -> Data {
        edited("schedule.json") { doc in
            var sessions = doc["sessions"]?.arrayValue ?? []
            sessions[0] = .object(edit(sessions[0].objectValue ?? [:]))
            return doc.with("sessions", .array(sessions))
        }
    }

    /// The bundled `name` with its top-level object edited by `edit`.
    private func edited(_ name: String, _ edit: (JObject) -> JObject) -> Data {
        JSON.serializedData(.object(edit(object(name))))
    }

    private func assertRejected(_ outcome: SyncOutcome, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(isRejected(outcome, why), outcome.description, file: file, line: line)
    }

    private func isRejected(_ outcome: SyncOutcome, _ why: String = "") -> Bool {
        if case .rejected(let reason) = outcome { return reason.kotlinContains(why) }
        return false
    }

    private func isFailed(_ outcome: SyncOutcome, _ why: String = "") -> Bool {
        if case .failed(let reason) = outcome { return reason.kotlinContains(why) }
        return false
    }

    private func check(_ sync: DataSync) async -> SyncOutcome { await sync.check() }

    private func downloads() -> [String] {
        fetcher.requests.map(\.url).filter { $0 != DataSyncTests.BASE + DataManifest.FILE }.map { $0.removePrefix(DataSyncTests.BASE) }
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    private func isFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path, isDirectory: &isDir) && !isDir.boolValue
    }

    private func children() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    }

    private func assertStillBundled(_ sync: DataSync, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = try XCTUnwrap(sync.active, file: file, line: line)
        XCTAssertEqual(.bundled, a.source, file: file, line: line)
        XCTAssertEqual(1, a.version, file: file, line: line)
        XCTAssertEqual(TestData.repo.sessions[0].title, a.repository.sessions[0].title, file: file, line: line)
        XCTAssertTrue(swapped.value.isEmpty, file: file, line: line)
        XCTAssertFalse(exists(DataSync.POINTER), file: file, line: line)
        XCTAssertFalse(exists(DataSync.STAGING), file: file, line: line)
        XCTAssertTrue(children().allSatisfy { !$0.hasPrefix("v") }, "\(children())", file: file, line: line)
        // A restart still uses the bundled data.
        XCTAssertEqual(.bundled, try newSync().loadActive().source, file: file, line: line)
    }

    /// Kotlin `sync.onCrash()` (see the class comment): `sync`'s process dies in the foreground
    /// (no `onBackground()`, so its launch marker stays), and the next launch counts it.
    /// Returns that launch and whether it rolled the set back.
    private func crashAndRelaunch(_ sync: DataSync, appVersion: Int = 1) -> (next: DataSync, rolledBack: Bool) {
        _ = sync // its process ends here
        let next = newSync(appVersion: appVersion)
        return (next, next.installCrashGuard())
    }

    // MARK: - Tests

    func testStartsFromTheBundledData() throws {
        let a = try newSync().loadActive()
        XCTAssertEqual(.bundled, a.source)
        XCTAssertEqual(1, a.version)
        XCTAssertEqual(TestData.repo.sessions.count, a.repository.sessions.count)
    }

    func testHappyPathDownloadsOnlyChangedFilesVerifiesAndSwaps() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Moved to Ballroom B")) }])

        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)

        XCTAssertEqual(["schedule.json"], downloads()) // everything else reused from the bundled copy
        let a = try XCTUnwrap(sync.active)
        XCTAssertEqual(.github, a.source)
        XCTAssertEqual(2, a.version)
        XCTAssertEqual("Moved to Ballroom B", a.repository.sessions[0].title)
        XCTAssertEqual([2], swapped.value.map(\.version))
        XCTAssertEqual("v2", String(decoding: read(root.appendingPathComponent(DataSync.POINTER)), as: UTF8.self))
        XCTAssertTrue(isFile("v2/schedule.json"))
        XCTAssertTrue(isFile("v2/manifest.json"))
        XCTAssertFalse(exists(DataSync.STAGING))

        // After a restart the downloaded set is used, since it is newer than the bundled one.
        let restarted = try newSync().loadActive()
        XCTAssertEqual(.github, restarted.source)
        XCTAssertEqual("Moved to Ballroom B", restarted.repository.sessions[0].title)
        XCTAssertEqual(try TestData.repo.details.count, try restarted.repository.details.count)
    }

    func testNotModifiedSendsTheEtagAndDownloadsNothing() async {
        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("X")) }])
        let first = await check(sync)
        XCTAssertEqual(.updated(2), first)
        fetcher.requests = []

        let second = await check(sync)
        XCTAssertEqual(.notModified, second)
        XCTAssertEqual([FakeFetcher.Request(url: DataSyncTests.BASE + DataManifest.FILE, ifNoneMatch: "\"e2\"")], fetcher.requests)
        XCTAssertEqual([2], swapped.value.map(\.version))
    }

    func testHashMismatchLeavesDataUntouchedAndRetriesNextTime() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("New")) }])
        // The CDN still serves the old schedule.json for a few minutes.
        fetcher.served[DataSyncTests.BASE + "schedule.json"] = read(bundledDir.appendingPathComponent("schedule.json")) + Data(" ".utf8)

        let outcome = await check(sync)
        XCTAssertTrue(isFailed(outcome, "schedule.json"), outcome.description)
        try assertStillBundled(sync)

        // Not remembered as handled: the next check fetches the manifest again (no If-None-Match) and succeeds.
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("New")) }])
        fetcher.requests = []
        let retried = await check(sync)
        XCTAssertEqual(.updated(2), retried)
        XCTAssertNil(try XCTUnwrap(fetcher.requests.first).ifNoneMatch)
    }

    func testBadJsonIsRejectedAndNotDownloadedAgain() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"bad\"", ["schedule.json": Data("{ \"sessions\": [ oops".utf8)])

        let outcome = await check(sync)
        XCTAssertTrue(isRejected(outcome), outcome.description)
        try assertStillBundled(sync)

        // Same broken manifest: a 304, so it isn't downloaded again.
        fetcher.requests = []
        let again = await check(sync)
        XCTAssertEqual(.notModified, again)
        XCTAssertEqual([String](), downloads())
    }

    func testMissingRoomReferenceIsRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("room", .string("NOPE")) }])

        let outcome = await check(sync)
        XCTAssertTrue(isRejected(outcome, "unknown room 'NOPE'"), outcome.description)
        try assertStillBundled(sync)
    }

    func testMissingWayfindingNodeIsRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let rooms = object("rooms.json")
        let all = rooms["rooms"]?.objectValue ?? [:]
        let (code, room) = try XCTUnwrap(all.first { _, r in r.objectValue?.containsKey("attachNode") == true })
        let broken = rooms.with("rooms", .object(all.with(code, .object((room.objectValue ?? [:]).with("attachNode", .string("NOWHERE"))))))
        publish(2, "\"e2\"", ["rooms.json": JSON.serializedData(.object(broken))])

        let outcome = await check(sync)
        XCTAssertTrue(isRejected(outcome, "unknown node 'NOWHERE'"), outcome.description)
        try assertStillBundled(sync)
    }

    func testOlderOrSameVersionIsIgnored() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(1, "\"same\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Same version")) }])
        let same = await check(sync)
        XCTAssertEqual(.notNewer(1), same)
        XCTAssertEqual([String](), downloads())
        try assertStillBundled(sync)

        publish(3, "\"e3\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Three")) }])
        let three = await check(sync)
        XCTAssertEqual(.updated(3), three)
        fetcher.requests = []
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Two")) }])
        let two = await check(sync)
        XCTAssertEqual(.notNewer(2), two)
        XCTAssertEqual([String](), downloads())
        XCTAssertEqual("Three", try XCTUnwrap(sync.active).repository.sessions[0].title)
    }

    func testPartialDownloadIsNotSwapped() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let rooms = Data(String(decoding: read(bundledDir.appendingPathComponent("rooms.json")), as: UTF8.self).replaceFirst("{", "{ ").utf8)
        publish(
            2, "\"e2\"",
            ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Half")) }, "rooms.json": rooms]
        )
        fetcher.failing.insert(DataSyncTests.BASE + "schedule.json") // rooms.json downloads, schedule.json doesn't

        let outcome = await check(sync)
        XCTAssertTrue(isFailed(outcome), outcome.description)
        try assertStillBundled(sync)
    }

    func testOfflineOr404IsAQuietFailure() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let outcome = await check(sync)
        XCTAssertEqual(.failed("manifest: HTTP 404"), outcome) // repo not published yet
        try assertStillBundled(sync)
    }

    func testUnsafeFileNamesAreRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let files = bundledFiles().with("../evil.json", Data("{}".utf8))
        fetcher.served[DataSyncTests.BASE + DataManifest.FILE] = Data(manifestJson(files, version: 2).utf8)
        let outcome = await check(sync)
        XCTAssertTrue(isRejected(outcome), outcome.description)
        XCTAssertEqual([String](), downloads())
        try assertStillBundled(sync)
    }

    func testNewerBundledDataWinsOverAnOlderDownload() async throws {
        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Downloaded")) }])
        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)

        // An app update bundles version 3.
        try Data(manifestJson(bundledFiles(), version: 3).utf8).write(to: bundledDir.appendingPathComponent(DataManifest.FILE))
        let restarted = try newSync().loadActive()
        XCTAssertEqual(.bundled, restarted.source)
        XCTAssertEqual(3, restarted.version)
        XCTAssertFalse(exists("v2")) // the stale download is cleaned up
    }

    func testCorruptedDownloadFallsBackToBundled() async throws {
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Downloaded")) }])
        let outcome = await check(newSync())
        XCTAssertEqual(.updated(2), outcome)
        let rooms = root.appendingPathComponent("v2/rooms.json")
        try (read(rooms) + Data(" ".utf8)).write(to: rooms)

        let restarted = try newSync().loadActive()
        XCTAssertEqual(.bundled, restarted.source)
        XCTAssertEqual(1, restarted.version)
    }

    func testForegroundChecksAreThrottledTo15Minutes() async {
        let sync = newSync()
        XCTAssertTrue(sync.isDue()) // app start
        _ = await check(sync)
        advance(DataSync.FOREGROUND_INTERVAL_MS - 1)
        XCTAssertFalse(sync.isDue())
        advance(1)
        XCTAssertTrue(sync.isDue())
    }

    func testDuplicateDayKeysAreRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let schedule = edited("schedule.json") { doc in
            let days = doc["days"]?.arrayValue ?? []
            return doc.with("days", .array(days + [days[0]]))
        }
        publish(2, "\"e2\"", ["schedule.json": schedule])
        assertRejected(await check(sync), "duplicate day keys")
        try assertStillBundled(sync)
    }

    func testEmptyBuildingOutlineIsRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let venue = edited("venue.json") { doc in
            let buildings = doc["buildings"]?.objectValue ?? [:]
            let hy = (buildings["HY"]?.objectValue ?? [:]).with("outline", .array([]))
            return doc.with("buildings", .object(buildings.with("HY", .object(hy))))
        }
        publish(2, "\"e2\"", ["venue.json": venue])
        assertRejected(await check(sync), "building HY: outline has 0 points")
        try assertStillBundled(sync)
    }

    func testNoEntrancesIsRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"e2\"", ["wayfinding.json": edited("wayfinding.json") { $0.with("entrances", .object([:])) }])
        assertRejected(await check(sync), "no entrances")
        try assertStillBundled(sync)
    }

    func testTheBundledSetWithItsCoLocatedEventsIsValid() throws {
        // colocated.json uses places rooms.json doesn't have (foyers, lunch hall): still valid.
        XCTAssertTrue(DataSyncTests.BUNDLED_NAMES.contains("colocated.json") && DataSyncTests.BUNDLED_NAMES.contains("colocated_details.json"))
        let repo = try Repository.fromDirectory(bundledDir)
        XCTAssertTrue(!repo.coloEvents.isEmpty)
        XCTAssertEqual([String](), try DataValidator.problems(repo, files: DataSyncTests.BUNDLED_NAMES))
    }

    func testAnUnreadableColocatedFileIsRejected() async throws {
        // Repository.load would quietly drop it (no event cards): the published set must not.
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"e2\"", ["colocated.json": Data("{ \"events\": [ oops".utf8)])
        assertRejected(await check(sync), "colocated.json: no usable events")
        try assertStillBundled(sync)
    }

    func testACoLocatedTalkInAnUnknownRoomIsRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        let colo = edited("colocated.json") { doc in
            var sessions = doc["sessions"]?.arrayValue ?? []
            sessions[0] = .object((sessions[0].objectValue ?? [:]).with("room", .string("NOPE")))
            return doc.with("sessions", .array(sessions))
        }
        publish(2, "\"e2\"", ["colocated.json": colo])
        assertRejected(await check(sync), "unknown room 'NOPE'")
        try assertStillBundled(sync)
    }

    func testAManifestWithoutABundledFileIsRejected() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        var files = bundledFiles()
        files.removeValue(forKey: "rooms.json")
        for (name, b) in files { fetcher.served[DataSyncTests.BASE + name] = b }
        fetcher.served[DataSyncTests.BASE + DataManifest.FILE] = Data(manifestJson(files, version: 2).utf8)
        assertRejected(await check(sync), "missing rooms.json")
        XCTAssertEqual([String](), downloads())
        try assertStillBundled(sync)
    }

    func testARejectionByAnOlderAppVersionIsRetried() async throws {
        let v1 = newSync(appVersion: 1)
        publish(2, "\"bad\"", ["schedule.json": Data("{ \"sessions\": [ oops".utf8)])
        let rejected = await check(v1)
        XCTAssertTrue(isRejected(rejected), rejected.description)
        fetcher.requests = []
        let remembered = await check(v1)
        XCTAssertEqual(.notModified, remembered) // same app: remembered

        // An app update that might accept it: no If-None-Match, so it is fetched and checked again.
        let v2 = newSync(appVersion: 2)
        fetcher.requests = []
        let retried = await check(v2)
        XCTAssertTrue(isRejected(retried), retried.description)
        XCTAssertNil(try XCTUnwrap(fetcher.requests.first).ifNoneMatch)
        fetcher.requests = []
        let rememberedAgain = await check(v2)
        XCTAssertEqual(.notModified, rememberedAgain)
    }

    func testCrashGuardRollsBackADownloadedSetThatKeepsCrashing() async throws {
        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Crashy")) }])
        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)

        let (restarted, firstRolledBack) = crashAndRelaunch(sync)
        XCTAssertFalse(firstRolledBack) // one crash could be anything
        XCTAssertTrue(exists(DataSync.POINTER))
        XCTAssertEqual(.github, try restarted.loadActive().source)
        let (safe, secondRolledBack) = crashAndRelaunch(restarted)
        XCTAssertTrue(secondRolledBack) // the second: roll back
        XCTAssertFalse(exists(DataSync.POINTER))

        // The next start uses the bundled data, and the same version isn't downloaded again.
        XCTAssertEqual(.bundled, try safe.loadActive().source)
        fetcher.requests = []
        assertRejected(await check(safe), "rolled back")
        XCTAssertEqual([String](), downloads())
        let again = await check(safe)
        XCTAssertEqual(.notModified, again)

        // Fixed forward with a new version: downloaded as usual.
        publish(3, "\"e3\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Fixed")) }])
        let fixed = await check(safe)
        XCTAssertEqual(.updated(3), fixed)
        XCTAssertEqual("Fixed", try XCTUnwrap(safe.active).repository.sessions[0].title)
        XCTAssertFalse(crashAndRelaunch(safe).rolledBack) // v3 starts its own probation from zero
    }

    func testCrashGuardLeavesSetsAloneAfterProbationAndTheBundledData() async throws {
        let bundled = newSync()
        _ = try bundled.loadActive()
        let (bundledAgain, firstRolledBack) = crashAndRelaunch(bundled)
        XCTAssertFalse(firstRolledBack)
        _ = try bundledAgain.loadActive()
        XCTAssertFalse(crashAndRelaunch(bundledAgain).rolledBack)

        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Fine")) }])
        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)
        // iOS dates a crash by the start of the foreground session it ended (the launch marker's
        // time), so Kotlin's "crash after probation" is a crash in a session that began after
        // it: the user leaves, comes back a day later, and the app crashes.
        sync.onBackground()
        advance(DataSync.PROBATION_MS + 1)
        _ = await sync.onForeground()?.value
        let (restarted, secondRolledBack) = crashAndRelaunch(sync)
        XCTAssertFalse(secondRolledBack)
        _ = try restarted.loadActive()
        XCTAssertFalse(crashAndRelaunch(restarted).rolledBack)
        XCTAssertTrue(exists(DataSync.POINTER))
        XCTAssertEqual(.github, try newSync().loadActive().source)
    }

    func testARollbackByAnOlderAppVersionDoesNotBlockAnUpdate() async throws {
        let v1 = newSync(appVersion: 1)
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Crashy in 1")) }])
        let outcome = await check(v1)
        XCTAssertEqual(.updated(2), outcome)
        let (v1Again, _) = crashAndRelaunch(v1, appVersion: 1)
        _ = try v1Again.loadActive()
        XCTAssertTrue(crashAndRelaunch(v1Again, appVersion: 1).rolledBack)

        let v2 = newSync(appVersion: 2)
        XCTAssertEqual(.bundled, try v2.loadActive().source)
        let updated = await check(v2)
        XCTAssertEqual(.updated(2), updated)
    }

    func testTheBundledDataSetPassesValidation() throws {
        XCTAssertEqual([String](), try DataValidator.problems(TestData.repo))
    }

    // MARK: - iOS: the crash guard's launch marker

    func testCrashGuardDoesNotCountAProcessThatLeftTheForeground() async throws {
        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Fine")) }])
        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)
        XCTAssertTrue(isFile(DataSync.LAUNCH_MARKER))
        sync.onBackground() // then iOS kills the suspended app: not a crash
        XCTAssertFalse(exists(DataSync.LAUNCH_MARKER))

        let next = newSync()
        XCTAssertFalse(next.installCrashGuard())
        XCTAssertEqual(.github, try next.loadActive().source)
        XCTAssertTrue(isFile(DataSync.LAUNCH_MARKER))
        // Had the background exit counted, this first real crash would roll back.
        let (restarted, firstRolledBack) = crashAndRelaunch(next)
        XCTAssertFalse(firstRolledBack)
        XCTAssertEqual(.github, try restarted.loadActive().source)
        XCTAssertTrue(crashAndRelaunch(restarted).rolledBack)
    }

    func testTheLaunchMarkerIsOnlyWrittenInTheForegroundDuringProbation() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        XCTAssertFalse(exists(DataSync.LAUNCH_MARKER)) // bundled data: nothing to guard

        sync.onBackground()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Background")) }])
        let outcome = await check(sync) // a check that finishes after the app left the foreground
        XCTAssertEqual(.updated(2), outcome)
        XCTAssertFalse(exists(DataSync.LAUNCH_MARKER))

        _ = await sync.onForeground()?.value // back in the foreground with v2 on probation
        let marker = String(decoding: read(root.appendingPathComponent(DataSync.LAUNCH_MARKER)), as: UTF8.self)
        XCTAssertEqual("2 \(now.value)", marker)

        sync.onBackground()
        advance(DataSync.PROBATION_MS + 1)
        _ = await sync.onForeground()?.value // probation is over
        XCTAssertFalse(exists(DataSync.LAUNCH_MARKER))
    }

    func testTheLaunchCountsThePreviousCrashBeforeAnythingClearsTheMarker() async throws {
        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Crashy")) }])
        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)
        let (restarted, firstRolledBack) = crashAndRelaunch(sync)
        XCTAssertFalse(firstRolledBack)
        _ = try restarted.loadActive()

        // The next launch goes to the background before loading anything: the crash still counts.
        let next = newSync()
        next.onBackground()
        XCTAssertTrue(next.installCrashGuard()) // the result of the launch's one count
        XCTAssertFalse(exists(DataSync.POINTER))
        XCTAssertEqual(.bundled, try next.loadActive().source)
    }

    func testChecksRunOneAtATime() async throws {
        let sync = newSync()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Once")) }])
        async let a = sync.check()
        async let b = sync.check()
        let outcomes = await [a, b]
        XCTAssertEqual(Set([SyncOutcome.updated(2), .notModified]), Set(outcomes))
        XCTAssertEqual([2], swapped.value.map(\.version))
        XCTAssertFalse(sync.status.checking)
    }

    func testActiveAndStatusAreObservable() async throws {
        let sync = newSync()
        _ = try sync.loadActive()
        publish(2, "\"e2\"", ["schedule.json": scheduleWithFirstSession { $0.with("title", .string("Observed")) }])
        let changed = Locked<[String]>([])
        withObservationTracking {
            _ = sync.active
        } onChange: {
            changed.withLock { $0.append("active") }
        }
        withObservationTracking {
            _ = sync.status
        } onChange: {
            changed.withLock { $0.append("status") }
        }
        let outcome = await check(sync)
        XCTAssertEqual(.updated(2), outcome)
        XCTAssertEqual(["status", "active"], changed.value)
        let status = sync.status
        XCTAssertEqual(SyncStatus(checking: false, last: .updated(2), lastCheckedAt: Date(epochMillis: 1_000_000)), status)
    }

    // MARK: - Fake

    private final class FakeFetcher: DataFetcher {
        struct Request: Equatable {
            let url: String
            let ifNoneMatch: String?
        }

        private struct State {
            var served: [String: Data] = [:]
            var failing: Set<String> = []
            var etag: String?
            var requests: [Request] = []
        }

        private let state = Locked(State())

        var served: [String: Data] {
            get { state.value.served }
            set { state.withLock { $0.served = newValue } }
        }

        var failing: Set<String> {
            get { state.value.failing }
            set { state.withLock { $0.failing = newValue } }
        }

        var etag: String? {
            get { state.value.etag }
            set { state.withLock { $0.etag = newValue } }
        }

        var requests: [Request] {
            get { state.value.requests }
            set { state.withLock { $0.requests = newValue } }
        }

        func get(_ url: String, ifNoneMatch: String?, maxBytes: Int64) async -> HttpResult {
            let s = state.withLock { s -> State in
                s.requests.append(Request(url: url, ifNoneMatch: ifNoneMatch))
                return s
            }
            if s.failing.contains(url) { return .failed("offline") }
            let isManifest = url.kotlinEndsWith("/" + DataManifest.FILE)
            if isManifest, let ifNoneMatch, ifNoneMatch == s.etag { return .notModified }
            guard let body = s.served[url] else { return .failed("HTTP 404") }
            let n = Int(min(Int64(body.count), maxBytes + 1))
            return .ok(body: Data(body.prefix(n)), etag: isManifest ? s.etag : nil)
        }
    }
}
