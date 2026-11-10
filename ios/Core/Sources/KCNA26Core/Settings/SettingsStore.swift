import Foundation
import Observation

/// User settings in a ``KeyValueStore`` ([PREFS] "kcna26.settings", same keys as Android),
/// exposed as observable properties. Setters write through immediately and update the
/// properties synchronously.
///
/// In SwiftUI: read `settings.speakingAs` in a view body (it is `@Observable`).
/// The App reschedules reminders whenever ``speakingAs`` changes, so callers of
/// ``setSpeakingAs(_:)`` don't need to.
@MainActor
@Observable
final class SettingsStore {
    nonisolated static let PREFS = "kcna26.settings"
    /// The schedule's own "me" (schedule.json). No longer the default: fresh installs start at None.
    nonisolated static let DEFAULT_SPEAKER = "Lucy Sweet"
    nonisolated static let FROM_LIVE = "LIVE"
    private nonisolated static let KEY_SPEAKING_AS = "speakingAs"
    private nonisolated static let KEY_FROM = "directionsFrom"
    private nonisolated static let KEY_NOTIF_ASKED = "notifAsked"
    private nonisolated static let KEY_FIRST_RUN_DONE = "firstRunDone"
    /// Stored value meaning "None" (no speaker has an empty name).
    private nonisolated static let NONE = ""

    @ObservationIgnored private let prefs: KeyValueStore

    /// "I'm speaking as": a speaker name, or nil for None. None until the user picks someone
    /// (in the first-run picker or Settings).
    private(set) var speakingAs: String?

    /// True on a fresh install until the first-run picker ("Speaking at KubeCon? Pick your
    /// name") is answered with a name or Skip. Never true once ``speakingAs`` has been set
    /// explicitly (a name or None).
    private(set) var firstRunPending: Bool

    /// Directions "From" choice: ``FROM_LIVE`` ("LIVE", the default = My location), an entrance
    /// key (E200S, EWT, EHY, E200W) or a room code.
    private(set) var directionsFrom: String

    init(_ prefs: KeyValueStore) {
        self.prefs = prefs
        speakingAs = SettingsStore.readSpeakingAs(prefs)
        directionsFrom = prefs.string(forKey: SettingsStore.KEY_FROM) ?? SettingsStore.FROM_LIVE
        firstRunPending = !prefs.contains(SettingsStore.KEY_SPEAKING_AS)
            && !(prefs.bool(forKey: SettingsStore.KEY_FIRST_RUN_DONE) ?? false)
    }

    /// False until the user has explicitly chosen a speaker or None (distinguishes "never set" from None).
    var isSpeakingAsSet: Bool { prefs.contains(SettingsStore.KEY_SPEAKING_AS) }

    /// Sets "I'm speaking as"; nil means None.
    func setSpeakingAs(_ name: String?) {
        prefs.set(name ?? SettingsStore.NONE, forKey: SettingsStore.KEY_SPEAKING_AS)
        speakingAs = name
        firstRunPending = false
    }

    /// Answers the first-run picker: a `name` sets "I'm speaking as" (reminders follow, like any
    /// change); nil is Skip, which leaves it at None.
    func finishFirstRun(_ name: String?) {
        if let name { setSpeakingAs(name) }
        prefs.set(true, forKey: SettingsStore.KEY_FIRST_RUN_DONE)
        firstRunPending = false
    }

    /// The first-run sheet was swiped away or dismissed: hide it for this process only, so it
    /// asks again on the next cold start. Only a name or Skip (``finishFirstRun(_:)``) is final.
    func dismissFirstRunForNow() {
        firstRunPending = false
    }

    /// Forgets the choice, so ``speakingAs`` goes back to the default (None).
    func resetSpeakingAs() {
        prefs.removeValue(forKey: SettingsStore.KEY_SPEAKING_AS)
        speakingAs = nil
    }

    func setDirectionsFrom(_ value: String) {
        prefs.set(value, forKey: SettingsStore.KEY_FROM)
        directionsFrom = value
    }

    /// True once the app has asked for notification permission (asked only once; Android:
    /// POST_NOTIFICATIONS, iOS: `UNUserNotificationCenter.requestAuthorization`).
    var notificationPermissionAsked: Bool {
        get { prefs.bool(forKey: SettingsStore.KEY_NOTIF_ASKED) ?? false }
        set { prefs.set(newValue, forKey: SettingsStore.KEY_NOTIF_ASKED) }
    }

    private static func readSpeakingAs(_ prefs: KeyValueStore) -> String? {
        guard prefs.contains(KEY_SPEAKING_AS) else { return nil }
        let v = prefs.string(forKey: KEY_SPEAKING_AS)
        return (v == nil || v == NONE) ? nil : v
    }
}
