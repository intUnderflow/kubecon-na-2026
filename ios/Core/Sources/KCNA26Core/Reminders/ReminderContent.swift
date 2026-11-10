import Foundation

/// What one reminder notification shows and carries (the port of Kotlin ReminderNotifier's
/// notification, and of ReminderReceiver's fire-time checks in ``ReminderFiring``), in the shape
/// `UNMutableNotificationContent` needs. The app layer copies it field by field (see
/// ``ReminderScheduling``).
///
/// - ``title``: the session title; ``body``: "Your talk in 10 min · Grand Ballroom GI, Level 1"
///   (my talks) or "Starting in 10 min · Grand Ballroom GI, Level 1" (starred sessions), the
///   planner's texts (``ReminderPlanner/text(_:_:_:)``).
/// - ``identifier``: the ``PlannedReminder/key`` ("1249844/10"), the `UNNotificationRequest`
///   identifier, which is also what ``ReminderStore`` remembers.
/// - ``threadIdentifier``: "talk:<session id>" (Kotlin's notification tag): a session's 30 and
///   10 minute reminders group together. Android shows one notification per session (the 10
///   minute one replaces the 30 minute one); iOS can't replace a delivered notification without
///   running app code, so the next reschedule keeps only the newest delivered one per session
///   (``ReminderScheduler/deliveredToRemove(_:_:_:_:_:_:)``).
/// - ``userInfo``: the action, session id, offset and kind (strings), read back by
///   ``keyOf(identifier:userInfo:)`` and ``directionsSessionId(_:)`` (the tap opens Directions).
/// - ``targetContentIdentifier``: the Directions screen key ("directions:<id>"), so iOS can
///   bring the right window forward.
///
/// Delivery: sound on (Android's high-importance channel), interruption level `.active`.
/// Android's channels ("Your talks", "Sessions you’ve RSVP’d to") have no iOS counterpart (one
/// notification switch per app); ``channelId`` is kept for parity and logs.
struct ReminderContent: Sendable, Hashable {
    let identifier: String
    let sessionId: String
    let minutesBefore: Int
    let kind: ReminderKind
    let title: String
    let body: String

    init(identifier: String, sessionId: String, minutesBefore: Int, kind: ReminderKind, title: String, body: String) {
        self.identifier = identifier
        self.sessionId = sessionId
        self.minutesBefore = minutesBefore
        self.kind = kind
        self.title = title
        self.body = body
    }

    /// The notification for a planned reminder.
    init(_ r: PlannedReminder) {
        self.init(identifier: r.key, sessionId: r.sessionId, minutesBefore: r.minutesBefore, kind: r.kind, title: r.title, body: r.text)
    }

    /// "talk:<session id>": groups a session's reminders (Kotlin's notification tag).
    var threadIdentifier: String { ReminderContent.TAG_PREFIX + sessionId }

    /// The Directions screen this notification opens ("directions:<session id>").
    var targetContentIdentifier: String { Screen.directions(sessionId).key }

    /// Kotlin `ReminderNotifier.channelFor(kind)`.
    var channelId: String { ReminderContent.channelFor(kind) }

    /// `UNMutableNotificationContent.userInfo` (strings only, so it is `Sendable` and plist-safe).
    var userInfo: [String: String] {
        [
            ReminderContent.KEY_ACTION: ReminderContent.ACTION_OPEN_DIRECTIONS,
            ReminderContent.EXTRA_SESSION_ID: sessionId,
            ReminderContent.EXTRA_MINUTES_BEFORE: String(minutesBefore),
            ReminderContent.EXTRA_KIND: kind.rawValue,
        ]
    }

    // MARK: - Constants (Kotlin ReminderNotifier, MainActivity, ReminderScheduler)

    /// Kotlin `ReminderNotifier.CHANNEL_ID` / channel name (Android only).
    static let CHANNEL_ID = "your_talks"
    static let CHANNEL_NAME = "Your talks"
    /// Reminders for starred ("Going") sessions (Android: a separate channel, so they can be silenced on their own).
    static let GOING_CHANNEL_ID = "going"
    static let GOING_CHANNEL_NAME = "Sessions you’ve RSVP’d to"
    /// Kotlin's notification tag prefix, here the thread identifier's.
    static let TAG_PREFIX = "talk:"

    /// The tap's action (Kotlin `MainActivity.ACTION_OPEN_DIRECTIONS`), under ``KEY_ACTION``.
    static let ACTION_OPEN_DIRECTIONS = "app.kcna26.action.OPEN_DIRECTIONS"
    static let KEY_ACTION = "action"
    /// The session id (Kotlin `MainActivity.EXTRA_SESSION_ID`; the alarm's
    /// `ReminderScheduler.EXTRA_SESSION_ID` is the same value on iOS, one key serves both).
    static let EXTRA_SESSION_ID = "app.kcna26.extra.SESSION_ID"
    /// Kotlin `ReminderScheduler.EXTRA_MINUTES_BEFORE`.
    static let EXTRA_MINUTES_BEFORE = "app.kcna26.extra.REMINDER_MINUTES_BEFORE"
    /// iOS: the ``ReminderKind`` raw value ("MINE" / "GOING").
    static let EXTRA_KIND = "app.kcna26.extra.REMINDER_KIND"

    /// The channel for a reminder of `kind` (Kotlin `ReminderNotifier.channelFor`).
    static func channelFor(_ kind: ReminderKind) -> String { kind == .going ? GOING_CHANNEL_ID : CHANNEL_ID }

    // MARK: - Reading a notification back

    /// The session id and offset of a reminder notification (Kotlin ReminderReceiver `keyOf`):
    /// from `userInfo` if both are there (offset > 0), else from the identifier ("<id>/<minutes>",
    /// Kotlin: the data URI kcna26://reminder/<id>/<minutes>). Nil if it isn't a reminder.
    static func keyOf(identifier: String, userInfo: [AnyHashable: Any]) -> (sessionId: String, minutes: Int)? {
        let id = userInfo[EXTRA_SESSION_ID] as? String
        let minutes = intExtra(userInfo[EXTRA_MINUTES_BEFORE]) ?? -1
        if let id, minutes > 0 { return (id, minutes) }
        return ReminderPlanner.parseKey(identifier)
    }

    /// The session whose Directions a tapped notification opens (Kotlin MainActivity
    /// `handleIntent`: action ``ACTION_OPEN_DIRECTIONS`` with ``EXTRA_SESSION_ID``); nil for
    /// anything else. Call it for the default action only
    /// (`response.actionIdentifier == UNNotificationDefaultActionIdentifier`).
    static func directionsSessionId(_ userInfo: [AnyHashable: Any]) -> String? {
        guard (userInfo[KEY_ACTION] as? String) == ACTION_OPEN_DIRECTIONS else { return nil }
        return userInfo[EXTRA_SESSION_ID] as? String
    }

    /// Kotlin `getIntExtra`: an integer, or a string of one (the content stores strings).
    private static func intExtra(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) }
        return nil
    }
}

/// What a reminder should do when it fires (Kotlin ReminderReceiver `remind`): every check is
/// re-done at that moment, against the current settings and data. The session must still be
/// mine (current "I'm speaking as") or still starred with this reminder time (or a shorter one
/// the planner kept, ``ReminderPlanner/accepts(_:_:)``), and not started yet; the minutes shown
/// are the real minutes left.
///
/// iOS delivers a scheduled notification without running app code, so this applies where the
/// app gets control: in the foreground (`userNotificationCenter(_:willPresent:)` shows it only
/// for ``show(title:text:channelId:expiresAt:)``); otherwise the reschedule on every change
/// (``ReminderScheduler``) is what keeps stale reminders from firing.
enum ReminderFiring: Sendable, Hashable {
    /// Notify: `title` / `text` (with the real minutes left), on `channelId`; the notification
    /// goes away at `expiresAt`, the end of the session (Kotlin `setTimeoutAfter`).
    case show(title: String, text: String, channelId: String, expiresAt: Date)
    /// The data has no such session any more (Kotlin returns silently).
    case unknownSession
    /// Not mine nor starred with this reminder time any more.
    case notWanted
    /// The session has started, or a later reminder of it is due too.
    case stale

    /// Kotlin `remind(context, sessionId, minutesBefore)`'s decision at `now`.
    static func check(
        _ sessionId: String,
        _ minutesBefore: Int,
        _ repo: Repository,
        _ me: String?,
        _ going: Set<String>,
        _ goingMinutes: Int,
        _ now: Date
    ) -> ReminderFiring {
        guard let session = repo.session(sessionId) else { return .unknownSession }
        guard let spec = ReminderPlanner.specFor(session, me, going, goingMinutes),
              ReminderPlanner.accepts(spec, minutesBefore)
        else { return .notWanted }
        guard let minutesLeft = ReminderPlanner.minutesLeftToShow(session.start, minutesBefore, now, spec.offsets) else {
            return .stale
        }
        let text = ReminderPlanner.text(spec.kind, minutesLeft, repo.roomOf(session))
        return .show(title: session.title, text: text, channelId: ReminderContent.channelFor(spec.kind), expiresAt: session.effectiveEnd)
    }

    /// True for ``show(title:text:channelId:expiresAt:)``.
    var shows: Bool {
        if case .show = self { return true }
        return false
    }

    /// Kotlin's log line for this outcome ("reminders: 1249844/10 \"Your talk in 10 min · …\" posted=true").
    func logLine(_ sessionId: String, _ minutesBefore: Int, now: Date, posted: Bool) -> String? {
        switch self {
        case .unknownSession: return nil
        case .notWanted: return "reminders: \(sessionId)/\(minutesBefore) skipped, not mine or going any more"
        case .stale: return "reminders: \(sessionId)/\(minutesBefore) skipped as stale at \(now)"
        case .show(_, let text, _, _): return "reminders: \(sessionId)/\(minutesBefore) \"\(text)\" posted=\(posted)"
        }
    }
}
