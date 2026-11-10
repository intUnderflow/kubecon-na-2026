import Foundation

/// Remembers which reminder notifications are scheduled (their `ReminderPlanner.key`s), so the
/// next reschedule can cancel the ones that no longer apply, for example after "I'm speaking
/// as" changes to someone else or None. Prefs file [PREFS] "kcna26.reminders" (key "armed").
///
/// iOS: the keys double as `UNNotificationRequest` identifiers. Not main-actor bound: the
/// reschedule may run in a background task. Thread-safe (the store is).
final class ReminderStore: Sendable {
    static let PREFS = "kcna26.reminders"
    private static let KEY_ARMED = "armed"

    private let prefs: KeyValueStore

    init(_ prefs: KeyValueStore) {
        self.prefs = prefs
    }

    /// Keys armed by the last reschedule.
    func armed() -> Set<String> { prefs.stringSet(forKey: ReminderStore.KEY_ARMED) ?? [] }

    /// Replaces the armed set. Skips the write when nothing changed.
    func setArmed(_ keys: Set<String>) {
        guard keys != armed() else { return }
        if keys.isEmpty {
            prefs.removeValue(forKey: ReminderStore.KEY_ARMED)
        } else {
            prefs.set(keys, forKey: ReminderStore.KEY_ARMED)
        }
    }
}
