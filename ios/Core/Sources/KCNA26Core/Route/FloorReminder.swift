import Foundation

/// The floor reminder, derived from a room and its route
/// (owner: engine). GPS can't tell floors apart, so Directions shows the room's floor in
/// large type plus what to do to get there:
///
/// - ``headline``: "Level 2 · Salt Palace · 251 A–C"
/// - ``instruction``: "Room is on Level 2: take the North Foyer escalator up"
///
/// ``action`` comes from the route's up/down step that arrives on the room's level: its first
/// sentence, with the first letter lower-cased and a trailing " to Level N" (or " on
/// Level N") dropped, because the level is already said. When the last level change is the
/// end of several hops in the same direction, the hops are joined with ", then " (for
/// Capitol Reef from 200 South: "take the Hyatt escalators or an elevator up, then take a
/// Hyatt elevator up one level"). With no level change on the way (a Level 1 room, or
/// starting on the right level) ``action`` is nil and ``instruction`` is just "Room is on
/// Level N". Pieces that aren't known are nil, never made up.
///
/// - `level`: the room's floor, nil for OFF.
/// - `building`: "Salt Palace" or "Hyatt Regency" (the web's `.loc .bd`), nil if unknown.
/// - `roomName`: the room's name, e.g. "251 A–C".
/// - `action`: what to do to reach `level`, or nil when the route doesn't change level.
/// - `direction`: ``StepKind/up`` or ``StepKind/down`` for `action`, nil without one.
/// - `hops`: how many up/down steps `action` covers (0 without one).
struct FloorReminder: Sendable, Hashable {
    let level: Int?
    let building: String?
    let roomName: String
    let action: String?
    let direction: StepKind?
    let hops: Int

    init(level: Int?, building: String?, roomName: String, action: String?, direction: StepKind? = nil, hops: Int = 0) {
        self.level = level
        self.building = building
        self.roomName = roomName
        self.action = action
        self.direction = direction
        self.hops = hops
    }

    init(_ level: Int?, _ building: String?, _ roomName: String, _ action: String?, _ direction: StepKind? = nil, _ hops: Int = 0) {
        self.init(level: level, building: building, roomName: roomName, action: action, direction: direction, hops: hops)
    }

    /// "Level 2 · Salt Palace · 251 A–C"; missing pieces are left out ("Off-site" for OFF).
    var headline: String {
        [level.map { "Level \($0)" }, building, roomName].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Level 2", or nil for OFF.
    var levelLabel: String? { level.map { "Level \($0)" } }

    /// "Salt Palace · 251 A–C" (the web's `.loc .bd` line).
    var buildingAndRoom: String { [building, roomName].compactMap { $0 }.joined(separator: " · ") }

    /// "Room is on Level 2: take the North Foyer escalator up", "Room is on Level 1", or nil for OFF.
    var instruction: String? {
        level.map { l in action.map { "Room is on Level \(l): \($0)" } ?? "Room is on Level \(l)" }
    }

    /// The reminder for `room`, reached by `route` (nil: no route, so no action).
    static func of(_ room: Room, _ route: Route?) -> FloorReminder {
        let level = room.level
        let base = FloorReminder(level: level, building: buildingName(room.venueCode), roomName: room.name, action: nil)
        guard let route, let level else { return base }
        let steps = route.steps
        guard let arrival = steps.lastIndex(where: { $0.kind.changesLevel && ($0.level == nil || $0.level == level) }) else {
            return base
        }
        let kind = steps[arrival].kind
        // Walk back over earlier hops in the same direction (walks in between are fine).
        var first = arrival
        for i in stride(from: arrival - 1, through: 0, by: -1) {
            let k = steps[i].kind
            if k == kind {
                first = i
            } else if k.changesLevel || k == .start {
                break
            }
        }
        let parts = (first...arrival).filter { steps[$0].kind == kind }.compactMap { actionOf(steps[$0].text) }
        if parts.isEmpty { return base }
        return FloorReminder(
            level: base.level,
            building: base.building,
            roomName: base.roomName,
            action: parts.joined(separator: ", then "),
            direction: kind,
            hops: parts.count
        )
    }

    /// The action part of one up/down step: "Take the North Foyer escalator up to Level 2.
    /// You arrive on the Upper Concourse." → "take the North Foyer escalator up".
    /// Nil for blank text.
    static func actionOf(_ stepText: String) -> String? {
        let t = stepText.kotlinTrim()
        let end = t.kotlinIndexOf(". ")
        let sentence = (end >= 0 ? t.kotlinSubstring(0, end) : t).removeSuffix(".").kotlinTrim()
        if sentence.isEmpty { return nil }
        let lowered = replaceFirstCharLowercase(sentence)
        let action = LEVEL_TAIL.replace(lowered, "").kotlinTrim()
        return action.isEmpty ? nil : action
    }

    /// "SP" → "Salt Palace", "HY" → "Hyatt Regency" (web wayHTML), else nil.
    static func buildingName(_ venueCode: String?) -> String? {
        switch venueCode {
        case "SP"?: "Salt Palace"
        case "HY"?: "Hyatt Regency"
        default: nil
        }
    }

    /// Kotlin `replaceFirstChar { it.lowercaseChar() }`: the first UTF-16 unit, lower-cased
    /// with Java's simple (one unit to one unit) case mapping.
    private static func replaceFirstCharLowercase(_ s: String) -> String {
        var units = Array(s.utf16)
        guard let c = units.first else { return s }
        let lower = javaToLowerCase(c)
        if lower == c { return s }
        units[0] = lower
        return String(decoding: units, as: UTF16.self)
    }

    /// " to Level 2" / " on Level 1" at the end of the sentence or before a comma.
    private static let LEVEL_TAIL = KRegex(" (?:to|on) Level \\d+(?=,|$)")
}
