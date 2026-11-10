import Foundation

/// One reminder to arm: notify `minutesBefore` minutes before session `sessionId` starts.
///
/// `title` is the session title; `text` is the notification line, e.g.
/// "Your talk in 10 min · Grand Ballroom GI, Level 1" (``ReminderKind/mine``) or
/// "Starting in 10 min · Grand Ballroom GI, Level 1" (``ReminderKind/going``).
struct PlannedReminder: Sendable, Hashable {
    let sessionId: String
    let triggerAt: Date
    let minutesBefore: Int
    let title: String
    let text: String
    let kind: ReminderKind

    /// Stable identity of this reminder ("sessionId/minutes"), stored to cancel it later. On iOS
    /// it is also the `UNNotificationRequest` identifier.
    var key: String { ReminderPlanner.key(sessionId, minutesBefore) }
}

extension PlannedReminder {
    /// Kotlin `PlannedReminder(sessionId, triggerAt, minutesBefore, title, text, kind = MINE)`.
    init(_ sessionId: String, _ triggerAt: Date, _ minutesBefore: Int, _ title: String, _ text: String, _ kind: ReminderKind = .mine) {
        self.init(sessionId: sessionId, triggerAt: triggerAt, minutesBefore: minutesBefore, title: title, text: text, kind: kind)
    }
}

/// Why a session has reminders: I speak at it (30 and 10 min), or I starred it ("Going", one
/// reminder). Kotlin `MINE` / `GOING`.
enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    case mine = "MINE"
    case going = "GOING"
}

/// The reminders one session gets: `kind` and the minutes before its start, earliest first.
struct ReminderSpec: Sendable, Hashable {
    let kind: ReminderKind
    let offsets: [Int]
}

extension ReminderSpec {
    /// Kotlin `ReminderSpec(kind, offsets)`.
    init(_ kind: ReminderKind, _ offsets: [Int]) {
        self.init(kind: kind, offsets: offsets)
    }
}

/// Pure reminder logic (no platform APIs): which reminders to schedule, what they say, and
/// whether a firing reminder should still notify. Unit-tested with fixed instants.
///
/// iOS: the app layer schedules each ``PlannedReminder`` as a `UNNotificationRequest`
/// (identifier = ``PlannedReminder/key``, trigger at ``PlannedReminder/triggerAt``); iOS keeps at
/// most 64 pending requests, so schedule the soonest (the plan is sorted by trigger time).
enum ReminderPlanner {

    /// Minutes before each of the speaker's own sessions, earliest first (30 and 10).
    static let OFFSETS_MIN: [Int] = [30, 10]

    /// Every reminder still to come, keeping only those strictly after `now`, sorted by
    /// trigger time:
    /// - each session where `me` speaks (nil = None, so none): start − 30 and − 10 min;
    /// - each starred ("Going") session in `going`: one at start − `goingMinutes`
    ///   (`GoingStore.REMIND_OFF` = 0: none).
    ///
    /// A session that is both mine and starred gets only my 30/10 reminders, never a third one.
    /// Starred ids the data doesn't have are ignored.
    ///
    /// `armed` (the keys armed by the last reschedule) only matters when the "Going" lead time
    /// was just raised so close to a start that its new trigger is already past: the earlier,
    /// shorter reminder of that session that is still to come stays planned (e.g. 5 → 15 min
    /// at start − 8 keeps the start − 5 one), instead of the session losing its reminder.
    static func plan(
        _ sessions: [Session],
        _ rooms: OrderedMap<String, Room>,
        _ me: String?,
        _ now: Date,
        _ going: Set<String> = [],
        _ goingMinutes: Int = 0,
        _ armed: Set<String> = []
    ) -> [PlannedReminder] {
        if me == nil && (going.isEmpty || goingMinutes <= 0) { return [] }
        var armedBySession: [String: [Int]] = [:]
        for k in armed {
            if let (id, minutes) = parseKey(k) { armedBySession[id, default: []].append(minutes) }
        }
        var out: [PlannedReminder] = []
        for s in sessions {
            if !s.start.isAfter(now) { continue }
            guard let spec = specFor(s, me, going, goingMinutes) else { continue }
            let room = rooms[s.room]
            for m in spec.offsets {
                let at = s.start.minusMinutes(m)
                if at.isAfter(now) {
                    out.append(PlannedReminder(s.id, at, m, s.title, text(spec.kind, m, room), spec.kind))
                } else if spec.kind == .going {
                    // Too late for the new lead time: keep the shorter one already armed, if still to come.
                    let kept = (armedBySession[s.id] ?? [])
                        .filter { $0 >= 1 && $0 < m && s.start.minusMinutes($0).isAfter(now) }
                        .max()
                    if let kept {
                        let keptAt = s.start.minusMinutes(kept)
                        out.append(PlannedReminder(s.id, keptAt, kept, s.title, text(spec.kind, kept, room), spec.kind))
                    }
                }
            }
        }
        return out.stableSorted(with: KComparator<PlannedReminder>.by { $0.triggerAt }.thenBy { $0.sessionId })
    }

    /// Whether a firing reminder of `minutesBefore` still belongs to `spec`: one of its offsets,
    /// or, for "Going", a shorter one kept by ``plan(_:_:_:_:_:_:_:)`` after the lead time was raised late.
    static func accepts(_ spec: ReminderSpec, _ minutesBefore: Int) -> Bool {
        spec.offsets.contains(minutesBefore)
            || (spec.kind == .going && minutesBefore > 0 && minutesBefore < (spec.offsets.max() ?? 0))
    }

    /// The reminders `s` gets right now, ignoring the time: mine wins over starred (so a
    /// session that is both is reminded once, at 30 and 10 min); nil when it gets none.
    /// A firing reminder is re-checked against this.
    static func specFor(_ s: Session, _ me: String?, _ going: Set<String>, _ goingMinutes: Int) -> ReminderSpec? {
        if isMine(s, me) { return ReminderSpec(.mine, OFFSETS_MIN) }
        if goingMinutes > 0 && going.contains(s.id) { return ReminderSpec(.going, [goingMinutes]) }
        return nil
    }

    /// ``text(_:_:)`` for my talks, ``goingText(_:_:)`` for starred sessions.
    static func text(_ kind: ReminderKind, _ minutes: Int, _ room: Room?) -> String {
        switch kind {
        case .mine: return text(minutes, room)
        case .going: return goingText(minutes, room)
        }
    }

    /// "Your talk in 10 min · Grand Ballroom GI, Level 1". The level is left out when the room
    /// has none (OFF: "Your talk in 10 min · Off-site"), the room part when the room is unknown.
    static func text(_ minutes: Int, _ room: Room?) -> String { withRoom("Your talk in \(minutes) min", room) }

    /// A starred session: "Starting in 10 min · Grand Ballroom GI, Level 1", with the same room
    /// rules as ``text(_:_:)`` ("Starting in 10 min · Off-site", or no room part when unknown).
    static func goingText(_ minutes: Int, _ room: Room?) -> String { withRoom("Starting in \(minutes) min", room) }

    private static func withRoom(_ head: String, _ room: Room?) -> String {
        guard let room else { return head }
        let level = room.level.map { ", Level \($0)" } ?? ""
        return "\(head) · \(room.name)\(level)"
    }

    /// What a firing reminder should do at `now`: nil to skip it, otherwise the whole minutes
    /// left until `start` to show (the notification may be handled late, so this is the real
    /// figure, not the planned `minutesBefore`).
    ///
    /// Skips when the session has already started (stale), and skips an earlier reminder that
    /// ran so late that a later one of the same session (`offsets`: 30 and 10 for my talks, the
    /// one "Going" offset for a starred session) is due too, so the user isn't alerted twice for
    /// the same moment.
    static func minutesLeftToShow(_ start: Date, _ minutesBefore: Int, _ now: Date, _ offsets: [Int] = OFFSETS_MIN) -> Int? {
        if !now.isBefore(start) { return nil }
        let left = TimeFormat.minutesBetween(now, start).coerceAtLeast(1)
        if let nextOffset = offsets.filter({ $0 < minutesBefore }).max(), left <= nextOffset { return nil }
        return left
    }

    /// "sessionId/minutes" (session ids are digits or "m" + digits, so "/" can't clash).
    static func key(_ sessionId: String, _ minutesBefore: Int) -> String { "\(sessionId)/\(minutesBefore)" }

    /// Inverse of ``key(_:_:)``; nil for anything malformed.
    static func parseKey(_ key: String) -> (sessionId: String, minutes: Int)? {
        let i = key.kotlinLastIndexOf("/")
        if i <= 0 || i == key.kotlinLength - 1 { return nil }
        guard let minutes = minutesToIntOrNull(key.kotlinSubstring(i + 1)) else { return nil }
        return (key.kotlinSubstring(0, i), minutes)
    }

    /// Android's PendingIntent request code (`sessionId.hashCode() * 31 + minutesBefore`, with
    /// Java's 32-bit wrap-around). Always different for the reminders of one session (30, 15,
    /// 10 and 5 minutes). iOS identifies notifications by ``key(_:_:)`` instead; kept for parity.
    static func requestCode(_ sessionId: String, _ minutesBefore: Int) -> Int {
        var h: Int32 = 0
        for u in sessionId.utf16 { h = h &* 31 &+ Int32(u) }
        return Int(h &* 31 &+ Int32(truncatingIfNeeded: minutesBefore))
    }
}

/// Kotlin `String.toIntOrNull()`: an optional '+' / '-' sign then decimal digits (any Unicode
/// `Nd` digit, per UTF-16 unit, like `Character.digit`), within Int32; nil otherwise.
private func minutesToIntOrNull(_ s: String) -> Int? {
    let units = Array(s.utf16)
    if units.isEmpty { return nil }
    var i = 0
    var negative = false
    if units[0] < 0x30 {
        if units.count == 1 { return nil }
        if units[0] == 0x2D {
            negative = true
        } else if units[0] != 0x2B {
            return nil
        }
        i = 1
    }
    let limit: Int64 = negative ? Int64(Int32.max) + 1 : Int64(Int32.max)
    var value: Int64 = 0
    while i < units.count {
        guard let scalar = Unicode.Scalar(units[i]),
              scalar.properties.numericType == .decimal,
              let d = scalar.properties.numericValue
        else { return nil }
        value = value * 10 + Int64(d)
        if value > limit { return nil }
        i += 1
    }
    return Int(negative ? -value : value)
}
