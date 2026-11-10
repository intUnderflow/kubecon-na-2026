#if DEBUG
import Foundation

/// Debug builds only: the app states the screenshot script (`ios/scripts/screenshots.sh`, run by
/// `.github/workflows/ios-screenshots.yml`) captures, the iOS twins of the Android screenshots in
/// `docs/screenshots/`. One scene per launch, chosen with the launch argument
/// `-screenshotScene <name>`:
///
/// ```
/// xcrun simctl launch <udid> app.kcna26 -screenshotScene list-detail
/// ```
///
/// Every scene speaks as Lucy Sweet (first run answered), RSVPs to the same sessions as the
/// Android shots, reminds 10 minutes before, routes from "My location" and runs at a fake time
/// (Wednesday 1:30 PM, or Monday 10:30 AM for the co-located events). Dark mode comes from the
/// simulator's appearance, so "schedule" also makes the dark shot.
///
/// The app side (`KCNA26/Sources/App/ScreenshotMode.swift`) applies a scene at launch:
/// ``services(_:)`` (offline, no notification prompt or hint, no reminders), then
/// ``apply(settings:going:clock:)`` before ``AppGraph/start(arguments:)``, ``navSaved`` for the
/// window's ``NavModel``, ``scheduleSeed`` for the Schedule screen's saved state and scroll, and
/// ``location`` / ``heading`` for Directions (the simulator has no compass; the script also
/// sets the simulator's location to ``location``).
struct ScreenshotScene: Sendable, Hashable {
    /// Where the Schedule list starts.
    enum Scroll: Sendable, Hashable {
        /// The top (search box, banners).
        case top
        /// The day heading at the top of the list (the banners scrolled away).
        case dayHeading
        /// A banner-style jump to the session (Kotlin `onTalk` without opening it): its row
        /// lands under its pinned heading, a group card's kid is revealed.
        case session(String)
    }

    /// The Schedule screen's saved state (its `@SceneStorage`) and where its list starts.
    struct ScheduleSeed: Sendable, Hashable {
        /// The selected day tab; nil = today (``ScheduleLogic/resolveDayKey(_:_:_:)``).
        let selectedDay: String?
        /// Group cards shown in full (group keys).
        let expanded: Set<String>
        /// Co-located event cards with their agenda open (event keys).
        let coloOpen: Set<String>
        let scroll: Scroll

        init(selectedDay: String? = nil, expanded: Set<String> = [], coloOpen: Set<String> = [], scroll: Scroll = .top) {
            self.selectedDay = selectedDay
            self.expanded = expanded
            self.coloOpen = coloOpen
            self.scroll = scroll
        }

        /// The jump of a ``Scroll/session(_:)`` scroll (Kotlin `onTalk`: the talk's day, its
        /// co-located card opened, the jump); nil for other scrolls or an unknown session.
        func talkTap(_ index: ScheduleIndex) -> ScheduleScreenLogic.TalkTap? {
            guard case .session(let id) = scroll, let s = index.repo.session(id) else { return nil }
            return ScheduleScreenLogic.onTalk(index, s, coloOpen)
        }
    }

    /// A GPS fix (WGS84) with its horizontal accuracy.
    struct Location: Sendable, Hashable {
        let latitude: Double
        let longitude: Double
        let accuracyM: Double
    }

    /// The `-screenshotScene` value.
    let name: String
    /// The fake time (``FakeableClock/applyFakeNowArg(_:)``), an offset date-time.
    let fakeNow: String
    /// "I’m speaking as" (nil = None); the first-run picker counts as answered.
    let speakingAs: String?
    /// The RSVP'd sessions, exactly (others are unstarred).
    let goingIds: [String]
    /// Reminder lead time (``GoingStore/REMIND_OPTIONS``).
    let remindMinutes: Int
    /// The Directions "From" choice (``SettingsStore/FROM_LIVE`` = My location).
    let directionsFrom: String
    /// The screens pushed over the Schedule.
    let screens: [Screen]
    /// The session whose details are open (sheet or pane).
    let openSessionId: String?
    let scheduleSeed: ScheduleSeed
    /// Directions: a fix fed to the screen's view model at once (the script also sets the
    /// simulator's location to it).
    let location: Location?
    /// Directions: a true heading for the map's cone (the simulator has no compass).
    let heading: Double?

    init(
        name: String,
        fakeNow: String = ScreenshotScene.WEDNESDAY,
        speakingAs: String? = ScreenshotScene.SPEAKING_AS,
        goingIds: [String] = ScreenshotScene.RSVPS,
        remindMinutes: Int = GoingStore.DEFAULT_REMIND_MINUTES,
        directionsFrom: String = SettingsStore.FROM_LIVE,
        screens: [Screen] = [],
        openSessionId: String? = nil,
        scheduleSeed: ScheduleSeed = ScheduleSeed(),
        location: Location? = nil,
        heading: Double? = nil
    ) {
        self.name = name
        self.fakeNow = fakeNow
        self.speakingAs = speakingAs
        self.goingIds = goingIds
        self.remindMinutes = remindMinutes
        self.directionsFrom = directionsFrom
        self.screens = screens
        self.openSessionId = openSessionId
        self.scheduleSeed = scheduleSeed
        self.location = location
        self.heading = heading
    }

    // MARK: - The scenes

    /// The launch argument.
    static let ARGUMENT = "-screenshotScene"

    /// Wednesday 1:30 PM: Kubernetes Meet + Greet is on, the next RSVP is in 10 minutes, Lucy
    /// Sweet speaks at 2:20.
    static let WEDNESDAY = "2026-11-11T13:30:00-07:00"
    /// Monday 10:30 AM: the co-located events' coffee break.
    static let MONDAY = "2026-11-09T10:30:00-07:00"
    static let SPEAKING_AS: String = SettingsStore.DEFAULT_SPEAKER

    /// Kubernetes Meet + Greet (Wed), the Kubeflow Summit's "Building Reproducible AgentOps
    /// Pipelines…" (Wed), "What monday.com's 500+ Engineers…" (Thu), and ArgoCon's "Beating the
    /// Final Boss: GitOps Promoter in Production" and "Securing the Repo Server…" (Mon).
    static let RSVPS: [String] = ["1342434", "1333709", "1248305", "1269659", "1265272"]

    /// ArgoCon (colocated.json), opened on Monday.
    static let ARGOCON = "colo-argocon"
    /// The session sheet (iPhone).
    static let SESSION = "1248305"
    /// The list–detail selection (iPad).
    static let LIST_DETAIL_SESSION = "1333709"
    /// "In-Place Pod Resizing Like I'm 5: Scaling Without Restarts", Regency Ballroom B (Hyatt L4).
    static let DIRECTIONS_SESSION = "1251049"

    /// The local point (metres east / north of the wayfinding origin) the Directions fix stands
    /// on: in the Salt Palace by the North Foyer (the nearest start node), about 190 m north of
    /// Regency Ballroom B (x −54, y 70), so the readout says "190 m south".
    static let DIRECTIONS_LOCAL = PointXY(-75, 255)

    /// ``DIRECTIONS_LOCAL`` in WGS84 (``latLng(_:_:)`` with wayfinding.json's origin, rounded to
    /// 6 decimals, ~0.1 m), ±12 m like the Android shot. The script's `simctl location set`
    /// uses the same numbers (a test keeps them equal).
    static let DIRECTIONS_LOCATION = Location(latitude: 40.767297, longitude: -111.89489, accuracyM: 12)

    /// The heading cone's direction (true north-north-east, as in the Android shot).
    static let DIRECTIONS_HEADING = 20.0

    static let schedule = ScreenshotScene(name: "schedule")
    static let monday = ScreenshotScene(
        name: "monday",
        fakeNow: MONDAY,
        scheduleSeed: ScheduleSeed(coloOpen: [ARGOCON], scroll: .dayHeading)
    )
    static let session = ScreenshotScene(name: "session", openSessionId: SESSION)
    static let directions = ScreenshotScene(
        name: "directions",
        screens: [.directions(DIRECTIONS_SESSION)],
        location: DIRECTIONS_LOCATION,
        heading: DIRECTIONS_HEADING
    )
    static let listDetail = ScreenshotScene(
        name: "list-detail",
        openSessionId: LIST_DETAIL_SESSION,
        scheduleSeed: ScheduleSeed(scroll: .session(LIST_DETAIL_SESSION))
    )
    static let ipadDirections = ScreenshotScene(
        name: "ipad-directions",
        screens: [.directions(DIRECTIONS_SESSION)],
        location: DIRECTIONS_LOCATION,
        heading: DIRECTIONS_HEADING
    )

    /// Every scene, in the script's order.
    static let all: [ScreenshotScene] = [schedule, monday, session, directions, listDetail, ipadDirections]

    // MARK: - Parsing

    /// The value after the last `-screenshotScene` (or `--screenshotScene`) in `arguments`
    /// (`ProcessInfo.processInfo.arguments`); nil if there is none or nothing follows it.
    static func argument(_ arguments: [String]) -> String? {
        var value: String?
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if (a == ARGUMENT || a == "-" + ARGUMENT) && i + 1 < arguments.count {
                value = arguments[i + 1]
                i += 2
                continue
            }
            i += 1
        }
        return value
    }

    /// The scene called `name` (surrounding whitespace ignored); nil if there is none.
    static func named(_ name: String) -> ScreenshotScene? {
        let n = name.kotlinTrim()
        return all.first { $0.name == n }
    }

    /// The scene the launch arguments ask for; nil for a normal run (or an unknown name).
    static func from(arguments: [String]) -> ScreenshotScene? {
        argument(arguments).flatMap { named($0) }
    }

    // MARK: - Applying

    /// The fake time as an instant (nil only if ``fakeNow`` doesn't parse).
    var fakeNowDate: Date? { try? parseOffsetDateTime(fakeNow) }

    /// Puts the stores into the scene's state (call before ``AppGraph/start(arguments:)``): the
    /// speaker (first run answered), notification permission marked as asked, the From choice,
    /// exactly ``goingIds`` starred, the reminder time, the fake time.
    @MainActor
    func apply(settings: SettingsStore, going: GoingStore, clock: FakeableClock) {
        settings.setSpeakingAs(speakingAs)
        settings.finishFirstRun(nil)
        settings.notificationPermissionAsked = true
        settings.setDirectionsFrom(directionsFrom)
        let wanted = Set(goingIds)
        for id in going.ids.sorted() where !wanted.contains(id) {
            going.setGoing(id, false)
        }
        for id in goingIds {
            going.setGoing(id, true)
        }
        going.setRemindMinutes(remindMinutes)
        clock.applyFakeNowArg(fakeNow)
    }

    /// The window's navigation state: the Schedule, ``screens`` over it, ``openSessionId``.
    @MainActor
    var navSaved: NavModel.Saved {
        let keys: [String] = ([Screen.schedule] + screens).map(\.key)
        return NavModel.Saved(stack: NavModel.encodeKeys(keys), session: openSessionId)
    }

    /// `base` with the screenshot stand-ins: no network (the bundled data and descriptions stay,
    /// nothing swaps in mid-shot), notifications that read as allowed (no system dialog, no
    /// "notifications are off" hint) and no reminder notifications.
    static func services(_ base: AppServices) -> AppServices {
        var s = base
        s.dataFetcher = ScreenshotDataFetcher()
        s.detailsFetcher = ClosureDetailsFetcher { _ in .notFound }
        s.reminders = ScreenshotReminders()
        s.notificationPermission = ScreenshotNotificationPermission()
        return s
    }

    /// Local metres -> WGS84 (the inverse of ``Geo/toLocal(_:_:_:)``).
    static func latLng(_ p: PointXY, _ origin: Origin) -> (latitude: Double, longitude: Double) {
        (origin.lat0 + p.y / origin.metersPerDegLat, origin.lon0 + p.x / origin.metersPerDegLon)
    }
}

/// Screenshots: notifications read as allowed, and asking grants at once (no system dialog).
struct ScreenshotNotificationPermission: NotificationPermission {
    func status() async -> NotificationAsk.Authorization { .authorized }
    func request() async -> Bool { true }
}

/// Screenshots: no reminder notifications (none can show over a shot).
struct ScreenshotReminders: ReminderScheduling {
    func pendingIdentifiers() async -> [String] { [] }
    func add(_ request: ReminderRequest) async throws {}
    func removePending(_ identifiers: [String]) async {}
    func delivered() async -> [DeliveredReminder] { [] }
    func removeDelivered(_ identifiers: [String]) async {}
}

/// Screenshots: data updates are offline, so the bundled data stays.
struct ScreenshotDataFetcher: DataFetcher {
    func get(_ url: String, ifNoneMatch: String?, maxBytes: Int64) async -> HttpResult {
        .failed("screenshot scene: offline")
    }
}
#endif
