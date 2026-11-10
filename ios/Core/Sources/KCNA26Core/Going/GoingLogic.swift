import Foundation

/// Pure "Going" rules (no UI, no platform): the filter, clash detection and the "Up next" pick.
/// Unit-tested in Tests/KCNA26CoreTests/Going/.
enum GoingLogic {

    /// How soon a starred session must start to take "Up next" over one that is on now.
    static let SOON_MINUTES = 15

    /// The Going filter keeps starred sessions and my own talks.
    static func keeps(_ s: Session, _ going: Set<String>, _ me: String?) -> Bool {
        going.contains(s.id) || isMine(s, me)
    }

    // MARK: - filter

    /// `view` with only the sessions `keep` accepts: session cards and long rows are kept or
    /// dropped, group cards keep just their accepted kids (and go when none is left), and
    /// the half-hour blocks are rebuilt, so a group whose first kept kid starts later moves
    /// to that block. Co-located event cards (Monday) keep just their accepted talks (no breaks)
    /// and go when none is left. The "Up next" line and today's status line ("1 on now · Next at
    /// 11:45 AM") are worked out as in ``ScheduleIndex/dayView(_:_:_:)``, from the kept sessions only.
    static func filterDay(_ view: DayView, _ now: Date, _ keep: (Session) -> Bool) -> DayView {
        // Stable sort by the new start keeps the index's tie order (mine, then category, then room).
        let blocks: [Block] = view.slots
            .flatMap { $0.blocks }
            .compactMap { filterBlock($0, keep) }
            .stableSorted(on: { $0.start })
        let slots = Slot.build(view.day.key, blocks)
        var upNextBefore = -1
        if view.isToday {
            let nowMin = TimeFormat.minuteOfDay(now)
            if let i = slots.firstIndex(where: { $0.key > nowMin }), i > 0 { upNextBefore = i }
        }
        let colo = view.colo.compactMap { filterColo($0, now, keep) }
        var status: DayStatus? = nil
        if view.status != nil {
            // Like the index: no breaks, no long rows (those are in view.longs, not in the blocks).
            let fromBlocks: [Session] = blocks.flatMap { b -> [Session] in
                switch b {
                case .session(let sb): return sb.category == "log" ? [] : [sb.session]
                case .group(let gb): return gb.kids
                }
            }
            let fromColo: [Session] = colo.flatMap { card in card.agenda.map { $0.session } }
            let core = fromBlocks + fromColo
            let onNow = core.count { ScheduleLogic.isLive($0, now) }
            let next = core.filter { $0.start.isAfter(now) }.map { $0.start }.min()
            status = DayStatus(onNow, next)
        }
        return DayView(
            day: view.day,
            isToday: view.isToday,
            status: status,
            longsTitle: view.longsTitle,
            longs: view.longs.filter { keep($0.session) },
            longsFirst: view.longsFirst,
            slots: slots,
            upNextBefore: upNextBefore,
            colo: colo
        )
    }

    /// A co-located event card with only the talks `keep` accepts, or nil when none is left.
    /// Its live lines come from those talks (the event's breaks still name a "Lunch · Next …").
    static func filterColo(_ card: ColoCard, _ now: Date, _ keep: (Session) -> Bool) -> ColoCard? {
        let talks = card.agenda.filter { !$0.isBreak && keep($0.session) }
        if talks.isEmpty { return nil }
        let breaks = card.agenda.filter { $0.isBreak }
        let agenda = (talks + breaks).stableSorted(on: { $0.session.start })
        return ColoCard(
            event: card.event,
            hours: card.hours,
            lines: ColoLines.of(card.event, agenda, now),
            agenda: talks,
            mine: talks.contains { $0.mine },
            anthropic: talks.contains { $0.anthropic },
            live: talks.contains { $0.live }
        )
    }

    private static func filterBlock(_ b: Block, _ keep: (Session) -> Bool) -> Block? {
        switch b {
        case .session(let sb):
            return keep(sb.session) ? b : nil
        case .group(let gb):
            let kept = gb.kids.filter(keep)
            return kept.isEmpty ? nil : .group(GroupBlock(gb.group, kept))
        }
    }

    /// `results` with only the sessions `keep` accepts; days left empty are dropped.
    static func filterSearch(_ results: SearchResults, _ keep: (Session) -> Bool) -> SearchResults {
        let days: [SearchDay] = results.days.compactMap { d in
            let kept = d.sessions.filter { keep($0.session) }
            return kept.isEmpty ? nil : SearchDay(d.day, kept)
        }
        return SearchResults(days.reduce(0) { $0 + $1.sessions.count }, days)
    }

    /// The Going filter's note (title, text), or nil for none. When the filter leaves nothing
    /// from a day or search that has something, the note replaces the usual empty state; when
    /// nothing is starred at all but my own talks are left, it follows them (how to star).
    /// A day whose starred sessions are all over says so, and every note about a day names
    /// the other days that still have stars ("You have 3 on Wednesday.").
    static func emptyText(
        _ goingOnly: Bool,
        _ fullView: DayView?,
        _ view: DayView?,
        _ allResults: SearchResults?,
        _ results: SearchResults?,
        _ index: ScheduleIndex,
        _ going: Set<String>,
        _ now: Date,
        _ remindMinutes: Int
    ) -> (title: String, text: String)? {
        if !goingOnly { return nil }
        let anyStarred = going.contains { index.repo.sessionsById[$0] != nil }
        let none: (title: String, text: String) = (GoingText.NONE_TITLE, GoingText.noneText(remindMinutes))
        if let allResults {
            guard let results, allResults.count != 0 else { return nil }
            if results.count > 0 { return anyStarred ? nil : none }
            return anyStarred ? (GoingText.SEARCH_TITLE, GoingText.SEARCH_TEXT) : none
        }
        guard let fullView, let view, !fullView.isEmpty else { return nil }
        if !view.isEmpty { return anyStarred ? nil : none }
        if !anyStarred { return none }
        let day = fullView.day
        let others: [(count: Int, day: String)] = starredLeftByDay(index, going, now)
            .filter { $0.dayKey != day.key }
            .map { left in (left.count, index.repo.day(left.dayKey)?.label.substringBefore(",") ?? left.dayKey) }
        let doneToday = fullView.isToday &&
            index.sessionsOn(day.key).contains { going.contains($0.id) && ScheduleLogic.isFinished($0, now) }
        if doneToday {
            return (GoingText.DONE_TITLE, GoingText.doneText(others))
        }
        return (GoingText.dayTitle(day.label), GoingText.dayText(others))
    }

    /// (day key, starred sessions not finished at `now`) for each day that has some, in day order.
    static func starredLeftByDay(_ index: ScheduleIndex, _ going: Set<String>, _ now: Date) -> [(dayKey: String, count: Int)] {
        if going.isEmpty { return [] }
        return index.days.compactMap { (d: Day) -> (dayKey: String, count: Int)? in
            let n = index.sessionsOn(d.key).count { going.contains($0.id) && !ScheduleLogic.isFinished($0, now) }
            return n > 0 ? (d.key, n) : nil
        }
    }

    // MARK: - clashes

    /// True when the two sessions overlap in time (back-to-back is not a clash).
    static func overlaps(_ a: Session, _ b: Session) -> Bool {
        a.start.isBefore(b.effectiveEnd) && b.start.isBefore(a.effectiveEnd)
    }

    /// Whether `s` takes part in clash detection: not a long row (co-located, off-site, all-day:
    /// something people drop in and out of, which would otherwise clash with everything) and
    /// not a break.
    private static func clashable(_ index: ScheduleIndex, _ s: Session) -> Bool {
        !index.isLong(s) && !index.isBreak(s)
    }

    /// For each starred session still in the data, the other starred sessions and my own
    /// talks it overlaps, by start time. Sessions finished at `now` don't count (a clash
    /// with something that is over doesn't matter any more); nil `now` keeps everything.
    /// Not clashes: two sessions in the same room (e.g. posters of one poster session, or
    /// keynotes whose times overlap by a minute: you're there for both), and long rows
    /// (``clashable``). Starred sessions without a clash are not in the map.
    static func clashes(_ index: ScheduleIndex, _ going: Set<String>, _ me: String?, _ now: Date? = nil) -> [String: [Clash]] {
        if going.isEmpty { return [:] }
        let repo = index.repo
        let counts = { (s: Session) -> Bool in
            if let now, ScheduleLogic.isFinished(s, now) { return false }
            return clashable(index, s)
        }
        let starred = going.compactMap { repo.sessionsById[$0] }.filter(counts)
        if starred.isEmpty { return [:] }
        var all = OrderedMap<String, Session>()
        for s in starred { all[s.id] = s }
        for s in repo.mySessions(me) where counts(s) { all[s.id] = s }
        let candidates = all.values.stableSorted(with: KComparator<Session>.by { $0.start }.thenBy { $0.id })
        var out: [String: [Clash]] = [:]
        for s in starred {
            let with = candidates.filter { $0.id != s.id && $0.room != s.room && overlaps(s, $0) }
            if !with.isEmpty { out[s.id] = with.map { Clash($0, mine: isMine($0, me)) } }
        }
        return out
    }

    /// ``clashes(_:_:_:_:)`` for one session (empty when it isn't starred or clashes with nothing).
    static func clashesFor(_ index: ScheduleIndex, _ s: Session, _ going: Set<String>, _ me: String?, _ now: Date? = nil) -> [Clash] {
        if !going.contains(s.id) { return [] }
        return clashes(index, going, me, now)[s.id] ?? []
    }

    // MARK: - up next

    /// The "Up next" row for `dayKey`'s list: my next (or live) starred session today, or nil
    /// when `dayKey` isn't today or nothing starred is left today. My own talks are left out
    /// (the "You’re speaking" banner has them), and so are breaks.
    ///
    /// Pick: the next starred session to start, unless one is on now and the next doesn't
    /// start within ``SOON_MINUTES``; then the live one (the latest to have started). A long row
    /// (co-located, off-site) that is on now only counts as live when nothing else starred is
    /// left today, so an all-day event doesn't hide the talks in between.
    static func upNext(_ index: ScheduleIndex, _ dayKey: String?, _ going: Set<String>, _ me: String?, _ now: Date) -> GoingNext? {
        guard !going.isEmpty, let dayKey else { return nil }
        guard let today = ScheduleLogic.todayKey(index.days, now), dayKey == today else { return nil }
        let left = index.sessionsOn(today).filter {
            going.contains($0.id) && !isMine($0, me) && !index.isBreak($0) && !ScheduleLogic.isFinished($0, now)
        }
        if left.isEmpty { return nil }
        let byStart = KComparator<Session>.by { $0.start }.thenBy { $0.id }
        let next = left.filter { $0.start.isAfter(now) }.min(with: byStart)
        let onNow = left.filter { ScheduleLogic.isLive($0, now) }
        var live = onNow.filter { !index.isLong($0) }.max(with: byStart)
        if live == nil && left.allSatisfy({ index.isLong($0) }) {
            live = onNow.max(with: byStart)
        }
        let picked: Session?
        if let live {
            if let next, TimeFormat.minutesBetween(now, next.start) <= SOON_MINUTES {
                picked = next
            } else {
                picked = live
            }
        } else {
            picked = next
        }
        guard let pick = picked else { return nil }
        let isLive = ScheduleLogic.isLive(pick, now)
        let room = index.repo.room(pick.room)
        let countdownText: String
        if !isLive {
            countdownText = countdown(TimeFormat.minutesBetween(now, pick.start))
        } else if index.isLong(pick) {
            countdownText = "until " + TimeFormat.hma(pick.effectiveEnd)
        } else {
            countdownText = "\(ScheduleLogic.minutesLeft(pick, now)) min left"
        }
        return GoingNext(
            session: pick,
            live: isLive,
            label: isLive ? GoingText.ON_NOW : GoingText.YOUR_NEXT,
            countdown: countdownText,
            time: TimeFormat.range(pick),
            roomName: index.roomName(pick.room),
            level: room?.level.map { "Level \($0)" },
            canRoute: room?.hasPosition == true
        )
    }

    /// "in 12 min", "in 1h", "in 1h 5m" (the banner's countdown, lower-case to follow a label).
    static func countdown(_ minutesUntil: Int) -> String {
        let label = ScheduleLogic.countdownLabel(minutesUntil.coerceAtLeast(1))
        // Kotlin replaceFirstChar { it.lowercaseChar() }: the label always starts with "In".
        guard let first = label.first else { return label }
        return String(first).lowercased() + label.dropFirst()
    }
}

/// A session a starred one overlaps: another starred session, or one of my talks (`mine`).
struct Clash: Sendable, Hashable {
    let session: Session
    let mine: Bool
}

extension Clash {
    /// Kotlin `Clash(session, mine = …)`.
    init(_ session: Session, mine: Bool) {
        self.init(session: session, mine: mine)
    }
}

/// The "Up next" row: my next (or live) starred session today.
struct GoingNext: Sendable, Hashable {
    let session: Session
    let live: Bool
    /// "Your next", or "On now" when `live` (never "Up next": the timeline line has that name).
    let label: String
    /// "in 12 min", "in 1h 5m"; when `live` "8 min left" ("until 5:00 PM" for co-located / off-site rows).
    let countdown: String
    /// "10:30–11:00 AM".
    let time: String
    /// "251 A–C".
    let roomName: String
    /// "Level 2", or nil when the room has none (off-site).
    let level: String?
    /// The room is on the map, so Directions can route to it.
    let canRoute: Bool
}

/// Wording for the Going filter's empty states and hints.
enum GoingText {
    static let CHIP = "RSVP’d"
    static let CHIP_DESCRIPTION = "RSVP’d: only sessions you’ve RSVP’d to, and your talks"
    static let MARK = "RSVP"
    static let GOING = "RSVP’d"
    static let YOUR_NEXT = "Your next"
    static let ON_NOW = "On now"
    static let CLASH = "Clash"
    static let CLASHES_WITH = "Clashes with"
    static let YOUR_TALK = "Your talk"
    static let SETTING_TITLE = "Remind me before sessions I’ve RSVP’d to"
    /// The notifications-off hint (``NotificationAsk/Block/app``: refused, or off in Settings).
    static let NOTIFICATIONS_OFF = "Notifications are off for this app, so reminders can’t reach you."
    /// Android notification-channel hints (``NotificationAsk/Block/channel``). iOS has no
    /// per-channel switch, so the iOS app never shows these; kept for parity.
    static let GOING_CHANNEL_OFF = "Reminders for sessions you’ve RSVP’d to are turned off."
    static let TALKS_CHANNEL_OFF = "Reminders for your talks are turned off."
    /// The hint's button: asks again while the system can still show its dialog, else opens
    /// the app's notification settings (``NotificationAsk/turnOn(_:)``).
    static let TURN_ON = "Turn on"

    /// RSVPs are a personal mark: say so, so nobody thinks they registered with the organisers.
    static let PRIVATE_NOTE = "RSVPs stay on this phone; they don’t register you with the organisers."

    /// A card or row star: "RSVP’d: <title>" / "RSVP: <title>" (just the state without a `title`).
    static func starDescription(_ going: Bool, _ title: String?) -> String {
        (going ? GOING : MARK) + (title.map { ": " + $0 } ?? "")
    }

    static let NONE_TITLE = "No RSVPs yet"
    static let SEARCH_TITLE = "No RSVP’d matches"
    static let SEARCH_TEXT = "Turn off RSVP’d to search every session."

    /// Nothing starred at all: how to star.
    static func noneText(_ remindMinutes: Int) -> String {
        "Turn off RSVP’d above, then tap the star on any session to RSVP. It shows up here" +
            (remindMinutes > 0 ? ", with a reminder \(remindMinutes) min before it starts." : ".") +
            " \(PRIVATE_NOTE)"
    }

    /// Stars exist, but none on this day: "No RSVPs for Wednesday".
    static func dayTitle(_ dayLabel: String) -> String { "No RSVPs for \(dayLabel.substringBefore(","))" }

    static let DAY_TEXT = "Turn off RSVP’d above to see the whole day, then tap the star on the sessions you want."

    /// Today's starred sessions are all over.
    static let DONE_TITLE = "No RSVPs left today"

    /// "You have 3 on Wednesday and 1 on Thursday." from (count, day name) pairs; "" for none.
    static func othersText(_ others: [(count: Int, day: String)]) -> String {
        if others.isEmpty { return "" }
        let parts = others.map { "\($0.count) on \($0.day)" }
        let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        return "You have \(list)."
    }

    /// No stars on this day: the other days that have some, then how to star here.
    static func dayText(_ others: [(count: Int, day: String)]) -> String {
        let o = othersText(others)
        return o.isEmpty ? DAY_TEXT : "\(o) \(DAY_TEXT)"
    }

    /// Today's starred sessions are over: say so, and where the others are.
    static func doneText(_ others: [(count: Int, day: String)]) -> String {
        ["Your RSVP’d sessions for today are over.", othersText(others), "Turn off RSVP’d above to see what’s still on."]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Settings choice label: "Off", "5 min".
    static func optionLabel(_ minutes: Int) -> String { minutes <= 0 ? "Off" : "\(minutes) min" }

    /// Settings summary under the choice (`me`: "I’m speaking as", nil = None).
    static func settingSummary(_ minutes: Int, _ me: String? = nil) -> String {
        if minutes <= 0 {
            return "No reminders for sessions you’ve RSVP’d to." + (me != nil ? " Your own talks still get theirs." : "")
        }
        return "One notification \(minutes) min before each session you’ve RSVP’d to, with the room and level. Tap it for directions. \(PRIVATE_NOTE)"
    }
}
