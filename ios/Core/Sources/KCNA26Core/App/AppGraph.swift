import Foundation
import Observation

/// The app's shared objects and their wiring (Kotlin `interface AppGraph` and its implementation
/// `KcnaApp`, plus MainActivity's start-up steps). One per process, created by the app at launch
/// and handed to the views (`.environment(graph)`; Kotlin `LocalAppGraph`).
///
/// - ``repository``: all schedule data, the bundled resources or a newer set downloaded by
///   ``dataSync``. Loaded once, off the main thread, at ``start(arguments:)`` (or by the first
///   ``awaitRepository()``); the root shows screens only once ``isRepositoryLoaded``. It is
///   replaced as a whole (never mixed) when ``dataSync`` swaps in newer data; it is observable,
///   so views that read it update with the new data.
/// - ``clock``: "now" (real time, or the debug fake time). Never call `Date()` in logic.
/// - ``going``: RSVPs (starred sessions, the reminder lead time); ``settings``: "I'm speaking
///   as", the Directions "From" choice.
/// - ``details`` / ``router``: session descriptions and indoor routing, rebuilt for each
///   ``repository``.
/// - ``dataSync``: live data updates (``DataSync/active``, status, "Check now").
/// - ``reminders``: the reminder notifications (``ReminderScheduler``).
///
/// The reactions KcnaApp sets up: the reminders are re-planned at launch, every time the app
/// becomes active, when "I'm speaking as", the stars, the "Going" reminder time, the debug fake
/// time or the data change, and once notification permission is granted; data sync checks at
/// launch and back in the foreground (with its crash guard); details.json is parsed off the main
/// thread after each data load.
///
/// The app layer's part (all on the main actor):
///
/// ```swift
/// @main struct KCNA26App: App {
///     @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate   // sets the UNUserNotificationCenter delegate
///     @Environment(\.scenePhase) private var phase
///     @State private var graph = AppGraph.shared                             // AppGraph(.live(reminders:notificationPermission:))
///     var body: some Scene {
///         WindowGroup { RootView().environment(graph) }
///             .onChange(of: phase, initial: true) { _, p in p == .active ? graph.onForeground() : graph.onBackground() }
///     }
///     init() { AppGraph.shared.start(arguments: ProcessInfo.processInfo.arguments) }
/// }
/// extension AppGraph {
///     static let shared = AppGraph.live(reminders: NotificationCenterReminders(), notificationPermission: NotificationCenterPermission())
/// }
/// // UNUserNotificationCenterDelegate (set in application(_:didFinishLaunchingWithOptions:)):
/// //   didReceive, default action only:
/// //     if let id = ReminderContent.directionsSessionId(response.notification.request.content.userInfo) {
/// //         await graph.notificationTapped(sessionId: id) }
/// //   willPresent: a reminder (ReminderContent.keyOf(identifier:userInfo:)) shows only if
/// //     await graph.reminderFiring(sessionId:minutesBefore:).shows -> [.banner, .list, .sound], else [];
/// //     anything else -> [.banner, .list, .sound]
/// // RootView: switch graph.rootState { … }; graph.routePendingDirections(to: nav) on appear and
/// //   .onChange(of: graph.pendingDirectionsSessionId); willTerminateNotification -> graph.onBackground()
/// ```
@MainActor
@Observable
final class AppGraph {
    @ObservationIgnored let services: AppServices

    /// Live data updates from GitHub: ``DataSync/active``, status and "Check now".
    @ObservationIgnored let dataSync: DataSync

    /// The concrete clock, for the debug fake-time override (``start(arguments:)``'s `-fakeNow`).
    @ObservationIgnored let fakeableClock: FakeableClock

    /// "Now" (real time, or the debug fake time). Never call `Date()` directly in logic.
    @ObservationIgnored let clock: AppClock

    /// RSVPs ("Going" in code): starred sessions and how long before them to send a reminder.
    @ObservationIgnored let going: GoingStore

    /// "I'm speaking as" and the Directions "From" choice.
    @ObservationIgnored let settings: SettingsStore

    /// The armed reminder keys (prefs "kcna26.reminders").
    @ObservationIgnored let reminderStore: ReminderStore

    /// The reminder notifications (Kotlin `ReminderScheduler.reschedule(context)` -> `graph.reminders.reschedule()`).
    @ObservationIgnored let reminders: ReminderScheduler

    /// The repository in use once published on the main actor (nil until loaded).
    private var current: Repository?

    /// Set when the bundled data itself couldn't be loaded (the root shows it).
    private(set) var loadError: String?

    /// The session of a tapped reminder, until the scene routes it (``routePendingDirections(to:)``).
    private(set) var pendingDirectionsSessionId: String?

    @ObservationIgnored private let detailsByRepository: RepositoryScoped<DetailsRepository>
    @ObservationIgnored private let routerByRepository: RepositoryScoped<Router>
    @ObservationIgnored private let ref: AppGraphRef
    @ObservationIgnored private var loadTask: Task<Repository, any Error>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var watches: [AppGraphWatch] = []
    @ObservationIgnored private var askWatch: NotificationAsk.TriggerWatch?
    @ObservationIgnored private var askCheck: Task<Void, Never>?

    init(_ services: AppServices) {
        self.services = services
        let ref = AppGraphRef()
        self.ref = ref
        let log = services.log
        let wall = services.wallClock
        dataSync = DataSync(
            root: services.filesDirectory.appendingPathComponent("data", isDirectory: true),
            bundled: services.bundledData,
            fetcher: services.dataFetcher,
            prefs: services.prefs(DataSync.PREFS),
            baseUrl: services.dataBaseUrl,
            // A background thread: publish on the main actor, from DataSync.active (the newest).
            onSwapped: { _ in Task { @MainActor in ref.graph?.publishActive() } },
            nowMillis: { wall.now().epochMillis },
            appVersion: services.appVersion,
            log: log
        )
        let fake = FakeableClock(services.prefs(FakeableClock.PREFS), allowFake: services.isDebug)
        fakeableClock = fake
        let clock = services.clockOverride ?? fake
        self.clock = clock
        let going = GoingStore(services.prefs(GoingStore.PREFS))
        self.going = going
        let settings = SettingsStore(services.prefs(SettingsStore.PREFS))
        self.settings = settings
        let store = ReminderStore(services.prefs(ReminderStore.PREFS))
        reminderStore = store
        reminders = ReminderScheduler(
            center: services.reminders,
            store: store,
            settings: settings,
            going: going,
            clock: clock,
            wallClock: wall,
            repository: {
                guard let graph = ref.graph else { throw AppGraphGone() }
                return try await graph.awaitRepository()
            },
            log: log
        )
        let detailsDir = services.filesDirectory.appendingPathComponent("details", isDirectory: true)
        let detailsFetcher = services.detailsFetcher
        detailsByRepository = RepositoryScoped { @Sendable repo in DetailsRepository(repo, cacheDir: detailsDir, fetcher: detailsFetcher) }
        routerByRepository = RepositoryScoped { @Sendable repo in Router(repo) }
        ref.graph = self
    }

    // MARK: - Repository

    /// All schedule data (see the type's documentation). Read it once ``isRepositoryLoaded``;
    /// before that it loads synchronously, blocking the caller (Kotlin's lazy), and traps only if
    /// the bundled data itself is broken.
    var repository: Repository {
        if let r = current { return r }
        if let a = dataSync.active { return a.repository }
        do {
            return try dataSync.loadActive().repository
        } catch {
            preconditionFailure(MainActivityLogic.loadErrorText(error))
        }
    }

    /// True once ``repository`` is loaded (observable).
    var isRepositoryLoaded: Bool { current != nil }

    /// ``repository``, loading it off the main thread if needed. Throws if the bundled data
    /// can't be loaded (then ``loadError`` says why; the next call tries again).
    func awaitRepository() async throws -> Repository {
        if let r = current { return r }
        return try await load().value
    }

    private func load() -> Task<Repository, any Error> {
        if let t = loadTask { return t }
        let sync = dataSync
        let t = Task { @MainActor [weak self] () throws -> Repository in
            do {
                let active = try await Task.detached(priority: .userInitiated) { try sync.loadActive() }.value
                self?.publishActive()
                return self?.current ?? active.repository
            } catch {
                self?.loadTask = nil
                self?.loadError = MainActivityLogic.loadErrorText(error)
                self?.services.log("Repository failed to load: \(error)")
                throw error
            }
        }
        loadTask = t
        return t
    }

    /// Publishes ``DataSync/active`` (the newest set) as ``repository`` if it changed: after the
    /// first load, and when a check swapped in newer data (Kotlin `onDataSwapped`). Then parses
    /// details.json off the main thread and, for a swap, re-plans the reminders.
    private func publishActive() {
        guard let active = dataSync.active, active.repository !== current else { return }
        let swapped = current != nil
        current = active.repository
        loadError = nil
        warmDetails()
        if swapped { reminders.reschedule() }
    }

    /// Parses details.json now, off the main thread, so the first sheet opens at once.
    private func warmDetails() {
        let d = details
        Task.detached(priority: .utility) { d.warmBundled() }
    }

    /// Session descriptions and speaker taglines, rebuilt for each ``repository``.
    var details: DetailsRepository { detailsByRepository[repository] }

    /// Indoor routing, rebuilt for each ``repository``.
    var router: Router { routerByRepository[repository] }

    // MARK: - Lifecycle

    /// Launch (Kotlin `KcnaApp.onCreate` + `MainActivity.onCreate` of a fresh start). Call once,
    /// as early as possible (the App's `init`); later calls do nothing.
    /// - Starts loading the data off the main thread (then parses details.json).
    /// - Debug builds: applies `-fakeNow` from `arguments` (`ProcessInfo.processInfo.arguments`).
    /// - Re-plans the reminders whenever "I'm speaking as", the stars, the "Going" reminder
    ///   time or the fake time change, and schedules them now.
    /// The first ``onForeground()`` (scenePhase `.active`) then checks for newer data.
    func start(arguments: [String] = []) {
        guard !started else { return }
        started = true
        dataSync.installCrashGuard()
        _ = load()
        if let line = MainActivityLogic.applyFakeNow(arguments, to: fakeableClock, isDebug: services.isDebug) {
            services.log(line)
        }
        let settings = settings
        let going = going
        let fake = fakeableClock
        watches = [
            AppGraphWatch(read: { _ = settings.speakingAs }) { [weak self] in self?.reminders.reschedule() },
            AppGraphWatch(read: {
                _ = going.ids
                _ = going.remindMinutes
            }) { [weak self] in self?.reminders.reschedule() },
            AppGraphWatch(read: { _ = fake.offsetMillis }) { [weak self] in self?.reminders.reschedule() },
        ]
        reminders.reschedule()
    }

    /// The app became active (App-level scenePhase `.active`, also right after launch; Kotlin:
    /// the first activity started). Checks for newer data if due (``DataSync/onForeground()``),
    /// re-plans the reminders (the soonest ones may have fired, making room for the next), and
    /// asks for notification permission in context (``NotificationAsk``).
    func onForeground() {
        dataSync.onForeground()
        reminders.reschedule()
        startNotificationAsk()
    }

    /// The app left the foreground (scenePhase `.inactive` or `.background`, and
    /// `willTerminateNotification`): lets the crash guard know it ran healthily
    /// (``DataSync/onBackground()``) and stops the permission triggers.
    func onBackground() {
        dataSync.onBackground()
        askWatch?.cancel()
        askWatch = nil
        askCheck?.cancel()
        askCheck = nil
    }

    // MARK: - Notifications

    /// A reminder notification was tapped (the default action): opens Directions for
    /// `sessionId` in the scene that routes it (Kotlin MainActivity `handleIntent` ->
    /// `nav.openDirectionsFromNotification`). The delegate reads the id with
    /// ``ReminderContent/directionsSessionId(_:)`` (nil: not a reminder, nothing to do).
    /// iOS removes the tapped notification; the session's other delivered reminders go too
    /// (Kotlin: one notification per session, removed by the tap, `setAutoCancel(true)`).
    func notificationTapped(sessionId: String) {
        pendingDirectionsSessionId = sessionId
        reminders.tidyDelivered(of: sessionId)
    }

    /// Takes the tapped reminder's session (once).
    func takePendingDirections() -> String? {
        let id = pendingDirectionsSessionId
        pendingDirectionsSessionId = nil
        return id
    }

    /// Applies a tapped reminder to `nav`: Schedule (with the session's details) → Directions.
    @discardableResult
    func routePendingDirections(to nav: NavModel) -> Bool {
        guard let id = takePendingDirections() else { return false }
        nav.openDirectionsFromNotification(id)
        return true
    }

    /// A reminder fired while the app is in the foreground (`willPresent`): the receiver's
    /// checks (``ReminderFiring/check(_:_:_:_:_:_:_:)``) at this moment. Show it only for
    /// ``ReminderFiring/show(title:text:channelId:expiresAt:)``; then the session's older
    /// delivered reminders go (Kotlin posts it under the session's tag, replacing the one showing).
    func reminderFiring(sessionId: String, minutesBefore: Int) async -> ReminderFiring {
        guard let repo = try? await awaitRepository() else { return .unknownSession }
        let now = clock.now()
        let firing = ReminderFiring.check(sessionId, minutesBefore, repo, settings.speakingAs, going.ids, going.remindMinutes, now)
        if let line = firing.logLine(sessionId, minutesBefore, now: now, posted: firing.shows) { services.log(line) }
        if firing.shows { reminders.tidyDelivered(of: sessionId, keeping: minutesBefore) }
        return firing
    }

    /// The notification permission (the notifications-off hint reads `status()` from it,
    /// ``NotificationAsk/blocked(_:_:)``).
    var notificationPermission: any NotificationPermission { services.notificationPermission }

    /// The hint's "Turn on" while the system can still show its dialog
    /// (``NotificationAsk/TurnOn/requestAuthorization``): asks now, then re-plans the reminders
    /// if granted. Returns whether it was granted.
    @discardableResult
    func requestNotificationsNow() async -> Bool {
        let granted = await NotificationAsk.askNow(settings, services.notificationPermission)
        if granted { reminders.reschedule() }
        return granted
    }

    /// Kotlin MainActivity `askForNotificationsOnce` (+ the permission callback): asks at most
    /// once, then re-plans the reminders if granted.
    func askForNotificationsOnce() {
        let settings = settings
        let permission = services.notificationPermission
        Task { [weak self] in
            if await NotificationAsk.askOnce(settings, permission) == true { self?.reminders.reschedule() }
        }
    }

    /// Kotlin `NotificationAsk.watch` for one foreground: every trigger asks, and so does the
    /// start check when reminders are already planned but the app never asked.
    private func startNotificationAsk() {
        askWatch?.cancel()
        askWatch = NotificationAsk.triggers(settings, going) { [weak self] in self?.askForNotificationsOnce() }
        askCheck?.cancel()
        askCheck = Task { [weak self] in await self?.askIfRemindersWaiting() }
    }

    private func askIfRemindersWaiting() async {
        let status = await services.notificationPermission.status()
        guard NotificationAsk.shouldAsk(status, asked: settings.notificationPermissionAsked) else { return }
        guard let repo = try? await awaitRepository(), !Task.isCancelled else { return }
        if NotificationAsk.remindersWaiting(status, settings, going, repo, clock.now()) { askForNotificationsOnce() }
    }

    // MARK: - Root

    /// What the root view shows (Kotlin `Root`).
    var rootState: MainActivityLogic.RootState {
        if isRepositoryLoaded { return .ready }
        if let e = loadError { return .failed(e) }
        return .loading
    }

    /// The first-run speaker sheet shows over the shell once the data is loaded, on a fresh
    /// install (``SettingsStore/firstRunPending``).
    var showsFirstRunSheet: Bool { isRepositoryLoaded && settings.firstRunPending }
}

extension AppGraph {
    /// The app's graph with the real platform services (``AppServices/live(reminders:notificationPermission:isDebug:bundle:log:)``).
    static func live(
        reminders: any ReminderScheduling,
        notificationPermission: any NotificationPermission,
        isDebug: Bool = AppServices.isDebugBuild
    ) -> AppGraph {
        AppGraph(.live(reminders: reminders, notificationPermission: notificationPermission, isDebug: isDebug))
    }
}

/// Lets closures made in ``AppGraph/init(_:)`` (before `self` exists) reach the graph.
@MainActor
private final class AppGraphRef {
    weak var graph: AppGraph?
}

private struct AppGraphGone: Error {}

/// Calls `onChange` on the main actor after any value `read` reads changes (Kotlin
/// `flow.drop(1).onEach { … }.launchIn(appScope)`). Several changes in one main-actor turn make
/// one call; `onChange` then sees the latest values.
@MainActor
private final class AppGraphWatch {
    private let read: @MainActor () -> Void
    private let onChange: @MainActor () -> Void

    init(read: @escaping @MainActor () -> Void, _ onChange: @escaping @MainActor () -> Void) {
        self.read = read
        self.onChange = onChange
        track()
    }

    private func track() {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            // Called as the value is about to change, on the changing thread: act afterwards, on the main actor.
            Task { @MainActor [weak self] in self?.changed() }
        }
    }

    private func changed() {
        track()
        onChange()
    }
}
