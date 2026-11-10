import Foundation
import Observation

/// RSVPs ("Going" in code): the starred sessions, and how long before them to send a reminder.
/// Stored in a ``KeyValueStore`` ([PREFS] "kcna26.going", same keys as Android) and exposed as
/// observable properties. Setters write through at once and update the properties
/// synchronously, so they are safe to call from a tap handler.
///
/// Ids are kept exactly as starred: an id the current data doesn't have is ignored by the
/// schedule and the reminders, but stays here, so the star comes back if the session returns
/// in a later data set.
///
/// The App reschedules the reminders whenever ``ids`` or ``remindMinutes`` change.
@MainActor
@Observable
final class GoingStore {
    nonisolated static let PREFS = "kcna26.going"
    nonisolated static let REMIND_OFF = 0
    nonisolated static let DEFAULT_REMIND_MINUTES = 10

    /// The settings choices, in order: Off, 5, 10, 15 min.
    nonisolated static let REMIND_OPTIONS: [Int] = [REMIND_OFF, 5, 10, 15]

    private nonisolated static let KEY_IDS = "ids"
    private nonisolated static let KEY_REMIND = "remindMinutes"

    @ObservationIgnored private let prefs: KeyValueStore

    /// Starred session ids (unordered).
    private(set) var ids: Set<String>

    /// "Remind me before sessions I'm going to": minutes before the start, one of
    /// ``REMIND_OPTIONS``; ``REMIND_OFF`` (0) is Off. Defaults to ``DEFAULT_REMIND_MINUTES``.
    private(set) var remindMinutes: Int

    init(_ prefs: KeyValueStore) {
        self.prefs = prefs
        ids = prefs.stringSet(forKey: GoingStore.KEY_IDS) ?? []
        let stored = prefs.int(forKey: GoingStore.KEY_REMIND) ?? GoingStore.DEFAULT_REMIND_MINUTES
        remindMinutes = GoingStore.REMIND_OPTIONS.contains(stored) ? stored : GoingStore.DEFAULT_REMIND_MINUTES
    }

    func isGoing(_ sessionId: String) -> Bool { ids.contains(sessionId) }

    /// Stars or unstars `sessionId`. Returns the new state.
    @discardableResult
    func toggle(_ sessionId: String) -> Bool {
        let now = !isGoing(sessionId)
        setGoing(sessionId, now)
        return now
    }

    func setGoing(_ sessionId: String, _ going: Bool) {
        var next = ids
        if going { next.insert(sessionId) } else { next.remove(sessionId) }
        guard next != ids else { return }
        ids = next
        write()
    }

    /// Sets the reminder lead time; anything not in ``REMIND_OPTIONS`` is ignored.
    func setRemindMinutes(_ minutes: Int) {
        guard GoingStore.REMIND_OPTIONS.contains(minutes), minutes != remindMinutes else { return }
        prefs.set(minutes, forKey: GoingStore.KEY_REMIND)
        remindMinutes = minutes
    }

    private func write() {
        // Swift sets are values: the store gets its own copy (Kotlin had to copy explicitly).
        if ids.isEmpty {
            prefs.removeValue(forKey: GoingStore.KEY_IDS)
        } else {
            prefs.set(ids, forKey: GoingStore.KEY_IDS)
        }
    }
}
