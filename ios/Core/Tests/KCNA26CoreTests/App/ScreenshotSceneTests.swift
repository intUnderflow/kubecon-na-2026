#if DEBUG
import Foundation
import XCTest
@testable import KCNA26Core

/// The debug screenshot scenes (`-screenshotScene <name>`): the launch argument, every session
/// they name exists in the bundled data, each scene shows what the Android screenshot shows,
/// the Directions fix reads "190 m south", and the scenes run offline with no notification
/// prompt or hint.
@MainActor
final class ScreenshotSceneTests: XCTestCase {
    private var repo: Repository { TestData.repo }

    // MARK: - Parsing

    func testArgumentIsTheValueAfterTheFlag() {
        XCTAssertEqual("schedule", ScreenshotScene.argument(["/app/KCNA26", "-screenshotScene", "schedule"]))
        XCTAssertEqual("monday", ScreenshotScene.argument(["/app/KCNA26", "--screenshotScene", "monday"]))
        // The last one wins; other arguments (e.g. -fakeNow) are skipped.
        XCTAssertEqual(
            "list-detail",
            ScreenshotScene.argument(["x", "-screenshotScene", "session", "-fakeNow", "clear", "-screenshotScene", "list-detail"])
        )
        XCTAssertEqual("session", ScreenshotScene.argument(["x", "-screenshotScene", "session", "-screenshotScene"]))
        XCTAssertNil(ScreenshotScene.argument(["/app/KCNA26"]))
        XCTAssertNil(ScreenshotScene.argument(["/app/KCNA26", "-screenshotScene"]))
        XCTAssertNil(ScreenshotScene.argument(["x", "-screenshotSceneX", "schedule", "screenshotScene", "schedule"]))
        XCTAssertNil(ScreenshotScene.argument([]))
        XCTAssertEqual("-screenshotScene", ScreenshotScene.ARGUMENT)
    }

    func testScenesAreFoundByName() throws {
        let names: [String] = ScreenshotScene.all.map(\.name)
        XCTAssertEqual(["schedule", "monday", "session", "directions", "list-detail", "ipad-directions"], names)
        XCTAssertEqual(names.count, Set(names).count)
        for scene in ScreenshotScene.all {
            XCTAssertEqual(scene, ScreenshotScene.named(scene.name))
            XCTAssertEqual(scene, ScreenshotScene.from(arguments: ["app", ScreenshotScene.ARGUMENT, scene.name]))
        }
        XCTAssertEqual(ScreenshotScene.monday, ScreenshotScene.named(" monday\n"))
        XCTAssertEqual(ScreenshotScene.listDetail, ScreenshotScene.from(arguments: ["app", "-fakeNow", "clear", "-screenshotScene", "list-detail"]))
        // Unknown names and normal runs: no scene.
        XCTAssertNil(ScreenshotScene.named("dark-schedule"))
        XCTAssertNil(ScreenshotScene.named("Schedule"))
        XCTAssertNil(ScreenshotScene.named(""))
        XCTAssertNil(ScreenshotScene.from(arguments: ["app", "-screenshotScene", "nope"]))
        XCTAssertNil(ScreenshotScene.from(arguments: ["app"]))
        XCTAssertNil(ScreenshotScene.from(arguments: ["app", "-fakeNow", "2026-11-11T09:00:00-07:00"]))
    }

    // MARK: - The data they name

    func testEverySessionTheScenesNameExistsInTheBundledData() throws {
        for scene in ScreenshotScene.all {
            var ids: [String] = scene.goingIds
            if let id = scene.openSessionId { ids.append(id) }
            ids += scene.screens.compactMap(\.sessionId)
            if case .session(let id) = scene.scheduleSeed.scroll { ids.append(id) }
            XCTAssertFalse(ids.isEmpty, scene.name)
            for id in ids {
                XCTAssertNotNil(repo.session(id), "\(scene.name): session \(id) is not in the bundled data")
            }
            for key in scene.scheduleSeed.coloOpen {
                XCTAssertNotNil(repo.coloEvent(key), "\(scene.name): co-located event \(key)")
            }
            if let day = scene.scheduleSeed.selectedDay {
                XCTAssertNotNil(repo.day(day), "\(scene.name): day \(day)")
            }
            XCTAssertTrue(GoingStore.REMIND_OPTIONS.contains(scene.remindMinutes), scene.name)
            if let me = scene.speakingAs {
                XCTAssertTrue(repo.allSpeakers.contains(me), "\(scene.name): speaker \(me)")
                XCTAssertFalse(repo.mySessions(me).isEmpty, scene.name)
            }
        }
    }

    func testTheRsvpsAreTheAndroidScreenshotsStars() throws {
        XCTAssertEqual(ScreenshotScene.RSVPS.count, Set(ScreenshotScene.RSVPS).count)
        func session(_ id: String) throws -> Session { try XCTUnwrap(repo.session(id), id) }
        XCTAssertEqual("Kubernetes Meet + Greet", try session("1342434").title)
        XCTAssertEqual("wed", try session("1342434").day)
        XCTAssertTrue(try session("1333709").title.hasPrefix("Building Reproducible AgentOps"))
        XCTAssertEqual("wed-kf", try session("1333709").group?.key)
        XCTAssertTrue(try session("1248305").title.hasPrefix("What monday.com's 500+ Engineers"))
        XCTAssertEqual("thu", try session("1248305").day)
        // Monday's ArgoCon talks.
        let boss = try session("1269659")
        XCTAssertEqual("Beating the Final Boss: GitOps Promoter in Production", boss.title)
        let repoServer = try session("1265272")
        XCTAssertTrue(repoServer.title.hasPrefix("Securing the Repo Server"))
        let index = ScheduleIndex.of(repo)
        for s in [boss, repoServer] {
            XCTAssertEqual("mon", s.day)
            XCTAssertEqual(ScreenshotScene.ARGOCON, index.coloEventOf(s)?.key)
        }
        XCTAssertEqual("ArgoCon", repo.coloEvent(ScreenshotScene.ARGOCON)?.name)
        // Directions: Regency Ballroom B, Hyatt Level 4.
        let target = try session(ScreenshotScene.DIRECTIONS_SESSION)
        XCTAssertTrue(target.title.hasPrefix("In-Place Pod Resizing Like I'm 5"))
        let room = try XCTUnwrap(repo.roomOf(target))
        XCTAssertEqual("Regency Ballroom B", room.name)
        XCTAssertEqual("Hyatt L4", room.buildingLabel)
        XCTAssertEqual(4, room.level)
    }

    func testTheFakeTimesFallOnWednesdayAfternoonAndMondayMorning() throws {
        let index = ScheduleIndex.of(repo)
        for scene in ScreenshotScene.all {
            let now = try XCTUnwrap(scene.fakeNowDate, scene.name)
            let dayKey = ScheduleLogic.resolveDayKey(index.days, ScheduleLogic.minuteOf(now), scene.scheduleSeed.selectedDay)
            XCTAssertEqual(scene.name == "monday" ? "mon" : "wed", dayKey, scene.name)
        }
        let wed = try XCTUnwrap(ScreenshotScene.schedule.fakeNowDate).localDateTime
        XCTAssertEqual("2026-11-11", wed.date.description)
        XCTAssertEqual(13 * 60 + 30, wed.minuteOfDay)
        let mon = try XCTUnwrap(ScreenshotScene.monday.fakeNowDate).localDateTime
        XCTAssertEqual("2026-11-09", mon.date.description)
        XCTAssertEqual(10 * 60 + 30, mon.minuteOfDay)
    }

    // MARK: - Applying a scene

    func testApplyPutsTheStoresIntoTheScene() throws {
        let settingsPrefs = InMemoryStore()
        let goingPrefs = InMemoryStore()
        let clockPrefs = InMemoryStore()
        // A previous run: another speaker, other stars, reminders off, an entrance as From.
        let before = SettingsStore(settingsPrefs)
        XCTAssertTrue(before.firstRunPending)
        let oldGoing = GoingStore(goingPrefs)
        oldGoing.setGoing("1344383", true)
        oldGoing.setGoing("1342434", true)
        oldGoing.setRemindMinutes(GoingStore.REMIND_OFF)
        before.setDirectionsFrom("EWT")

        let settings = SettingsStore(settingsPrefs)
        let going = GoingStore(goingPrefs)
        let clock = FakeableClock(clockPrefs, allowFake: true)
        let scene = ScreenshotScene.directions
        scene.apply(settings: settings, going: going, clock: clock)

        XCTAssertEqual("Lucy Sweet", settings.speakingAs)
        XCTAssertFalse(settings.firstRunPending)
        XCTAssertTrue(settings.notificationPermissionAsked)
        XCTAssertEqual(SettingsStore.FROM_LIVE, settings.directionsFrom)
        XCTAssertEqual(Set(ScreenshotScene.RSVPS), going.ids)
        XCTAssertEqual(10, going.remindMinutes)
        let fake = try XCTUnwrap(scene.fakeNowDate)
        XCTAssertLessThan(abs(clock.now().timeIntervalSince(fake)), 5)
        XCTAssertTrue(clock.isFaked)

        // Written through: a cold start reads the same state (the first-run sheet stays away).
        let reread = SettingsStore(settingsPrefs)
        XCTAssertEqual("Lucy Sweet", reread.speakingAs)
        XCTAssertFalse(reread.firstRunPending)
        XCTAssertEqual(Set(ScreenshotScene.RSVPS), GoingStore(goingPrefs).ids)

        // Monday: the clock moves to Monday; applying again changes nothing else.
        ScreenshotScene.monday.apply(settings: settings, going: going, clock: clock)
        let monday = try XCTUnwrap(ScreenshotScene.monday.fakeNowDate)
        XCTAssertLessThan(abs(clock.now().timeIntervalSince(monday)), 5)
        XCTAssertEqual(Set(ScreenshotScene.RSVPS), going.ids)
        XCTAssertEqual("Lucy Sweet", settings.speakingAs)
    }

    func testNavigationOpensTheScenesScreen() throws {
        func nav(_ scene: ScreenshotScene) -> NavModel { NavModel(restoring: scene.navSaved) }
        for scene in [ScreenshotScene.schedule, ScreenshotScene.monday] {
            XCTAssertEqual([.schedule], nav(scene).stack, scene.name)
            XCTAssertNil(nav(scene).openSessionId, scene.name)
        }
        XCTAssertEqual([.schedule], nav(ScreenshotScene.session).stack)
        XCTAssertEqual("1248305", nav(ScreenshotScene.session).openSessionId)
        XCTAssertEqual([.schedule], nav(ScreenshotScene.listDetail).stack)
        XCTAssertEqual("1333709", nav(ScreenshotScene.listDetail).openSessionId)
        for scene in [ScreenshotScene.directions, ScreenshotScene.ipadDirections] {
            let n = nav(scene)
            XCTAssertEqual([.schedule, .directions("1251049")], n.stack, scene.name)
            XCTAssertEqual(.directions("1251049"), n.current, scene.name)
            XCTAssertEqual([.directions("1251049")], n.path, scene.name)
            XCTAssertNil(n.openSessionId, scene.name)
        }
        XCTAssertEqual(#"["schedule","directions:1251049"]"#, ScreenshotScene.directions.navSaved.stack)
    }

    // MARK: - What the schedule shows

    private func state(_ scene: ScreenshotScene, selectedDay: String? = nil) throws -> ScheduleScreenLogic.State {
        let now = try XCTUnwrap(scene.fakeNowDate)
        return ScheduleScreenLogic.state(
            ScheduleIndex.of(repo),
            now,
            scene.speakingAs,
            selectedDay: selectedDay ?? scene.scheduleSeed.selectedDay,
            query: "",
            goingOnly: false,
            goingIds: Set(scene.goingIds),
            unstarred: [],
            remindMinutes: scene.remindMinutes
        )
    }

    /// A phone's list (one co-located column).
    private var phoneColumns: Int {
        ScheduleScreenLogic.listLayout(402, twoPane: false, wideWindow: false).coloColumns
    }

    func testWednesdayShowsTheBannerTheNextRsvpAndTheClash() throws {
        let st = try state(ScreenshotScene.schedule)
        XCTAssertEqual("wed", st.dayKey)
        XCTAssertEqual(["wed", "thu"], st.tabs.map(\.key))
        XCTAssertEqual("1:30 PM MST", st.clock)
        // "You’re speaking": Kubernetes The Hard Way - Live at 2:20.
        let banner = try XCTUnwrap(st.banner)
        XCTAssertEqual("Kubernetes The Hard Way - Live", banner.next.title)
        XCTAssertEqual("In 50 min", banner.countdown)
        // "Your next in 10 min": the Kubeflow Summit talk.
        let next = try XCTUnwrap(st.goingNext)
        XCTAssertEqual("1333709", next.session.id)
        XCTAssertEqual("in 10 min", next.countdown)
        // The Meet + Greet clashes with it.
        XCTAssertTrue(st.clashIds.isSuperset(of: ["1342434", "1333709"]))
        let keys: [String] = st.rows(phoneColumns, []).map(\.key)
        XCTAssertEqual(["search", "mine", "goingnext", "dayhead"], Array(keys.prefix(4)))
    }

    func testMondayOpensArgoConUnderTheDayHeading() throws {
        let scene = ScreenshotScene.monday
        XCTAssertEqual(.dayHeading, scene.scheduleSeed.scroll)
        XCTAssertNil(scene.scheduleSeed.talkTap(ScheduleIndex.of(repo)))
        let st = try state(scene)
        XCTAssertEqual("mon", st.dayKey)
        XCTAssertEqual(["mon", "tue", "wed", "thu"], st.tabs.map(\.key))
        let rows: [ScheduleRow] = st.rows(phoneColumns, scene.scheduleSeed.coloOpen)
        let head = try XCTUnwrap(rows.firstIndex { $0.key == "dayhead" })
        let agenda = try XCTUnwrap(rows.firstIndex { r in
            if case .coloAgenda(let card, _) = r { return card.key == ScreenshotScene.ARGOCON }
            return false
        })
        XCTAssertLessThan(head, agenda)
        guard case .coloAgenda(let card, _) = rows[agenda] else { return XCTFail("no ArgoCon agenda") }
        XCTAssertTrue(card.holds("1269659"))
        XCTAssertTrue(card.holds("1265272"))
        // Closed, the agenda isn't listed.
        XCTAssertFalse(st.rows(phoneColumns, []).contains { r in
            if case .coloAgenda = r { return true }
            return false
        })
    }

    func testListDetailJumpsToTheKubeflowSummitTalk() throws {
        let scene = ScreenshotScene.listDetail
        let index = ScheduleIndex.of(repo)
        let tap = try XCTUnwrap(scene.scheduleSeed.talkTap(index))
        XCTAssertEqual("wed", tap.selectedDay)
        XCTAssertEqual("1333709", tap.jump.id)
        XCTAssertNil(tap.jump.agenda)
        XCTAssertEqual([], tap.coloOpen)
        // The list pane (two-pane: one co-located column).
        let columns = ScheduleScreenLogic.listLayout(400, twoPane: true, wideWindow: true).coloColumns
        let st = try state(scene, selectedDay: tap.selectedDay)
        let rows: [ScheduleRow] = st.rows(columns, tap.coloOpen)
        let i = try XCTUnwrap(ScheduleScreenLogic.jumpTarget(rows, tap.jump))
        guard case .item(let block, _) = rows[i], let group = block.groupBlock else {
            return XCTFail("the jump should land on the Kubeflow Summit card, got \(rows[i].key)")
        }
        XCTAssertEqual("wed-kf", group.group.key)
        XCTAssertTrue(group.kids.contains { $0.id == "1333709" })
        XCTAssertTrue(ScheduleRows.revealsAfterJump(rows[i], "1333709", tap.coloOpen))
        // Short enough to show every talk without "show all".
        XCTAssertLessThanOrEqual(group.kids.count, ScheduleCardsLogic.GROUP_COLLAPSE_OVER)
        // Other scenes don't jump.
        for other in ScreenshotScene.all where other != scene {
            XCTAssertNil(other.scheduleSeed.talkTap(index), other.name)
        }
    }

    // MARK: - Directions

    func testTheDirectionsFixIsAbout190MetresNorthOfTheRoom() throws {
        let origin = repo.wayfinding.origin
        let loc = ScreenshotScene.DIRECTIONS_LOCATION
        // The constants are the local point converted with wayfinding.json's origin.
        let exact = ScreenshotScene.latLng(ScreenshotScene.DIRECTIONS_LOCAL, origin)
        XCTAssertEqual(exact.latitude, loc.latitude, accuracy: 0.000_000_5)
        XCTAssertEqual(exact.longitude, loc.longitude, accuracy: 0.000_000_5)
        let p = Geo.toLocal(loc.latitude, loc.longitude, origin)
        XCTAssertEqual(ScreenshotScene.DIRECTIONS_LOCAL.x, p.x, accuracy: 0.1)
        XCTAssertEqual(ScreenshotScene.DIRECTIONS_LOCAL.y, p.y, accuracy: 0.1)

        // What the screen's view model makes of it.
        let settings = SettingsStore(InMemoryStore())
        settings.setDirectionsFrom(SettingsStore.FROM_LIVE)
        let vm = DirectionsViewModel(
            repo: repo,
            router: Router(repo),
            settings: settings,
            clock: TestData.clockAt(ScreenshotScene.WEDNESDAY),
            sessionId: ScreenshotScene.DIRECTIONS_SESSION
        )
        let room = try XCTUnwrap(vm.room)
        XCTAssertEqual("RB", room.code)
        let target = try XCTUnwrap(vm.target)
        vm.onLocation(LocationReading(
            latitude: loc.latitude, longitude: loc.longitude, horizontalAccuracy: loc.accuracyM,
            altitude: -1, verticalAccuracy: -1, ageSeconds: 0
        ))
        let fix = try XCTUnwrap(vm.fix)
        XCTAssertFalse(vm.noFix)
        let readout = DirectionsLogic.readout(target, try XCTUnwrap(room.level), fix, .searching)
        XCTAssertEqual("190 m south", readout.headline)
        XCTAssertEqual("190 m", readout.distance)
        XCTAssertEqual("south", readout.direction)
        XCTAssertEqual("±12 m", readout.accuracy)
        XCTAssertNil(readout.weakGps)
        XCTAssertFalse(readout.here)
        // The simulator reports ±5 m: still 190 m south.
        let sim = Fix(loc.latitude, loc.longitude, fix.x, fix.y, 5)
        XCTAssertEqual("190 m south", DirectionsLogic.readout(target, 4, sim, .searching).headline)

        // The route starts inside, at the North Foyer, and goes up to the Hyatt's Level 4.
        let start = Router(repo).myLocationStart(fix.x, fix.y)
        guard case .inside(let inside) = start else { return XCTFail("starts outside: \(start.text)") }
        XCTAssertEqual("NF", inside.node)
        XCTAssertTrue(inside.text.hasPrefix("Start from where you are, near the North Foyer (Level 1)."), inside.text)
        let plan = try XCTUnwrap(vm.plan)
        XCTAssertNotNil(plan.route)
        XCTAssertFalse(plan.showFallbackNote)
        XCTAssertTrue(plan.summary.hasPrefix("About "), plan.summary)
        XCTAssertTrue(plan.summary.hasSuffix(" · up 3 levels"), plan.summary)
        XCTAssertEqual(3, plan.route?.levelsChanged)

        // The heading cone: a valid true heading, no calibration hint.
        vm.onHeading(
            trueHeading: ScreenshotScene.DIRECTIONS_HEADING,
            magneticHeading: Geo.norm360(ScreenshotScene.DIRECTIONS_HEADING - Geo.SLC_DECLINATION_DEG),
            headingAccuracy: 10,
            timeMs: 0
        )
        XCTAssertEqual(ScreenshotScene.DIRECTIONS_HEADING, try XCTUnwrap(vm.heading), accuracy: 0.5)
        XCTAssertFalse(vm.calibrate)
    }

    func testTheScriptSetsTheSameLocationAndKnowsEveryScene() throws {
        let url = TestData.repoRoot.appendingPathComponent("ios/scripts/screenshots.sh")
        let script = try String(contentsOf: url, encoding: .utf8)
        let loc = ScreenshotScene.DIRECTIONS_LOCATION
        let latLng = String(format: "%.6f,%.6f", loc.latitude, loc.longitude)
        XCTAssertEqual("40.767297,-111.894890", latLng)
        XCTAssertTrue(script.contains(latLng), "screenshots.sh must set the simulator to \(latLng)")
        XCTAssertTrue(script.contains(ScreenshotScene.ARGUMENT))
        for scene in ScreenshotScene.all {
            XCTAssertTrue(script.contains(scene.name), "screenshots.sh never shoots \(scene.name)")
        }
    }

    // MARK: - Offline and quiet

    func testTheScenesRunOfflineWithoutNotificationPromptsOrHints() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotSceneTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let stores = Locked<[String: InMemoryStore]>([:])
        let assets = TestData.assetsDir
        let base = AppServices(
            filesDirectory: dir,
            prefs: { name in
                stores.withLock { s in
                    if let x = s[name] { return x }
                    let x = InMemoryStore()
                    s[name] = x
                    return x
                }
            },
            bundledData: { name in try Data(contentsOf: assets.appendingPathComponent(name)) },
            dataFetcher: UnusedDataFetcher(),
            detailsFetcher: ClosureDetailsFetcher { _ in XCTFail("fetched details"); return .notFound },
            reminders: FakeReminderCenter(),
            notificationPermission: ScreenshotNotificationPermission(),
            dataBaseUrl: "https://example.test/data/",
            appVersion: 1,
            isDebug: true,
            log: { _ in }
        )
        let services = ScreenshotScene.services(base)
        XCTAssertTrue(services.dataFetcher is ScreenshotDataFetcher)
        XCTAssertTrue(services.reminders is ScreenshotReminders)
        XCTAssertTrue(services.notificationPermission is ScreenshotNotificationPermission)
        let offline: HttpResult = await services.dataFetcher.get("https://example.test/data/manifest.json", ifNoneMatch: nil, maxBytes: 1_000)
        XCTAssertEqual(.failed("screenshot scene: offline"), offline)
        let noFetch: FetchResult = try await services.detailsFetcher.fetch("1248305")
        XCTAssertEqual(.notFound, noFetch)
        let pending: [String] = await services.reminders.pendingIdentifiers()
        XCTAssertEqual([], pending)
        let delivered: [DeliveredReminder] = await services.reminders.delivered()
        XCTAssertEqual([], delivered)

        let graph = AppGraph(services)
        let scene = ScreenshotScene.session
        scene.apply(settings: graph.settings, going: graph.going, clock: graph.fakeableClock)
        graph.start(arguments: ["app", ScreenshotScene.ARGUMENT, scene.name])
        let loaded = try await graph.awaitRepository()
        XCTAssertEqual(.bundled, graph.dataSync.active?.source)
        XCTAssertFalse(graph.showsFirstRunSheet)
        XCTAssertEqual(.ready, graph.rootState)
        // No permission dialog and no "notifications are off" hint.
        let status = await graph.notificationPermission.status()
        XCTAssertEqual(.authorized, status)
        XCTAssertEqual(.nothing, NotificationAsk.blocked(status, graph.settings))
        XCTAssertFalse(NotificationAsk.remindersWaiting(status, graph.settings, graph.going, loaded, graph.clock.now()))
        let asked: Bool? = await NotificationAsk.askOnce(graph.settings, graph.notificationPermission)
        XCTAssertNil(asked)
        // The sheet's and the pane's descriptions are bundled: no network needed.
        for id in [ScreenshotScene.SESSION, ScreenshotScene.LIST_DETAIL_SESSION, ScreenshotScene.DIRECTIONS_SESSION] {
            let result: DetailsResult = await graph.details.load(id)
            guard case .found(let info) = result else { return XCTFail("no bundled details for \(id): \(result)") }
            XCTAssertNotNil(info.description, id)
        }
        // A foreground check stays offline: the bundled data stays.
        graph.onForeground()
        graph.onBackground()
        XCTAssertTrue(graph.repository === loaded)
    }
}

/// A data fetcher that must not be reached (the scene replaces it).
private struct UnusedDataFetcher: DataFetcher {
    func get(_ url: String, ifNoneMatch: String?, maxBytes: Int64) async -> HttpResult {
        XCTFail("the base fetcher was used: \(url)")
        return .failed("base")
    }
}
#endif
