import Foundation

/// The app's local notifications (the app layer implements it over `UNUserNotificationCenter`;
/// tests use a fake). Android's AlarmManager + NotificationManager become this one service:
/// iOS fires a scheduled request itself, keeps pending requests across reboots and app
/// updates (no boot receiver), and keeps at most 64 pending requests per app (so
/// ``ReminderScheduler`` schedules only the soonest ``ReminderScheduler/MAX_PENDING``).
///
/// ```swift
/// struct NotificationCenterReminders: ReminderScheduling {
///     private var center: UNUserNotificationCenter { .current() }
///     func pendingIdentifiers() async -> [String] {
///         await center.pendingNotificationRequests().map(\.identifier)
///     }
///     func add(_ r: ReminderRequest) async throws {
///         let c = UNMutableNotificationContent()
///         c.title = r.content.title
///         c.body = r.content.body
///         c.threadIdentifier = r.content.threadIdentifier
///         c.targetContentIdentifier = r.content.targetContentIdentifier
///         c.userInfo = r.content.userInfo
///         c.sound = .default
///         c.interruptionLevel = .active
///         let trigger = UNTimeIntervalNotificationTrigger(timeInterval: r.timeInterval(from: Date()), repeats: false)
///         try await center.add(UNNotificationRequest(identifier: r.identifier, content: c, trigger: trigger))
///     }
///     func removePending(_ ids: [String]) async { center.removePendingNotificationRequests(withIdentifiers: ids) }
///     func delivered() async -> [DeliveredReminder] {
///         await center.deliveredNotifications().map {
///             DeliveredReminder(identifier: $0.request.identifier, userInfo: $0.request.content.userInfo, date: $0.date)
///         }
///     }
///     func removeDelivered(_ ids: [String]) async { center.removeDeliveredNotifications(withIdentifiers: ids) }
/// }
/// ```
///
/// A time-interval trigger fires at an absolute moment (like Android's RTC alarms), also when
/// the phone changes time zone on the way to Salt Lake City; a calendar trigger built from date
/// components without a time zone would not.
protocol ReminderScheduling: Sendable {
    /// Identifiers of the app's pending requests (`pendingNotificationRequests()`).
    func pendingIdentifiers() async -> [String]
    /// Schedules `request`, replacing a pending one with the same identifier
    /// (`UNUserNotificationCenter.add`). Throws when iOS refuses it (e.g. not allowed).
    func add(_ request: ReminderRequest) async throws
    /// Cancels pending requests (`removePendingNotificationRequests(withIdentifiers:)`); unknown
    /// identifiers are ignored.
    func removePending(_ identifiers: [String]) async
    /// The app's notifications still in Notification Center (`deliveredNotifications()`).
    func delivered() async -> [DeliveredReminder]
    /// Removes delivered notifications (`removeDeliveredNotifications(withIdentifiers:)`).
    func removeDelivered(_ identifiers: [String]) async
}

/// One local notification to schedule: ``content`` at ``fireDate`` (real wall-clock time).
struct ReminderRequest: Sendable, Hashable {
    let content: ReminderContent
    /// The real moment to notify: the planned trigger moved off the debug fake time (Kotlin
    /// `clock.realEpochMillis(triggerAt)`), equal to it on the real clock.
    let fireDate: Date

    /// The `UNNotificationRequest` identifier (``PlannedReminder/key``).
    var identifier: String { content.identifier }

    /// `UNTimeIntervalNotificationTrigger`'s interval from `realNow`: the time left, at least
    /// 1 second (the trigger needs a positive interval; Android fires a past alarm at once).
    func timeInterval(from realNow: Date) -> TimeInterval {
        max(1, fireDate.timeIntervalSince(realNow))
    }
}

/// A notification in Notification Center (`UNNotification`), as far as reminders care.
struct DeliveredReminder: Sendable, Hashable {
    let identifier: String
    /// The reminder's session; nil if the notification isn't a reminder.
    let sessionId: String?
    let minutesBefore: Int?
    /// When it was delivered (`UNNotification.date`).
    let date: Date

    init(identifier: String, sessionId: String?, minutesBefore: Int?, date: Date) {
        self.identifier = identifier
        self.sessionId = sessionId
        self.minutesBefore = minutesBefore
        self.date = date
    }

    /// From a delivered notification's request identifier and content `userInfo`.
    init(identifier: String, userInfo: [AnyHashable: Any], date: Date) {
        let key = ReminderContent.keyOf(identifier: identifier, userInfo: userInfo)
        self.init(identifier: identifier, sessionId: key?.sessionId, minutesBefore: key?.minutes, date: date)
    }
}

/// Arms the talk reminders: 30 and 10 minutes before each of the speaker's own sessions
/// (`isMine(s, settings.speakingAs)`), and one "Remind me before sessions I'm going to"
/// minutes before each starred session (`going.ids`, `going.remindMinutes`; Off = none).
/// (Kotlin `object ReminderScheduler`; one per app, owned by ``AppGraph``.)
///
/// ``reschedule()`` is called at launch, every time the app becomes active, and whenever "I'm
/// speaking as", the stars, the "Going" reminder time, the debug fake time or the data change
/// (``AppGraph`` wires all of these), and after notification permission is granted. It is cheap
/// and idempotent: it cancels every request it scheduled before that is no longer planned
/// (tracked in ``ReminderStore``, plus any pending reminder request the store doesn't know)
/// and re-adds the planned ones, which replaces them in place.
///
/// iOS keeps at most 64 pending requests per app, so only the soonest ``MAX_PENDING`` (60) of
/// the plan are scheduled (``select(_:max:)``); the rest follow at a later reschedule, as the
/// first ones fire (the app becomes active often during a conference day). Delivered reminders
/// are tidied up at the same time (``deliveredToRemove(_:_:_:_:_:_:)``), and right away when a
/// reminder is presented in the foreground or tapped (``tidyDelivered(of:keeping:)``), so a
/// session keeps one notification at most, like Kotlin's one per session.
///
/// Runs on the main actor (it reads the stores); the notification center calls are `async`.
/// Reschedules run one at a time, in order; each reads the settings when it starts, so the last
/// change always wins. Requests made while one is waiting to start are served by that one.
@MainActor
final class ReminderScheduler {
    /// Pending reminder requests scheduled at most (iOS allows 64 per app; 4 spare).
    nonisolated static let MAX_PENDING = 60

    private let center: any ReminderScheduling
    private let store: ReminderStore
    private let settings: SettingsStore
    private let going: GoingStore
    private let clock: AppClock
    private let wallClock: AppClock
    private let repository: @MainActor () async throws -> Repository
    private let log: @Sendable (String) -> Void

    private let gate = RescheduleGate()
    private var requested = 0
    private var covered = 0
    private var lastCount = 0
    private var tidying: [Int: Task<Void, Never>] = [:]
    private var nextTidy = 0

    /// Number of reschedules that have finished (diagnostics and tests).
    private(set) var runs = 0

    /// - Parameters:
    ///   - clock: the app clock (``AppGraph/clock``, maybe faked) the plan runs on.
    ///   - wallClock: the real clock, to turn planned times into real fire dates.
    ///   - repository: ``AppGraph/awaitRepository()``.
    init(
        center: any ReminderScheduling,
        store: ReminderStore,
        settings: SettingsStore,
        going: GoingStore,
        clock: AppClock,
        wallClock: AppClock = SystemAppClock.shared,
        repository: @escaping @MainActor () async throws -> Repository,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.center = center
        self.store = store
        self.settings = settings
        self.going = going
        self.clock = clock
        self.wallClock = wallClock
        self.repository = repository
        self.log = log
    }

    /// Re-plans and re-schedules all reminders. Returns at once; the work runs in a task.
    func reschedule() {
        requested += 1
        let n = requested
        Task { _ = await self.serve(n) }
    }

    /// The work of ``reschedule()``, for callers that wait for it. Never throws. Returns the
    /// number of reminders scheduled.
    @discardableResult
    func rescheduleNow() async -> Int {
        requested += 1
        return await serve(requested)
    }

    /// Waits until every reschedule requested so far has finished (and every
    /// ``tidyDelivered(of:keeping:)`` started so far).
    func settle() async {
        if covered < requested { _ = await serve(requested) }
        while let t = tidying.values.first {
            await t.value
        }
    }

    /// Removes the session's other delivered reminders, where the app gets control (Kotlin shows
    /// one notification per session, tag "talk:<id>": posting the next reminder replaces the one
    /// showing, and a tap removes it). ``AppGraph`` calls it when a reminder is presented in the
    /// foreground (`keeping` its `minutesBefore`) and when one is tapped (`keeping` nil: all of the
    /// session's). Returns at once; the work runs in a task (``settle()`` waits for it).
    func tidyDelivered(of sessionId: String, keeping minutesBefore: Int? = nil) {
        nextTidy += 1
        let n = nextTidy
        tidying[n] = Task {
            await self.removeDelivered(of: sessionId, keeping: minutesBefore)
            self.tidying[n] = nil
        }
    }

    /// The work of ``tidyDelivered(of:keeping:)``. Returns the identifiers removed.
    @discardableResult
    func removeDelivered(of sessionId: String, keeping minutesBefore: Int? = nil) async -> [String] {
        let gone = ReminderScheduler.deliveredOfSession(await center.delivered(), sessionId, keeping: minutesBefore)
        if !gone.isEmpty {
            await center.removeDelivered(gone)
            let why: String = minutesBefore.map { m in "\(sessionId)/\(m) shown" } ?? "\(sessionId) tapped"
            log("reminders: removed delivered \(gone.joined(separator: ",")) (\(why))")
        }
        return gone
    }

    private func serve(_ n: Int) async -> Int {
        await gate.enter()
        defer { gate.leave() }
        if covered >= n { return lastCount }
        // Everything requested so far is served by this run: it reads the settings from here on.
        let upTo = requested
        let count: Int
        do {
            count = try await doReschedule()
        } catch {
            log("reminders: reschedule failed: \(error)")
            count = 0
        }
        covered = max(covered, upTo)
        lastCount = count
        runs += 1
        return count
    }

    private func doReschedule() async throws -> Int {
        let repo = try await repository()
        let me = settings.speakingAs
        let goingIds = going.ids
        let goingMinutes = going.remindMinutes
        let armed = store.armed()
        // armed: a "Going" reminder whose new, longer lead time is already past keeps its armed one.
        let plan = ReminderPlanner.plan(repo.sessions, repo.rooms, me, clock.now(), goingIds, goingMinutes, armed)
        let selected = ReminderScheduler.select(plan)
        let planned = selected.map(\.key)
        let plannedSet = Set(planned)

        // Cancel what no longer applies (the setting changed, or it already fired), and any
        // pending reminder this store doesn't know about.
        let pending = await center.pendingIdentifiers().filter { ReminderPlanner.parseKey($0) != nil }
        let stale = (armed.union(pending)).subtracting(plannedSet).sorted()
        if !stale.isEmpty { await center.removePending(stale) }

        // A reminder still showing for a session that is no longer mine or starred goes too, as
        // do ended sessions' and superseded ones (see deliveredToRemove).
        let delivered = await center.delivered()
        let gone = ReminderScheduler.deliveredToRemove(delivered, repo, me, goingIds, goingMinutes, clock.now())
        if !gone.isEmpty { await center.removeDelivered(gone) }

        let pendingSet = Set(pending)
        var added = 0
        for request in ReminderScheduler.requests(selected, clock: clock, wallClock: wallClock) {
            guard ReminderScheduler.shouldAdd(request, alreadyPending: pendingSet.contains(request.identifier), realNow: wallClock.now()) else {
                continue
            }
            do {
                try await center.add(request)
                added += 1
            } catch {
                log("reminders: can't schedule \(request.identifier): \(error)")
            }
        }
        store.setArmed(plannedSet)
        let next = selected.first.map { "\($0.key)@\($0.triggerAt)" } ?? "none"
        log(
            "reminders: me=\(me ?? "None") going=\(goingIds.count)@\(goingMinutes)m armed=\(selected.count) of \(plan.count) " +
                "(added=\(added)) cancelled=\(stale.count) removed=\(gone.count) next=\(next)"
        )
        return selected.count
    }

    // MARK: - Rules

    /// The reminders to schedule: the soonest `max` of `plan` (the plan holds only reminders
    /// still to come, sorted by trigger time, then session id).
    nonisolated static func select(_ plan: [PlannedReminder], max: Int = MAX_PENDING) -> [PlannedReminder] {
        Array(plan.prefix(Swift.max(0, max)))
    }

    /// The requests for `selected`: each reminder's content at its real fire date (the planned
    /// trigger minus the debug fake-time offset, `clock.now() - wallClock.now()`).
    nonisolated static func requests(_ selected: [PlannedReminder], clock: AppClock, wallClock: AppClock) -> [ReminderRequest] {
        let offsetMillis = clock.now().epochMillis - wallClock.now().epochMillis
        return selected.map { r in
            ReminderRequest(content: ReminderContent(r), fireDate: Date(epochMillis: r.triggerAt.epochMillis - offsetMillis))
        }
    }

    /// Whether to (re-)add `request` now. Not when its moment has already passed while this
    /// reschedule ran (if it was pending it has just fired; adding it again would notify
    /// twice), nor when it is pending and fires within a second (replacing it could only delay it).
    nonisolated static func shouldAdd(_ request: ReminderRequest, alreadyPending: Bool, realNow: Date) -> Bool {
        let left = request.fireDate.timeIntervalSince(realNow)
        if left <= 0 { return false }
        if alreadyPending && left < 1 { return false }
        return true
    }

    /// The delivered reminders to remove from Notification Center at `now` (app clock):
    /// - its session is no longer mine or starred (or gone from the data), as Kotlin's reschedule does;
    /// - its session has ended (Kotlin posts with `setTimeoutAfter(end of the session)`);
    /// - it is superseded (Kotlin shows one notification per session, the 10 minute one replacing
    ///   the 30 minute one): a shorter reminder of the session has come due by `now`
    ///   (``supersededBySchedule(_:_:_:_:)``; also once that one was tapped or swiped away, when
    ///   only the older one is left), or, of the session's remaining ones, it isn't the newest.
    /// Notifications that aren't reminders are left alone. In `delivered` order.
    nonisolated static func deliveredToRemove(
        _ delivered: [DeliveredReminder],
        _ repo: Repository,
        _ me: String?,
        _ going: Set<String>,
        _ goingMinutes: Int,
        _ now: Date
    ) -> [String] {
        var gone = [Bool](repeating: false, count: delivered.count)
        var newest: [String: DeliveredReminder] = [:]
        for (i, d) in delivered.enumerated() {
            guard let id = d.sessionId else { continue }
            guard let s = repo.session(id), let spec = ReminderPlanner.specFor(s, me, going, goingMinutes) else {
                gone[i] = true
                continue
            }
            if !now.isBefore(s.effectiveEnd) {
                gone[i] = true
                continue
            }
            if let m = d.minutesBefore, supersededBySchedule(s, m, spec, now) {
                gone[i] = true
                continue
            }
            if let best = newest[id], !isNewer(d, than: best) { continue }
            newest[id] = d
        }
        var remove: [String] = []
        for (i, d) in delivered.enumerated() {
            guard let id = d.sessionId else { continue }
            if gone[i] || newest[id]?.identifier != d.identifier { remove.append(d.identifier) }
        }
        return remove
    }

    /// Whether a reminder `minutesBefore` session `s` is superseded at `now` by the schedule: one
    /// of `spec`'s shorter offsets has come due (Kotlin posts it under the same tag, replacing
    /// this one; its tap or swipe then leaves nothing of the session).
    nonisolated static func supersededBySchedule(_ s: Session, _ minutesBefore: Int, _ spec: ReminderSpec, _ now: Date) -> Bool {
        spec.offsets.contains { o in o < minutesBefore && !s.start.minusMinutes(o).isAfter(now) }
    }

    /// The delivered reminders of `sessionId` to remove when the app sees one of them presented
    /// or tapped (Kotlin's one notification per session, tag "talk:<id>"): all of them except
    /// those `keeping` minutes before (the one being presented); all of them when `keeping` is nil
    /// (a tap: Kotlin's `setAutoCancel(true)` removes the session's notification).
    nonisolated static func deliveredOfSession(_ delivered: [DeliveredReminder], _ sessionId: String, keeping minutesBefore: Int?) -> [String] {
        delivered.compactMap { d in
            guard d.sessionId == sessionId else { return nil }
            if let m = minutesBefore, d.minutesBefore == m { return nil }
            return d.identifier
        }
    }

    /// Later delivery first; at the same moment, the shorter lead time (the later reminder).
    private nonisolated static func isNewer(_ a: DeliveredReminder, than b: DeliveredReminder) -> Bool {
        if a.date != b.date { return a.date > b.date }
        return (a.minutesBefore ?? Int.max) < (b.minutesBefore ?? Int.max)
    }
}

/// Kotlin's coroutine `Mutex` for the reschedules: one at a time, in arrival order; waiting
/// suspends (never blocks the main thread).
@MainActor
private final class RescheduleGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }

    /// Hands the gate to the next waiter, or opens it.
    func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
