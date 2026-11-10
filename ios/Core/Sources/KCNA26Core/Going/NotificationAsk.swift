import Foundation
import Observation

/// Notification permission is asked for in context, not at launch: the first time the user
/// stars a session, picks a name in "I’m speaking as" (Settings or the first-run picker), or
/// turns the "Going" reminders on; or, when reminders are already planned (a talk of mine or a
/// star still to come, e.g. the default speaker) and the app has never asked, when the app
/// comes to the foreground. The app asks at most once (`settings.notificationPermissionAsked`);
/// after that, a refused permission shows the inline notifications-off hint (``blocked(_:_:)``)
/// with a "Turn on" button (``turnOn(_:)``).
///
/// Android's POST_NOTIFICATIONS plumbing becomes `UNUserNotificationCenter` in the app layer,
/// which reads the permission (``Authorization``, from `notificationSettings().authorizationStatus`)
/// and asks for it (`requestAuthorization`) through a ``NotificationPermission``:
/// - `.notDetermined`: the ask is still to come; `requestAuthorization` shows the system dialog.
/// - `.denied`: refused in the dialog or switched off in Settings; the dialog never shows
///   again, so the hint's button opens the app's notification settings.
/// - `.authorized`, `.provisional`, `.ephemeral`: reminders can be delivered.
///
/// iOS has one notification switch per app: Android's per-channel switches ("Sessions you’re
/// going to", "Your talks") and its install-time grant before Android 13 have no counterpart,
/// so ``Block/channel`` never comes up on iOS.
enum NotificationAsk {

    // MARK: - permission (iOS)

    /// `UNAuthorizationStatus` as Core sees it (Core can't import UserNotifications). The app maps
    /// an `@unknown default` to ``authorized`` (don't nag about a state it can't explain).
    enum Authorization: String, Sendable, Hashable {
        /// Never asked: `requestAuthorization` shows the system dialog.
        case notDetermined
        /// Refused in the dialog, or turned off in Settings. Only Settings can turn it back on.
        case denied
        case authorized
        /// Quiet delivery to Notification Center (the app never asks for it, but it delivers).
        case provisional
        /// App Clips.
        case ephemeral

        /// Reminders can be delivered (Kotlin `hasPermission`).
        var allowsDelivery: Bool { self == .authorized || self == .provisional || self == .ephemeral }

        /// The system dialog can still be shown (Kotlin: Android 13+, not granted, not refused for good).
        var canAsk: Bool { self == .notDetermined }
    }

    // MARK: - the system dialog

    /// Holds ``asking`` (Kotlin's `asking` StateFlow): observable, so a SwiftUI view that reads
    /// ``NotificationAsk/asking`` updates when the dialog opens or answers.
    @MainActor
    @Observable
    final class DialogState {
        fileprivate(set) var asking = false
    }

    @MainActor static let dialog = DialogState()

    /// True while the system permission dialog is up (between ``requestStarted()`` and ``requestFinished()``).
    @MainActor static var asking: Bool { dialog.asking }

    /// The permission dialog is about to show.
    @MainActor static func requestStarted() {
        dialog.asking = true
    }

    /// The permission dialog has answered (granted or not).
    @MainActor static func requestFinished() {
        dialog.asking = false
    }

    // MARK: - when to ask

    /// The values ``triggers(_:_:_:)`` follows (Kotlin: the three flows it merges).
    struct Watched: Sendable, Equatable {
        let ids: Set<String>
        let speakingAs: String?
        let remindMinutes: Int
    }

    /// How many ``triggers(_:_:_:)`` emissions a change from `old` to `new` makes: one for each
    /// value that changed to something that needs notifications (RSVPs that aren't empty, a name
    /// in "I’m speaking as", the "Going" reminders on).
    static func triggerCount(_ old: Watched, _ new: Watched) -> Int {
        var n = 0
        if new.ids != old.ids && !new.ids.isEmpty { n += 1 }
        let nameChanged: Bool
        switch (old.speakingAs, new.speakingAs) {
        case (nil, nil): nameChanged = false
        case (let a?, let b?): nameChanged = !kotlinEquals(a, b)
        default: nameChanged = true
        }
        if nameChanged && new.speakingAs != nil { n += 1 }
        if new.remindMinutes != old.remindMinutes && new.remindMinutes > 0 { n += 1 }
        return n
    }

    /// Calls `onTrigger` each time the user does something that needs notifications: the RSVPs
    /// change and aren't empty, a name is picked in "I’m speaking as", or the "Going" reminders
    /// are turned on. Only changes made after the call count (the current values are skipped).
    /// Kotlin returns a `Flow<Unit>`; here the returned watch runs until
    /// ``TriggerWatch/cancel()`` (or until it is released).
    ///
    /// App layer (Kotlin `watch`, `repeatOnLifecycle(STARTED)`): start a watch whose
    /// `onTrigger` calls ``askOnce(_:_:)`` when the scene becomes active, cancel it when it leaves.
    @MainActor
    static func triggers(_ settings: SettingsStore, _ going: GoingStore, _ onTrigger: @escaping () -> Void) -> TriggerWatch {
        TriggerWatch(settings, going, onTrigger)
    }

    /// A running ``triggers(_:_:_:)`` (Kotlin: the collecting job).
    ///
    /// Every value the stores take is seen, also when several changes follow each other in one
    /// main-actor turn (as Kotlin's collector sees each StateFlow value): Observation reports a
    /// change as it is about to happen, when the store still holds the previous change's value,
    /// so that one is delivered then; the latest change is delivered on the next main-actor
    /// turn, or at once by ``flush()``.
    @MainActor
    final class TriggerWatch {
        private let settings: SettingsStore
        private let going: GoingStore
        private let onTrigger: () -> Void
        private var last: Watched
        private var active = true
        private var settleQueued = false

        fileprivate init(_ settings: SettingsStore, _ going: GoingStore, _ onTrigger: @escaping () -> Void) {
            self.settings = settings
            self.going = going
            self.onTrigger = onTrigger
            last = Watched(ids: going.ids, speakingAs: settings.speakingAs, remindMinutes: going.remindMinutes)
            track()
        }

        /// Stops the watch: no more `onTrigger` calls.
        func cancel() {
            active = false
        }

        /// Delivers a change not delivered yet now, instead of on the next main-actor turn.
        func flush() {
            guard active else { return }
            let current = Watched(ids: going.ids, speakingAs: settings.speakingAs, remindMinutes: going.remindMinutes)
            let n = NotificationAsk.triggerCount(last, current)
            last = current
            for _ in 0..<n where active { onTrigger() }
        }

        private func track() {
            withObservationTracking {
                _ = going.ids
                _ = settings.speakingAs
                _ = going.remindMinutes
            } onChange: { [weak self] in
                // The stores are @MainActor: their changes (and so this call) happen on the main actor.
                MainActor.assumeIsolated { self?.willChange() }
            }
        }

        /// One of the values is about to change (Observation's willSet; tracking fires once).
        private func willChange() {
            guard active else { return }
            flush()
            track()
            if !settleQueued {
                settleQueued = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.settleQueued = false
                    self.flush()
                }
            }
        }
    }

    /// True when at least one reminder is planned from `now` on (my talks under `me`, or a
    /// star in `going` with `goingMinutes` on): the app has something to deliver, so a
    /// pending permission is worth asking for at start.
    static func remindersToCome(
        _ sessions: [Session],
        _ rooms: OrderedMap<String, Room>,
        _ me: String?,
        _ now: Date,
        _ going: Set<String>,
        _ goingMinutes: Int
    ) -> Bool {
        !ReminderPlanner.plan(sessions, rooms, me, now, going, goingMinutes).isEmpty
    }

    /// The ask's rule (Kotlin MainActivity `askForNotificationsOnce`): at most once (`asked`),
    /// and only while the system can still show its dialog (`.notDetermined`; on iOS a refused
    /// permission never shows the dialog again, so there is nothing to ask).
    static func shouldAsk(_ status: Authorization, asked: Bool) -> Bool {
        status.canAsk && !asked
    }

    /// The start check (Kotlin `watch` / `remindersWaiting`): once per foreground, ask when the
    /// ask is still to come (``shouldAsk(_:asked:)``) and reminders are already planned
    /// (`toCome`, evaluated only then: ``remindersToCome(_:_:_:_:_:_:)``).
    static func remindersWaiting(_ status: Authorization, asked: Bool, _ toCome: () -> Bool) -> Bool {
        shouldAsk(status, asked: asked) && toCome()
    }

    /// ``remindersWaiting(_:asked:_:)`` with the app's stores and data at `now`.
    @MainActor
    static func remindersWaiting(_ status: Authorization, _ settings: SettingsStore, _ going: GoingStore, _ repo: Repository, _ now: Date) -> Bool {
        remindersWaiting(status, asked: settings.notificationPermissionAsked) {
            remindersToCome(repo.sessions, repo.rooms, settings.speakingAs, now, going.ids, going.remindMinutes)
        }
    }

    /// Kotlin MainActivity `askForNotificationsOnce`: reads the permission and, if
    /// ``shouldAsk(_:asked:)``, asks (``askNow(_:_:)``). Nil when it didn't ask, else whether
    /// permission was granted (then reschedule the reminders, as Kotlin does).
    @MainActor
    static func askOnce(_ settings: SettingsStore, _ permission: NotificationPermission) async -> Bool? {
        let status = await permission.status()
        // No suspension between the check and marking it asked: two triggers ask once.
        guard shouldAsk(status, asked: settings.notificationPermissionAsked) else { return nil }
        return await askNow(settings, permission)
    }

    /// Shows the system dialog now (``askOnce(_:_:)``, or the hint's "Turn on" while the
    /// permission is ``Authorization/notDetermined``): marks it asked, with ``asking`` true
    /// while the dialog is up. Returns whether permission was granted.
    @MainActor
    static func askNow(_ settings: SettingsStore, _ permission: NotificationPermission) async -> Bool {
        settings.notificationPermissionAsked = true
        requestStarted()
        let granted = await permission.request()
        requestFinished()
        return granted
    }

    // MARK: - the hint

    /// Why reminders can't be shown, as far as the user should be told: ``app`` the permission
    /// was refused or the app's notifications are off; ``channel`` only that channel is off
    /// (Android only: a deliberate choice, so only Settings mentions it). Kotlin `NONE` is
    /// ``nothing`` (`.none` would clash with `Optional.none` in a `Block?`).
    enum Block: Sendable, Hashable {
        case nothing
        case app
        case channel
    }

    /// Pure rule behind ``blocked(_:_:)``. Nothing is said while the system dialog is up
    /// (`asking`), or while the contextual ask is still to come (`needsRuntimeAsk`, not `asked`).
    static func blockOf(
        permission: Bool,
        appOn: Bool,
        channelOn: Bool,
        needsRuntimeAsk: Bool,
        asked: Bool,
        asking: Bool
    ) -> Block {
        if asking { return .nothing }
        if !permission { return needsRuntimeAsk && !asked ? .nothing : .app }
        if !appOn { return .app }
        if !channelOn { return .channel }
        return .nothing
    }

    /// ``blockOf(permission:appOn:channelOn:needsRuntimeAsk:asked:asking:)`` on iOS: the
    /// permission is the app's only switch (no separate app or channel switch), and an ask is
    /// still to come only while the system can show its dialog (``Authorization/canAsk``).
    static func blockOf(_ status: Authorization, asked: Bool, asking: Bool) -> Block {
        blockOf(
            permission: status.allowsDelivery,
            appOn: true,
            channelOn: true,
            needsRuntimeAsk: status.canAsk,
            asked: asked,
            asking: asking
        )
    }

    /// Kotlin `blocked(context, settings, channelId)`: the hint for `status`, just read from
    /// `UNUserNotificationCenter`. The SwiftUI hint (Kotlin `rememberNotificationsBlocked`)
    /// re-reads the status whenever the scene becomes active (back from the dialog or Settings)
    /// and when ``asking`` changes.
    @MainActor
    static func blocked(_ status: Authorization, _ settings: SettingsStore) -> Block {
        blockOf(status, asked: settings.notificationPermissionAsked, asking: asking)
    }

    /// What the hint's "Turn on" does (Kotlin `openSettings`: the channel's or the app's
    /// notification settings page).
    enum TurnOn: Sendable, Hashable {
        /// The system can still show its dialog: ``askNow(_:_:)``.
        case requestAuthorization
        /// The app's notification settings: `UIApplication.openNotificationSettingsURLString`
        /// (falling back to `openSettingsURLString`).
        case openSettings
    }

    /// ``TurnOn`` for `status`.
    static func turnOn(_ status: Authorization) -> TurnOn {
        status.canAsk ? .requestAuthorization : .openSettings
    }
}

/// The app layer's notification permission (`UNUserNotificationCenter`); tests use a fake.
protocol NotificationPermission: Sendable {
    /// `notificationSettings().authorizationStatus`, mapped to ``NotificationAsk/Authorization``.
    func status() async -> NotificationAsk.Authorization
    /// `requestAuthorization(options: [.alert, .sound])`: true when granted (false on an error).
    func request() async -> Bool
}
