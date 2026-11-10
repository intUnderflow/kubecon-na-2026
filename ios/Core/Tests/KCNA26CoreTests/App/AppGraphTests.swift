import Foundation
import XCTest
@testable import KCNA26Core

/// The app graph's wiring (Kotlin AppGraph / KcnaApp / MainActivity start-up, which have no
/// Kotlin unit tests), with fakes for every platform service: the data loads off the main
/// thread, data swaps rebuild details and routing and re-plan the reminders, the reminders
/// follow every setting, the fake clock and the foreground, a tapped reminder opens
/// Directions, and notification permission is asked in context.
@MainActor
final class AppGraphTests: XCTestCase {
    private let lucy = "Lucy Sweet"

    // MARK: - Fakes

    private final class PrefsRegistry: @unchecked Sendable {
        private let stores = Locked<[String: InMemoryStore]>([:])

        func store(_ name: String) -> InMemoryStore {
            stores.withLock { s in
                if let x = s[name] { return x }
                let x = InMemoryStore()
                s[name] = x
                return x
            }
        }

        var names: [String] { stores.value.keys.sorted() }
    }

    private final class FakeDataFetcher: DataFetcher, @unchecked Sendable {
        private let state = Locked<(served: [String: Data], requests: [String])>(([:], []))

        func serve(_ url: String, _ body: Data) { state.withLock { $0.served[url] = body } }
        var requests: [String] { state.value.requests }

        func get(_ url: String, ifNoneMatch: String?, maxBytes: Int64) async -> HttpResult {
            let body = state.withLock { s -> Data? in
                s.requests.append(url)
                return s.served[url]
            }
            guard let body else { return .failed("offline") }
            return .ok(body: body, etag: "\"e1\"")
        }
    }

    private actor FakePermission: NotificationPermission {
        private var current: NotificationAsk.Authorization
        private var grants: Bool
        private var hold: Bool
        private var held: CheckedContinuation<Void, Never>?
        private(set) var requests = 0

        /// `hold`: the system dialog stays up until ``release()``.
        init(_ status: NotificationAsk.Authorization, grants: Bool = true, hold: Bool = false) {
            current = status
            self.grants = grants
            self.hold = hold
        }

        func status() async -> NotificationAsk.Authorization { current }

        func request() async -> Bool {
            requests += 1
            if hold { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in held = c } }
            current = grants ? .authorized : .denied
            return grants
        }

        var isHolding: Bool { held != nil }

        func setGrants(_ g: Bool) { grants = g }

        /// The user answers the dialog.
        func release() {
            hold = false
            held?.resume()
            held = nil
        }
    }

    private struct Fixture {
        let graph: AppGraph
        let prefs: PrefsRegistry
        let center: FakeReminderCenter
        let fetcher: FakeDataFetcher
        let permission: FakePermission
        let clock: FixedClock?
        let logs: Locked<[String]>
        let dir: URL
    }

    private static let BASE = "https://example.test/data/"

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppGraphTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func fixture(
        at iso: String? = "2026-11-10T12:00:00-07:00",
        speakingAs: String? = nil,
        permission: NotificationAsk.Authorization = .authorized,
        holdPermission: Bool = false,
        isDebug: Bool = true,
        bundled: (@Sendable (String) throws -> Data)? = nil
    ) -> Fixture {
        let prefs = PrefsRegistry()
        if let speakingAs { SettingsStore(prefs.store(SettingsStore.PREFS)).setSpeakingAs(speakingAs) }
        let center = FakeReminderCenter()
        let fetcher = FakeDataFetcher()
        let perm = FakePermission(permission, hold: holdPermission)
        let clock = iso.map { TestData.clockAt($0) }
        let logs = Locked<[String]>([])
        let dir = tempDir()
        let assets = TestData.assetsDir
        let services = AppServices(
            filesDirectory: dir,
            prefs: { name in prefs.store(name) },
            bundledData: bundled ?? { name in try Data(contentsOf: assets.appendingPathComponent(name)) },
            dataFetcher: fetcher,
            detailsFetcher: ClosureDetailsFetcher { _ in .notFound },
            reminders: center,
            notificationPermission: perm,
            dataBaseUrl: AppGraphTests.BASE,
            appVersion: 1,
            isDebug: isDebug,
            wallClock: clock ?? SystemAppClock.shared,
            clockOverride: clock,
            log: { m in logs.withLock { $0.append(m) } }
        )
        return Fixture(graph: AppGraph(services), prefs: prefs, center: center, fetcher: fetcher, permission: perm, clock: clock, logs: logs, dir: dir)
    }

    private func eventually(
        timeout: TimeInterval = 10,
        _ what: String = "condition",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Lets queued main-actor work (observation hops, reschedule tasks) run, then waits for the reminders.
    private func settle(_ g: AppGraph) async {
        for _ in 0..<5 { await Task.yield() }
        await g.reminders.settle()
    }

    private func lucysKeys(at iso: String) -> [String] {
        ReminderPlanner.plan(TestData.repo.sessions, TestData.repo.rooms, lucy, TestData.instant(iso)).map(\.key)
    }

    // MARK: - Repository

    func testTheRepositoryLoadsOffTheMainThreadAtStart() async throws {
        let f = fixture()
        let g = f.graph
        XCTAssertFalse(g.isRepositoryLoaded)
        XCTAssertEqual(.loading, g.rootState)
        XCTAssertFalse(g.showsFirstRunSheet)
        g.start()
        let repo = try await g.awaitRepository()
        XCTAssertTrue(g.isRepositoryLoaded)
        XCTAssertEqual(.ready, g.rootState)
        XCTAssertTrue(repo === g.repository)
        XCTAssertTrue(repo === g.dataSync.active?.repository)
        XCTAssertEqual(.bundled, g.dataSync.active?.source)
        XCTAssertEqual(TestData.repo.sessions.count, repo.sessions.count)
        // Details and routing: one per repository.
        XCTAssertTrue(g.details === g.details)
        XCTAssertTrue(g.router === g.router)
        // A second await returns the same data.
        let again = try await g.awaitRepository()
        XCTAssertTrue(again === repo)
        // Fresh install: the first-run sheet shows once the data is there.
        XCTAssertTrue(g.showsFirstRunSheet)
        g.settings.finishFirstRun(nil)
        XCTAssertFalse(g.showsFirstRunSheet)
        // Every store uses its Kotlin prefs file.
        XCTAssertEqual(
            [DataSync.PREFS, FakeableClock.PREFS, GoingStore.PREFS, ReminderStore.PREFS, SettingsStore.PREFS].sorted(),
            f.prefs.names
        )
    }

    func testAwaitRepositoryWithoutStartLoadsToo() async throws {
        let g = fixture().graph
        let repo = try await g.awaitRepository()
        XCTAssertTrue(g.isRepositoryLoaded)
        XCTAssertTrue(repo === g.repository)
    }

    func testRepositoryBeforeTheLoadFinishesBlocksLikeKotlinsLazy() {
        let g = fixture().graph
        // No start(): the first read loads synchronously.
        XCTAssertEqual(TestData.repo.sessions.count, g.repository.sessions.count)
        XCTAssertTrue(g.repository === g.dataSync.active?.repository)
    }

    func testBrokenBundledDataShowsTheError() async {
        struct Missing: Error {}
        let f = fixture(bundled: { _ in throw Missing() })
        let g = f.graph
        g.start()
        do {
            _ = try await g.awaitRepository()
            XCTFail("expected an error")
        } catch {
            // expected
        }
        XCTAssertFalse(g.isRepositoryLoaded)
        guard case .failed(let text) = g.rootState else { return XCTFail("\(g.rootState)") }
        XCTAssertTrue(text.hasPrefix("Couldn’t load the schedule data: "), text)
        XCTAssertEqual(g.loadError, text)
        XCTAssertFalse(g.showsFirstRunSheet)
        // The reminders don't throw either.
        await settle(g)
        XCTAssertEqual([], f.center.pendingIds)
    }

    func testANewerDataSetIsSwappedInWholeWithNewDetailsRouterAndReminders() async throws {
        let f = fixture(speakingAs: lucy)
        let g = f.graph
        // Publish the same files as a newer version.
        let manifestURL = TestData.assetsDir.appendingPathComponent(DataManifest.FILE)
        guard case .object(var m) = try JSON.parse(Data(contentsOf: manifestURL)) else { return XCTFail("manifest") }
        let bundledVersion = try XCTUnwrap(m["version"]?.intValue)
        m["version"] = .number(JSONNumber(bundledVersion + 1))
        f.fetcher.serve(AppGraphTests.BASE + DataManifest.FILE, Data(JSON.serialize(.object(m)).utf8))

        g.start()
        let first = try await g.awaitRepository()
        let firstDetails = g.details
        let firstRouter = g.router
        await settle(g)
        let runs = g.reminders.runs

        g.onForeground() // the first foreground checks
        await eventually("the swap") { g.repository !== first }
        XCTAssertEqual(bundledVersion + 1, g.dataSync.active?.version)
        XCTAssertEqual(.github, g.dataSync.active?.source)
        XCTAssertTrue(g.repository === g.dataSync.active?.repository)
        XCTAssertFalse(g.details === firstDetails)
        XCTAssertFalse(g.router === firstRouter)
        XCTAssertTrue(g.details === g.details)
        // The reminders were re-planned for the new data.
        await eventually("a reschedule") { g.reminders.runs > runs }
        await settle(g)
        XCTAssertEqual(Set(lucysKeys(at: "2026-11-10T12:00:00-07:00")), Set(f.center.pendingIds))
        XCTAssertEqual([AppGraphTests.BASE + DataManifest.FILE], f.fetcher.requests)
    }

    // MARK: - Reminders

    func testLaunchSchedulesTheReminders() async {
        let f = fixture(speakingAs: lucy)
        f.graph.start()
        await settle(f.graph)
        XCTAssertEqual(lucysKeys(at: "2026-11-10T12:00:00-07:00"), f.center.pendingIds)
        XCTAssertEqual(Set(lucysKeys(at: "2026-11-10T12:00:00-07:00")), f.graph.reminderStore.armed())
        XCTAssertEqual(1, f.graph.reminders.runs)
    }

    func testRemindersFollowSpeakingAsStarsAndTheLeadTime() async {
        let f = fixture()
        let g = f.graph
        g.start()
        await settle(g)
        XCTAssertEqual([], f.center.pendingIds)

        g.settings.setSpeakingAs(lucy)
        await eventually("Lucy's talks") { f.center.pendingIds.count == 6 }
        g.going.setGoing("1203350", true)
        await eventually("the star") { f.center.pendingIds.contains("1203350/10") }
        g.going.setRemindMinutes(15)
        await eventually("the new lead time") { f.center.pendingIds.contains("1203350/15") }
        await settle(g)
        XCTAssertFalse(f.center.pendingIds.contains("1203350/10"))
        g.going.setRemindMinutes(GoingStore.REMIND_OFF)
        await eventually("Off") { !f.center.pendingIds.contains("1203350/15") }
        g.settings.setSpeakingAs(nil)
        await eventually("None") { f.center.pendingIds.isEmpty }
        await settle(g)
        XCTAssertEqual([], g.reminderStore.armed())
    }

    func testForegroundReplansAndChecksForData() async {
        let f = fixture(speakingAs: lucy)
        let g = f.graph
        g.start()
        await settle(g)
        let runs = g.reminders.runs

        g.onForeground()
        await eventually("the manifest check") { f.fetcher.requests.count == 1 }
        await settle(g)
        XCTAssertGreaterThan(g.reminders.runs, runs)
        g.onBackground()
        // Back within 15 minutes: no second check, but the reminders are re-planned.
        let runs2 = g.reminders.runs
        g.onForeground()
        await settle(g)
        XCTAssertGreaterThan(g.reminders.runs, runs2)
        XCTAssertEqual(1, f.fetcher.requests.count)
        g.onBackground()
    }

    func testTheFakeTimeLaunchArgumentAndItsChangesReplan() async throws {
        // The real FakeableClock (no override), debug build.
        let f = fixture(at: nil, speakingAs: lucy)
        let g = f.graph
        g.start(arguments: ["/app/KCNA26", "-fakeNow", "2026-11-10T12:00:00-07:00"])
        XCTAssertTrue(g.fakeableClock.isFaked)
        XCTAssertLessThan(abs(g.clock.now().timeIntervalSince(TestData.instant("2026-11-10T12:00:00-07:00"))), 5)
        XCTAssertTrue(f.logs.value.contains { $0.hasPrefix("fakeNow=2026-11-10T12:00:00-07:00 applied=true") })
        await settle(g)
        XCTAssertEqual(lucysKeys(at: "2026-11-10T12:00:00-07:00"), f.center.pendingIds)
        // Fire dates are real time: the planned trigger minus the fake offset.
        let r = try XCTUnwrap(f.center.request("1249844/10"))
        let offset = Double(g.fakeableClock.offsetMillis) / 1000
        XCTAssertEqual(TestData.instant("2026-11-11T14:10:00-07:00").addingTimeInterval(-offset).timeIntervalSince1970, r.fireDate.timeIntervalSince1970, accuracy: 2)

        // Moving the fake time re-plans: at 14:00 on Wednesday only three are left.
        XCTAssertTrue(g.fakeableClock.applyFakeNowArg("2026-11-11T14:00:00-07:00"))
        await eventually("the re-plan") { f.center.pendingIds.count == 3 }
        XCTAssertEqual(["1249844/10", "1289660/30", "1289660/10"], f.center.pendingIds)
    }

    func testReleaseBuildsIgnoreTheFakeTimeArgument() {
        let f = fixture(at: nil, isDebug: false)
        f.graph.start(arguments: ["/app/KCNA26", "-fakeNow", "2026-11-10T12:00:00-07:00"])
        XCTAssertFalse(f.graph.fakeableClock.isFaked)
        XCTAssertLessThan(abs(f.graph.clock.now().timeIntervalSinceNow), 5)
        XCTAssertFalse(f.logs.value.contains { $0.hasPrefix("fakeNow=") })
    }

    func testStartRunsOnce() async {
        let f = fixture(speakingAs: lucy)
        f.graph.start()
        f.graph.start()
        await settle(f.graph)
        XCTAssertEqual(1, f.graph.reminders.runs)
        // One watch per value: one change, one re-plan.
        f.graph.going.setGoing("1203350", true)
        await eventually("the star") { f.center.pendingIds.contains("1203350/10") }
        await settle(f.graph)
        XCTAssertEqual(2, f.graph.reminders.runs)
    }

    // MARK: - Notifications

    func testATappedReminderOpensDirectionsInTheScene() async throws {
        let f = fixture(speakingAs: lucy)
        let g = f.graph
        g.start()
        await settle(g)
        let nav = NavModel(InMemoryStore())
        nav.openSettings()
        XCTAssertFalse(g.routePendingDirections(to: nav))

        // The delegate reads the session from the delivered content.
        let request = try XCTUnwrap(f.center.request("1249844/10"))
        let id = try XCTUnwrap(ReminderContent.directionsSessionId(request.content.userInfo))
        g.notificationTapped(sessionId: id)
        XCTAssertEqual("1249844", g.pendingDirectionsSessionId)
        XCTAssertTrue(g.routePendingDirections(to: nav))
        XCTAssertEqual([Screen.schedule, Screen.directions("1249844")], nav.stack)
        XCTAssertEqual("1249844", nav.openSessionId)
        XCTAssertNil(g.pendingDirectionsSessionId)
        // Routed once.
        XCTAssertFalse(g.routePendingDirections(to: nav))
        XCTAssertNil(g.takePendingDirections())
    }

    func testAForegroundReminderIsCheckedWhenItFires() async {
        let f = fixture(at: "2026-11-11T14:10:00-07:00", speakingAs: lucy)
        let g = f.graph
        g.start()
        let gi = TestData.repo.session("1249844")!
        let shown = await g.reminderFiring(sessionId: "1249844", minutesBefore: 10)
        XCTAssertEqual(
            .show(title: "Kubernetes The Hard Way - Live", text: "Your talk in 10 min · Grand Ballroom GI, Level 1", channelId: "your_talks", expiresAt: gi.effectiveEnd),
            shown
        )
        XCTAssertTrue(f.logs.value.contains("reminders: 1249844/10 \"Your talk in 10 min · Grand Ballroom GI, Level 1\" posted=true"))
        g.settings.setSpeakingAs(nil)
        let dropped = await g.reminderFiring(sessionId: "1249844", minutesBefore: 10)
        XCTAssertEqual(.notWanted, dropped)
        let stale = await g.reminderFiring(sessionId: "1249844", minutesBefore: 30)
        XCTAssertEqual(.notWanted, stale)
    }

    func testPermissionIsAskedWhenTheUserPicksANameThenOnlyOnce() async {
        let f = fixture(permission: .notDetermined, holdPermission: true)
        let g = f.graph
        g.start()
        g.onForeground()
        await settle(g)
        // Nothing planned (None, no stars): no ask at start.
        try? await Task.sleep(nanoseconds: 50_000_000)
        var asked = await f.permission.requests
        XCTAssertEqual(0, asked)
        XCTAssertFalse(g.settings.notificationPermissionAsked)

        // Picking a name asks (the dialog is up until the user answers).
        g.settings.setSpeakingAs(lucy)
        await eventually("the ask") { g.settings.notificationPermissionAsked }
        await eventually("the dialog") { NotificationAsk.asking }
        await eventually("Lucy's talks") { f.center.pendingIds.count == 6 }
        await settle(g)
        let runs = g.reminders.runs
        await f.permission.release()
        // Granted: the reminders are re-planned once more.
        await eventually("the re-plan after the grant") { g.reminders.runs == runs + 1 }
        XCTAssertFalse(NotificationAsk.asking)
        asked = await f.permission.requests
        XCTAssertEqual(1, asked)

        // Later triggers don't ask again.
        g.going.setGoing("1203350", true)
        await eventually("the star") { f.center.pendingIds.contains("1203350/10") }
        try? await Task.sleep(nanoseconds: 20_000_000)
        asked = await f.permission.requests
        XCTAssertEqual(1, asked)
        g.onBackground()
    }

    func testPlannedRemindersAskForPermissionWhenTheAppComesForward() async {
        let f = fixture(speakingAs: lucy, permission: .notDetermined, holdPermission: true)
        let g = f.graph
        g.start()
        g.onForeground()
        await eventually("the ask") { g.settings.notificationPermissionAsked }
        await settle(g)
        let runs = g.reminders.runs
        await f.permission.release()
        await eventually("the re-plan after the grant") { g.reminders.runs == runs + 1 }
        var asked = await f.permission.requests
        XCTAssertEqual(1, asked)
        g.onBackground()
        // The next foreground doesn't ask again.
        g.onForeground()
        await settle(g)
        try? await Task.sleep(nanoseconds: 20_000_000)
        asked = await f.permission.requests
        XCTAssertEqual(1, asked)
        g.onBackground()
    }

    func testARefusedPermissionDoesNotReplan() async {
        let f = fixture(speakingAs: lucy, permission: .notDetermined)
        let g = f.graph
        await f.permission.setGrants(false)
        g.start()
        g.onForeground()
        await eventually("the ask") { g.settings.notificationPermissionAsked }
        await eventually("the answer") { !NotificationAsk.asking }
        await settle(g)
        let runs = g.reminders.runs
        try? await Task.sleep(nanoseconds: 50_000_000)
        await settle(g)
        XCTAssertEqual(runs, g.reminders.runs)
        g.onBackground()
    }

    func testTurnOnAsksNowAndReplansWhenGranted() async {
        let f = fixture(speakingAs: lucy, permission: .notDetermined)
        let g = f.graph
        g.start()
        await settle(g)
        let status = await g.notificationPermission.status()
        XCTAssertEqual(.requestAuthorization, NotificationAsk.turnOn(status))
        let runs = g.reminders.runs
        let granted = await g.requestNotificationsNow()
        XCTAssertTrue(granted)
        XCTAssertTrue(g.settings.notificationPermissionAsked)
        await settle(g)
        XCTAssertEqual(runs + 1, g.reminders.runs)
        let after = await g.notificationPermission.status()
        XCTAssertEqual(.authorized, after)
    }

    func testNoAskWhileInTheBackground() async {
        let f = fixture(permission: .notDetermined)
        let g = f.graph
        g.start()
        g.onForeground()
        await settle(g)
        g.onBackground()
        g.settings.setSpeakingAs(lucy)
        await settle(g)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let asked = await f.permission.requests
        XCTAssertEqual(0, asked)
        XCTAssertFalse(g.settings.notificationPermissionAsked)
        // The reminders still follow.
        await eventually("Lucy's talks") { f.center.pendingIds.count == 6 }
    }

    // MARK: - Live services

    func testLiveServicesUseApplicationSupportAndTheKotlinPrefsNames() {
        let s = AppServices.live(reminders: FakeReminderCenter(), notificationPermission: FakePermission(.authorized), isDebug: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.filesDirectory.path))
        XCTAssertEqual(AppServices.applicationSupportDirectory(), s.filesDirectory)
        XCTAssertEqual(SettingsStore.PREFS, (s.prefs(SettingsStore.PREFS) as? UserDefaultsStore)?.suiteName)
        XCTAssertEqual(DataSync.baseUrl(from: .main), s.dataBaseUrl)
        XCTAssertFalse(s.isDebug)
        XCTAssertNil(s.clockOverride)
        XCTAssertTrue(s.wallClock is SystemAppClock)
        XCTAssertEqual(AppServices.KCNA_TAG, "kcna26")
    }
}
