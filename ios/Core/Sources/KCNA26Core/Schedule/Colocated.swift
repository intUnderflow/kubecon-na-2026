import Foundation

/*
 * The "Co-located events" section of a day (Monday): one card per CNCF-hosted co-located event,
 * built by ScheduleIndex.coloCards. Pure (unit-tested in ColocatedTests).
 *
 * A card disappears when its event ends (ColoEvent.end, the last talk's end), like finished
 * sessions do. Its agenda is what's left of the event: unfinished talks and the event's own
 * breaks (a break shared by several events is in each of their agendas), in time order. A break
 * that outlives every event it serves (CiliumCon's and FluxCon's lunches start as they end) then
 * joins the day's time blocks as an ordinary quiet break row (ScheduleIndex.dayView).
 */

/// One event's card.
struct ColoCard: Sendable, Hashable {
    let event: ColoEvent
    /// "9:00 AM–5:45 PM", or "Half day · 1:20–5:30 PM".
    let hours: String
    /// The glanceable line(s) under the hours, at most two: "Starts …"; or "Now …" and/or "Next …".
    let lines: [ColoLine]
    /// Unfinished talks and breaks, in time order (main room first at equal starts).
    let agenda: [ColoItem]
    /// One of the remaining talks is mine: the pink "You" marker.
    let mine: Bool
    /// One of the remaining talks has an Anthropic colleague (and isn't mine).
    let anthropic: Bool
    /// A talk is on now.
    let live: Bool

    var key: String { event.key }

    /// True when `sessionId` is still on this card's agenda.
    func holds(_ sessionId: String) -> Bool { agenda.contains { $0.session.id == sessionId } }
}

/// One agenda row: a talk, or a quiet break.
struct ColoItem: Sendable, Hashable {
    let session: Session
    let isBreak: Bool
    let live: Bool
    let mine: Bool
    let anthropic: Bool
    /// Room code to show: a talk outside the event's main room, or a break (they're in the foyers / lunch hall).
    let room: String?
}

/// A card's live line (Kotlin `sealed interface ColoLine` with `Starts`, `Now`, `Next`).
/// ``session`` is the talk it names.
///
/// ```swift
/// if case .now(let n) = line { n.minutesLeft }      // Kotlin `line as ColoLine.Now`
/// line.asStarts?.at                                 // Kotlin `(line as? ColoLine.Starts)?.at`
/// ColoText.label(.next(.init(s, nil, "Lunch")), roomName)
/// ```
enum ColoLine: Sendable, Hashable {
    /// Before the event: "Starts 9:00 AM · <first talk>" (opening remarks skipped), with the
    /// talk's own time when it isn't at `at`: "Starts 9:00 AM · First talk 9:10 · <title>".
    case starts(Starts)
    /// A talk is on (one line: the main room's, else the one ending first):
    /// "Now · 12 min left · <title>"; `room` when it isn't in the main room.
    case now(Now)
    /// The next talk: "Next 10:40 · <title>"; `during` names the event's break that's on
    /// ("Lunch · Next …").
    case next(Next)

    struct Starts: Sendable, Hashable {
        let at: Date
        let session: Session?
    }

    struct Now: Sendable, Hashable {
        let session: Session
        let minutesLeft: Int
        let room: String?
    }

    struct Next: Sendable, Hashable {
        let session: Session
        let room: String?
        let during: String?
    }

    /// The talk the line names (nil only for a `Starts` line of an event without talks left).
    var session: Session? {
        switch self {
        case .starts(let l): return l.session
        case .now(let l): return l.session
        case .next(let l): return l.session
        }
    }

    /// Kotlin `line as? ColoLine.Starts`.
    var asStarts: Starts? {
        if case .starts(let l) = self { return l }
        return nil
    }

    /// Kotlin `line as? ColoLine.Now`.
    var asNow: Now? {
        if case .now(let l) = self { return l }
        return nil
    }

    /// Kotlin `line as? ColoLine.Next`.
    var asNext: Next? {
        if case .next(let l) = self { return l }
        return nil
    }
}

extension ColoLine.Starts {
    /// Kotlin `ColoLine.Starts(at, session)`.
    init(_ at: Date, _ session: Session?) { self.init(at: at, session: session) }
}

extension ColoLine.Now {
    /// Kotlin `ColoLine.Now(session, minutesLeft, room)`.
    init(_ session: Session, _ minutesLeft: Int, _ room: String?) { self.init(session: session, minutesLeft: minutesLeft, room: room) }
}

extension ColoLine.Next {
    /// Kotlin `ColoLine.Next(session, room, during)`.
    init(_ session: Session, _ room: String?, _ during: String?) { self.init(session: session, room: room, during: during) }
}

/// A card's live lines, from what's left of its agenda (ScheduleIndex.coloCard, GoingLogic's filter).
enum ColoLines {
    /// The card's live line(s), at most two so a collapsed card stays compact: before the event
    /// "Starts 9:00 AM · First talk 9:10 · <title>"; during it one "Now" line (the main room's
    /// talk, else the one ending first: a second room's talk is in the agenda), then the next
    /// talk; between talks just the next one, prefixed by the event's break if one is on.
    static func of(_ e: ColoEvent, _ agenda: [ColoItem], _ now: Date) -> [ColoLine] {
        let talks = agenda.filter { !$0.isBreak }.map(\.session)
        if now.isBefore(e.start) {
            let first = talks.first { !ColoText.isRemarks($0) } ?? talks.first
            return [.starts(ColoLine.Starts(e.start, first))]
        }
        var out: [ColoLine] = []
        out.reserveCapacity(2)
        let main = e.mainRoom
        let live = talks.filter { ScheduleLogic.isLive($0, now) }
        let liveOrder = KComparator<Session>.by { $0.room == main ? 0 : 1 }
            .thenBy { $0.effectiveEnd }
            .thenBy { $0.start }
        if let shown = live.min(with: liveOrder) {
            let room: String? = shown.room != main ? shown.room : nil
            out.append(.now(ColoLine.Now(shown, ScheduleLogic.minutesLeft(shown, now), room)))
        }
        let nextOrder = KComparator<Session>.by { $0.start }.thenBy { $0.room == main ? 0 : 1 }
        if let next = talks.filter({ $0.start.isAfter(now) }).min(with: nextOrder) {
            let during: String? = live.isEmpty
                ? agenda.first { $0.isBreak && $0.live }.map { ScheduleLogic.breakTitle($0.session.title) }
                : nil
            let room: String? = next.room != main ? next.room : nil
            out.append(.next(ColoLine.Next(next, room, during)))
        }
        return out
    }
}

/// The card's strings.
enum ColoText {
    /// Section heading over the cards.
    static let SECTION = "Co-located events"

    /// "9:00 AM–5:45 PM", or "Half day · 1:20–5:30 PM" (the group cards' span style).
    static func hours(_ e: ColoEvent) -> String { hoursParts(e).joined(separator: " · ") }

    /// ``hours(_:)`` in the pieces a narrow card may wrap between: ["Half day", "1:20–5:30 PM"].
    static func hoursParts(_ e: ColoEvent) -> [String] {
        let span = ScheduleLogic.spanLabel(e.start, e.end)
        return e.halfDay ? ["Half day", span] : [span]
    }

    /// The line's label, before the title: "Starts 9:00 AM · First talk 9:10", "Now · 12 min left",
    /// "Now · 12 min left · 251 A–C", "Next 10:40", "Lunch · Next 12:45".
    static func label(_ line: ColoLine, _ roomName: (String) -> String) -> String {
        switch line {
        case .starts(let l):
            var s = "Starts " + TimeFormat.hma(l.at)
            if let talk = l.session, talk.start.isAfter(l.at) { s += " · First talk " + TimeFormat.hm(talk.start) }
            return s
        case .now(let l):
            var s = "Now · \(l.minutesLeft) min left"
            if let room = l.room { s += " · " + roomName(room) }
            return s
        case .next(let l):
            var s = ""
            if let during = l.during { s += during + " · " }
            s += "Next " + TimeFormat.hm(l.session.start)
            if let room = l.room { s += " · " + roomName(room) }
            return s
        }
    }

    /// The whole line as plain text (accessibility, tests): label · title.
    static func text(_ line: ColoLine, _ roomName: (String) -> String) -> String {
        label(line, roomName) + (line.session.map { " · " + $0.title } ?? "")
    }

    /// An agenda break row's text after its start time (which the row's time column shows):
    /// ["Coffee Break", "until 10:40", "Meeting room foyers"], joined with " · ", the first part bold.
    static func breakParts(_ s: Session, _ room: String?, _ roomName: (String) -> String) -> [String] {
        var parts = [ScheduleLogic.breakTitle(s.title)]
        if let end = s.end { parts.append("until " + TimeFormat.hm(end)) }
        if let room { parts.append(roomName(room)) }
        return parts
    }

    /// "Welcome + Opening Remarks" / "Closing Remarks": not what "Starts … · <first talk>" should name.
    static func isRemarks(_ s: Session) -> Bool { REMARKS.containsMatchIn(s.title) }

    private static let REMARKS = KRegex("^(Welcome\\b|Opening Remarks|Closing Remarks)", options: .ignoreCase)
}
