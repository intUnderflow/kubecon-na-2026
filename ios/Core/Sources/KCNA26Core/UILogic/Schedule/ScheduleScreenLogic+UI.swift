import Foundation

/// SwiftUI-side helpers of the Schedule screen that Kotlin gets from Compose: saving its
/// `rememberSaveable` sets in `@SceneStorage` (strings only), the keyed reset of `unstarred`
/// (Kotlin `rememberSaveable(goingOnly, dayKey)`), and the "hide agenda" scroll-back rule
/// expressed with what a SwiftUI list can measure (the card row's top in the viewport).
extension ScheduleScreenLogic {
    // MARK: - Saved sets (@SceneStorage)

    /// A string set as saved text: a JSON array of the members in sorted order; "" for none.
    static func encodeSet(_ set: Set<String>) -> String {
        if set.isEmpty { return "" }
        let members: [JSONValue] = set.sorted().map { JSONValue.string($0) }
        return JSON.serialize(.array(members))
    }

    /// ``encodeSet(_:)`` read back. Anything else ("", malformed text, non-string members) gives
    /// the empty set or skips the member, never throws: saved state is best effort.
    static func decodeSet(_ text: String) -> Set<String> {
        if text.isEmpty { return [] }
        guard let value = try? JSON.parse(text), let items = value.arrayValue else { return [] }
        var out: Set<String> = []
        for item in items {
            if let s = item.stringValue { out.insert(s) }
        }
        return out
    }

    // MARK: - unstarred (keyed by goingOnly and the day)

    /// The key `unstarred` is remembered under (Kotlin `rememberSaveable(goingOnly, dayKey)`):
    /// a new filter state or another day starts from an empty set. `dayKey` is the RESOLVED day
    /// (``ScheduleLogic/resolveDayKey(_:_:_:)`` at the current minute, = ``State/dayKey``), never
    /// the stored `selectedDay`: at midnight a stale selection moves on to the new today with
    /// `selectedDay` unchanged, and Kotlin starts a fresh set then.
    static func unstarredKey(goingOnly: Bool, dayKey: String?) -> String {
        (goingOnly ? "1" : "0") + "|" + (dayKey ?? "")
    }

    /// `unstarred` with the key it belongs to, saved as one string.
    struct SavedUnstarred: Sendable, Hashable {
        let key: String
        let ids: Set<String>

        init(key: String, ids: Set<String>) {
            self.key = key
            self.ids = ids
        }

        /// The set for `currentKey`: the saved ids while the key is unchanged, else empty (the
        /// view also resets the saved value when the key changes, as Compose drops the state).
        func ids(for currentKey: String) -> Set<String> {
            kotlinEquals(key, currentKey) ? ids : []
        }

        /// ``ScheduleScreenLogic/unstarredAfterToggle(_:_:nowGoing:goingOnly:)`` applied under `currentKey`.
        func afterToggle(_ id: String, nowGoing: Bool, goingOnly: Bool, currentKey: String) -> SavedUnstarred {
            let next = ScheduleScreenLogic.unstarredAfterToggle(ids(for: currentKey), id, nowGoing: nowGoing, goingOnly: goingOnly)
            return SavedUnstarred(key: currentKey, ids: next)
        }

        /// `{"key":"1|wed","ids":["a","b"]}`.
        var encoded: String {
            let members: [JSONValue] = ids.sorted().map { JSONValue.string($0) }
            let value: JSONValue = ["key": .string(key), "ids": .array(members)]
            return JSON.serialize(value)
        }

        /// ``encoded`` read back; "" or anything malformed is an empty set under key "".
        static func decode(_ text: String) -> SavedUnstarred {
            guard !text.isEmpty, let value = try? JSON.parse(text), let key = value["key"]?.stringValue else {
                return SavedUnstarred(key: "", ids: [])
            }
            var ids: Set<String> = []
            for item in value["ids"]?.arrayValue ?? [] {
                if let s = item.stringValue { ids.insert(s) }
            }
            return SavedUnstarred(key: key, ids: ids)
        }
    }

    // MARK: - Hiding an agenda

    /// Kotlin `onHideColo`'s scroll-back (``hideColoScrollTarget(_:_:firstVisibleIndex:firstVisibleOffset:)``)
    /// from the event card row's top edge relative to the list viewport's top (`cardTop`, points;
    /// negative = above it). Kotlin scrolls back when the card row is above the first visible row
    /// or is that row scrolled past its top, i.e. exactly when its top is above the viewport's
    /// top. `cardTop` nil (the card row was never laid out, e.g. after a banner jump straight to
    /// its agenda) counts as above: the agenda being hidden is below its card. Returns the row
    /// index to scroll to, or nil.
    static func hideColoScrollTarget(_ rows: [ScheduleRow], _ key: String, cardTop: Double?) -> Int? {
        let i = ScheduleRows.indexOfColoCard(rows, key)
        if i < 0 { return nil }
        if let top = cardTop, top >= 0 { return nil }
        return i
    }
}
