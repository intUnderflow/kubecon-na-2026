import Foundation

/// Everything the schedule screen shows, computed from the ``Repository``, "now" and "me" (the
/// "I'm speaking as" name; nil = None). Pure and platform-free.
///
/// Ports schedule_app.js `renderDay` (``dayView(_:_:_:)``), `renderMine` (``banner(_:_:_:searching:)``),
/// `renderSearch` (``search(_:_:_:)``) and the day tabs of `render` (``dayTabs(_:_:)``). "Mine"
/// and "Anthropic" are always worked out here from the speakers list (never the precomputed
/// JSON flags).
///
/// Co-located events (colocated.json): each event is one card in the day's "Co-located events"
/// section (``coloCards(_:_:_:)``) holding its talks and breaks, so those never appear one by
/// one in the half-hour blocks (a break that outlives all its events' cards joins the blocks
/// then); the schedule.json placeholders they replace are never shown (``isHidden(_:)``).
/// Everything else about a co-located talk (search, details, mine/Anthropic, the banner) is
/// ordinary.
///
/// Build once per repository with ``of(_:)`` (cached), then call the builders as often as
/// needed: each is a cheap pass over one day (≤ 200 sessions) or the week. Immutable and
/// `Sendable`: build it off the main actor, use it anywhere.
final class ScheduleIndex: Sendable {
    let repo: Repository
    var days: [Day] { repo.days }
    var anthropicSpeakers: Set<String> { repo.anthropicSpeakers }

    /// The per-session rules every builder uses (category / group fixes, hidden, long, co-located).
    private let rules: ScheduleIndexRules

    /// Days with co-located event cards in the data (Monday), whatever the time.
    private let coloDays: Set<String>

    private let byDay: [String: [Session]]

    /// Room sort order: rooms.json order, which equals the web's `Object.keys(R)`.
    private let roomOrder: [String: Int]

    /// Every group (web `SERIES`), in order of first appearance; kids sorted by start. Co-located
    /// talks (grouped by event in the JSON) are their event's card instead, so they're not here.
    let groups: OrderedMap<String, GroupInfo>

    private let groupOfSession: [String: String]

    /// Each co-located event's whole agenda (talks and the breaks it lists), by start; at equal
    /// starts talks before breaks, the main room first, then rooms.json order.
    let coloAgendas: OrderedMap<String, [Session]>

    /// Normalised search text per session id, without the "anthropic" flag (web `x.hay`).
    /// Built on first use (Kotlin `by lazy(SYNCHRONIZED)`).
    private let haystack: SynchronizedLazy<[String: String], Never>

    init(_ repo: Repository) {
        self.repo = repo

        // Three talks titled "Breaking…" are filed as breaks in the JSON; re-run the web rules for them.
        var cats: [String: String] = [:]
        var fixedGroups: [String: SessionGroup?] = [:]
        for s in repo.sessions where !s.isColocated && ScheduleRules.isMisfiledBreak(s) {
            let cat = ScheduleRules.catOf(s)
            cats[s.id] = cat
            fixedGroups[s.id] = .some(ScheduleRules.seriesOf(s, cat))
        }
        let rules = ScheduleIndexRules(repo: repo, categoryFix: cats, groupFix: fixedGroups)
        self.rules = rules

        coloDays = Set(repo.coloEvents.map(\.day))
        var byDay: [String: [Session]] = [:]
        for s in repo.sessions { byDay[s.day, default: []].append(s) }
        self.byDay = byDay
        let roomOrder: [String: Int] = Dictionary(
            repo.rooms.keys.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        self.roomOrder = roomOrder

        // groups
        var acc = OrderedMap<String, [Session]>()
        var first: [String: Session] = [:]
        var titles: [String: String] = [:]
        for s in repo.sessions {
            if rules.inColoCard(s) || rules.isHidden(s) { continue }
            guard let g = rules.group(s) else { continue }
            if acc.containsKey(g.key) { acc[g.key]!.append(s) } else { acc[g.key] = [s] }
            if first[g.key] == nil {
                first[g.key] = s
                titles[g.key] = g.title
            }
        }
        var out = OrderedMap<String, GroupInfo>()
        for (key, kids) in acc {
            let f = first[key]!
            out[key] = GroupInfo(
                key: key,
                title: titles[key]!,
                day: f.day,
                room: f.room,
                category: rules.category(f),
                kids: kids.stableSorted(on: { $0.start }),
                end: kids.map(\.effectiveEnd).max()!
            )
        }
        groups = out

        var groupOf: [String: String] = [:]
        for g in out.values {
            for k in g.kids { groupOf[k.id] = g.key }
        }
        groupOfSession = groupOf

        // coloAgendas
        var agendas = OrderedMap<String, [Session]>()
        for e in repo.coloEvents { agendas[e.key] = [] }
        for s in repo.sessions {
            for e in rules.coloEventsOf(s) { agendas[e.key]!.append(s) }
        }
        coloAgendas = agendas.mapValuesWithKey { key, xs in
            let main = repo.coloEvent(key)?.mainRoom
            let order = KComparator<Session>.by { $0.start }
                .thenBy { rules.isBreak($0) ? 1 : 0 }
                .thenBy { $0.room == main ? 0 : 1 }
                .thenBy { roomOrder[$0.room] ?? Int.max }
            return xs.stableSorted(with: order)
        }

        haystack = SynchronizedLazy<[String: String], Never> {
            var h: [String: String] = [:]
            h.reserveCapacity(repo.sessions.count)
            for s in repo.sessions {
                let parts: [String] = [
                    s.title,
                    s.speakers.joined(separator: ", "),
                    rules.roomName(s.room),
                    s.note ?? "",
                    rules.categoryLabel(rules.category(s)),
                    // Co-located talks: "argocon" finds all of ArgoCon's; also topic, format and level.
                    rules.coloEventOf(s)?.name ?? "",
                    s.topic ?? "",
                    s.format ?? "",
                    s.level ?? "",
                ]
                h[s.id] = TextMatch.normalize(parts.joined(separator: " "))
            }
            return h
        }
    }

    /// The session's category key (the JSON value, corrected for misfiled "Breaking…" talks).
    func category(_ s: Session) -> String { rules.category(s) }

    /// The session's group (the JSON value, corrected like ``category(_:)``).
    func group(_ s: Session) -> SessionGroup? { rules.group(s) }

    /// A quiet break row (category log).
    func isBreak(_ s: Session) -> Bool { rules.isBreak(s) }

    /// Web `x.long`: off-site or All-Access co-located rows, listed in their own section.
    func isLong(_ s: Session) -> Bool { rules.isLong(s) }

    /// A schedule.json all-day placeholder that a co-located event card replaces: never listed.
    func isHidden(_ s: Session) -> Bool { rules.isHidden(s) }

    /// The co-located events whose cards list `s`: a talk's event, or every event a break serves.
    func coloEventsOf(_ s: Session) -> [ColoEvent] { rules.coloEventsOf(s) }

    /// The one co-located event `s` belongs to (its talks, its own breaks), or nil.
    func coloEventOf(_ s: Session) -> ColoEvent? { rules.coloEventOf(s) }

    /// Shown inside co-located event cards rather than in the half-hour blocks.
    func inColoCard(_ s: Session) -> Bool { rules.inColoCard(s) }

    /// `s` is on a co-located card at `now`: one of its events hasn't ended yet. An unfinished
    /// talk always is (its event ends with its last talk); a break may not be (CiliumCon's lunch
    /// starts as CiliumCon ends), and then it's an ordinary break row in the blocks.
    func onColoCard(_ s: Session, _ now: Date) -> Bool { coloEventsOf(s).contains { now.isBefore($0.end) } }

    /// Room display name (web `rname`); the code itself for an unknown room.
    func roomName(_ code: String) -> String { rules.roomName(code) }

    /// Building line, e.g. "Salt Palace L2" (web `bldg`); "" for HL, OFF and unknown rooms.
    func building(_ code: String) -> String { repo.room(code)?.buildingLabel ?? "" }

    /// Category label as the web shows it (`CATS`): "Keynote", "Talk", …; "" for breaks.
    func categoryLabel(_ key: String) -> String { rules.categoryLabel(key) }

    /// My session under the current "I'm speaking as" (`me` = nil: None).
    func isMine(_ s: Session, _ me: String?) -> Bool { scheduleIsMine(s, me) }

    /// Not mine, and an Anthropic colleague other than `me` speaks (web `x.ant`).
    func hasAnthropic(_ s: Session, _ me: String?) -> Bool { scheduleHasAnthropic(s, me, repo.anthropicSpeakers) }

    /// The key of the group a session is shown in, or nil.
    func groupKeyOf(_ sessionId: String) -> String? { groupOfSession[sessionId] }

    /// Sessions of one day in file order.
    func sessionsOn(_ dayKey: String) -> [Session] { byDay[dayKey] ?? [] }

    // MARK: - day tabs

    /// Web `render` day tabs: visible days, "Today" label, "You" badge while I still have a talk that day.
    func dayTabs(_ now: Date, _ me: String?) -> [DayTab] {
        let today = ScheduleLogic.todayKey(days, now)
        return ScheduleLogic.visibleDays(days, now).map { d in
            DayTab(
                key: d.key,
                title: d.label,
                label: d.key == today ? "Today" : d.dow,
                number: d.num,
                hasMine: me != nil && sessionsOn(d.key).contains { isMine($0, me) && !ScheduleLogic.isFinished($0, now) }
            )
        }
    }

    // MARK: - day view

    /// Web `renderDay(k)`: what's left of one day, in half-hour blocks. Nil for an unknown day key.
    func dayView(_ dayKey: String, _ now: Date, _ me: String?) -> DayView? {
        guard let day = repo.day(dayKey) else { return nil }
        let today = day.date == now.localDate
        let items = sessionsOn(dayKey).filter { !ScheduleLogic.isFinished($0, now) && !isHidden($0) }
        let longs = items.filter { isLong($0) }.stableSorted(on: { $0.start })

        var blocks: [Block] = []
        // The day's own break rows. A co-located break that is the same break (start, end and
        // title) shows once, as that quiet row.
        var breakKeys = Set(items.filter { isBreak($0) && !$0.isColocated }.map { BreakKey.of($0) })
        for s in items {
            // Co-located talks and their events' breaks live in the event cards (coloCards), not in
            // the blocks; a break whose events have all ended (their cards are gone) is a block row.
            if isLong(s) || group(s) != nil || onColoCard(s, now) { continue }
            if s.isColocated && isBreak(s) && !breakKeys.insert(BreakKey.of(s)).inserted { continue }
            blocks.append(.session(SessionBlock(s, category(s), mine: isMine(s, me), anthropic: hasAnthropic(s, me))))
        }
        for g in groups.values {
            if g.day != dayKey { continue }
            let kids = g.kids.filter { !ScheduleLogic.isFinished($0, now) }
            if !kids.isEmpty { blocks.append(.group(GroupBlock(g, kids))) }
        }
        // Within a start time: my own talks first, then the normal order (category, then room).
        let roomOrder = self.roomOrder
        let order = KComparator<Block>.by { $0.start }
            .thenByDescending { $0.mine }
            .thenBy { ScheduleIndex.CATEGORY_ORDER[$0.category] ?? ScheduleIndex.CATEGORY_ORDER.count }
            .thenBy { roomOrder[$0.room] ?? -1 }
        let sorted = blocks.stableSorted(with: order)

        let slots = Slot.build(dayKey, sorted)

        var status: DayStatus? = nil
        var upNextBefore = -1
        if today {
            let core = items.filter { !isLong($0) && !isBreak($0) }
            let onNow = core.count { ScheduleLogic.isLive($0, now) }
            let next = core.filter { $0.start.isAfter(now) }.min { $0.start < $1.start }
            status = DayStatus(onNow, next?.start)
            let nowMin = TimeFormat.minuteOfDay(now)
            if let i = slots.firstIndex(where: { $0.key > nowMin }), i > 0 { upNextBefore = i }
        }

        // With co-located cards (the data has events this day), Monday's CNCF co-located events are
        // those cards and what's left of the web's "Co-located + off-site" section is the
        // sponsor-hosted (separate registration) list, after the blocks. Without them (colocated.json
        // missing or unreadable) the All-Access placeholders are back, so is the web's section.
        let coloDay = coloDays.contains(dayKey)
        let longsTitle: String
        if coloDay {
            longsTitle = "Sponsor-hosted · off-site"
        } else if dayKey == "mon" {
            longsTitle = "Co-located + off-site"
        } else {
            longsTitle = "Off-site"
        }
        return DayView(
            day: day,
            isToday: today,
            status: status,
            longsTitle: longsTitle,
            longs: longs.map { SessionBlock($0, category($0), mine: isMine($0, me), anthropic: hasAnthropic($0, me)) },
            longsFirst: !coloDay && dayKey == "mon",
            slots: slots,
            upNextBefore: upNextBefore,
            colo: coloCards(dayKey, now, me)
        )
    }

    // MARK: - co-located events

    /// The day's co-located event cards, alphabetical, each until its event ends. Empty on days
    /// without co-located events.
    func coloCards(_ dayKey: String, _ now: Date, _ me: String?) -> [ColoCard] {
        repo.coloEvents
            .filter { $0.day == dayKey && now.isBefore($0.end) }
            .stableSorted(with: .by(.caseInsensitiveOrder) { $0.name })
            .map { coloCard($0, now, me) }
    }

    /// One event's card at `now`.
    func coloCard(_ e: ColoEvent, _ now: Date, _ me: String?) -> ColoCard {
        let left = (coloAgendas[e.key] ?? []).filter { !ScheduleLogic.isFinished($0, now) }
        let agenda = left.map { s -> ColoItem in
            let brk = isBreak(s)
            let mine = isMine(s, me)
            return ColoItem(
                session: s,
                isBreak: brk,
                live: ScheduleLogic.isLive(s, now),
                mine: mine,
                anthropic: !mine && hasAnthropic(s, me),
                room: brk || s.room != e.mainRoom ? s.room : nil
            )
        }
        let talks = agenda.filter { !$0.isBreak }
        return ColoCard(
            event: e,
            hours: ColoText.hours(e),
            lines: ColoLines.of(e, agenda, now),
            agenda: agenda,
            mine: talks.contains { $0.mine },
            anthropic: talks.contains { $0.anthropic },
            live: talks.contains { $0.live }
        )
    }

    // MARK: - my talks banner

    /// Web `renderMine`: my talks still to come on `dayKey`, or nil (no talks that day, me = None,
    /// or a search is showing).
    func banner(_ dayKey: String?, _ now: Date, _ me: String?, searching: Bool = false) -> MineBanner? {
        if searching { return nil }
        guard let me, let dayKey else { return nil }
        let xs = sessionsOn(dayKey)
            .filter { isMine($0, me) && !ScheduleLogic.isFinished($0, now) }
            .stableSorted(on: { $0.start })
        guard let nx = xs.first else { return nil }
        let todayDate = now.localDate
        let nxDay = repo.dayOf(nx)
        let nxIsToday = nxDay?.date == todayDate

        let countdown: String
        let soon: Bool
        if ScheduleLogic.isLive(nx, now) {
            countdown = "On now"
            soon = true
        } else if nxIsToday {
            let until = TimeFormat.minutesBetween(now, nx.start)
            countdown = ScheduleLogic.countdownLabel(until)
            soon = until <= 45
        } else if let nxDay, nxDay.date == todayDate.plusDays(1) {
            countdown = "Tomorrow"
            soon = false
        } else {
            countdown = nxDay?.label.substringBefore(",") ?? ""
            soon = false
        }

        func dayPrefix(_ s: Session) -> String {
            guard let d = repo.dayOf(s) else { return "" }
            return d.date == todayDate ? "" : d.dow + " "
        }

        var where_ = soon ? "Head to " : ""
        where_ += roomName(nx.room)
        let b = building(nx.room)
        if !b.isEmpty { where_ += " · " + b }
        if category(nx) == "key" { where_ += " · Keynote" }

        var later: [LaterTalk] = []
        for i in xs.indices.dropFirst() {
            let x = xs[i]
            let prefix = x.day != xs[i - 1].day ? dayPrefix(x) : ""
            later.append(LaterTalk(session: x, time: prefix + TimeFormat.hma(x.start), roomName: roomName(x.room)))
        }
        return MineBanner(
            next: nx,
            countdown: countdown,
            soon: soon,
            live: ScheduleLogic.isLive(nx, now),
            nextTime: dayPrefix(nx) + TimeFormat.hma(nx.start),
            nextWhere: where_,
            later: later
        )
    }

    // MARK: - search

    /// Builds the search text now (call off the main thread) so the first keystroke is cheap.
    func prewarmSearch() {
        _ = haystack.value.count
    }

    /// True when `s` matches every search term (title, speakers, room name, note, category label, co-located event).
    func matches(_ s: Session, _ terms: [String], _ me: String?) -> Bool {
        if terms.isEmpty { return false }
        guard let base = haystack.value[s.id] else { return false }
        if TextMatch.matchesAll(base, terms) { return true }
        // Web: x.hay gets " anthropic" for the speaker's own sessions and sessions with Anthropic colleagues.
        if !(isMine(s, me) || hasAnthropic(s, me)) { return false }
        return TextMatch.matchesAll(base + " anthropic", terms)
    }

    /// Web `renderSearch`: unfinished, non-break sessions of the whole week matching every term, by day.
    func search(_ query: String, _ now: Date, _ me: String?) -> SearchResults {
        let terms = TextMatch.terms(query)
        if terms.isEmpty { return SearchResults(0, []) }
        let hits = repo.sessions.filter {
            !isBreak($0) && !isHidden($0) && !ScheduleLogic.isFinished($0, now) && matches($0, terms, me)
        }
        var byDayHits: [String: [Session]] = [:]
        for s in hits { byDayHits[s.day, default: []].append(s) }
        let sections: [SearchDay] = days.compactMap { d in
            guard let xs = byDayHits[d.key]?.stableSorted(on: { $0.start }) else { return nil }
            return SearchDay(d, xs.map { SessionBlock($0, category($0), mine: isMine($0, me), anthropic: hasAnthropic($0, me)) })
        }
        return SearchResults(hits.count, sections)
    }

    // MARK: - cards

    /// Live state for one card (web `card`: pills, live border, progress bar).
    func cardStatus(_ s: Session, _ now: Date) -> CardStatus {
        if !ScheduleLogic.isLive(s, now) { return CardStatus.NotLive }
        let long = isLong(s)
        return CardStatus(
            live: true,
            liveLabel: ScheduleLogic.liveLabel(s, now, long: long),
            progress: long ? nil : ScheduleLogic.liveProgress(s, now)
        )
    }

    // MARK: - companion

    /// Web `ORD`: block sort order by category.
    static let CATEGORY_ORDER: OrderedMap<String, Int> = [
        "key": 0, "talk": 1, "mnt": 2, "hands": 3, "com": 4, "show": 5, "soc": 6, "colo": 7, "log": 8,
    ]

    private static let cached = Locked<ScheduleIndex?>(nil)

    /// The index for `repo`, built once per Repository (it survives view recreation). Only the
    /// latest is kept, so a live data update doesn't keep the old data set alive.
    static func of(_ repo: Repository) -> ScheduleIndex {
        cached.withLock { c in
            if let c, c.repo === repo { return c }
            let idx = ScheduleIndex(repo)
            c = idx
            return idx
        }
    }
}

/// The per-session rules of ``ScheduleIndex`` (the Kotlin class's `category`, `group`,
/// `isBreak`, …), split out so the index's stored properties and its lazy search text can be
/// built from them in `init`.
private struct ScheduleIndexRules: Sendable {
    let repo: Repository
    let categoryFix: [String: String]
    /// Session id -> corrected group (nil value: no group).
    let groupFix: [String: SessionGroup?]

    func category(_ s: Session) -> String { categoryFix[s.id] ?? s.category }

    func group(_ s: Session) -> SessionGroup? {
        if let fixed = groupFix[s.id] { return fixed }
        return s.group
    }

    func isBreak(_ s: Session) -> Bool { category(s) == "log" }

    func isLong(_ s: Session) -> Bool { group(s) == nil && (s.room == "OFF" || s.note == "All-Access pass") }

    func isHidden(_ s: Session) -> Bool { repo.supersededIds.contains(s.id) }

    func coloEventsOf(_ s: Session) -> [ColoEvent] {
        if !s.isColocated { return [] }
        let keys: [String] = s.coloEvents.isEmpty ? (s.coloEvent.map { [$0] } ?? []) : s.coloEvents
        return keys.compactMap { repo.coloEvent($0) }
    }

    func coloEventOf(_ s: Session) -> ColoEvent? {
        if !s.isColocated { return nil }
        if let key = s.coloEvent, let e = repo.coloEvent(key) { return e }
        let all = coloEventsOf(s)
        return all.count == 1 ? all[0] : nil
    }

    func inColoCard(_ s: Session) -> Bool { !coloEventsOf(s).isEmpty }

    func roomName(_ code: String) -> String { repo.room(code)?.name ?? code }

    func categoryLabel(_ key: String) -> String { key == "log" ? "" : (repo.category(key)?.label ?? "") }
}

/// The free ``isMine(_:_:)`` under another name (the index has a method of the same name).
private func scheduleIsMine(_ s: Session, _ me: String?) -> Bool { isMine(s, me) }

/// The free ``hasAnthropic(_:_:_:)`` under another name.
private func scheduleHasAnthropic(_ s: Session, _ me: String?, _ speakers: Set<String>) -> Bool {
    hasAnthropic(s, me, speakers)
}

// MARK: - Types

/// A group of back-to-back sessions in one room (web `SERIES` entry).
struct GroupInfo: Sendable, Hashable {
    let key: String
    let title: String
    let day: String
    let room: String
    let category: String
    /// All kids, sorted by start.
    let kids: [Session]
    /// Latest effective end of any kid.
    let end: Date
}

/// One entry in a half-hour block: a session card / break row, or a group card (Kotlin
/// `sealed interface Block` with `SessionBlock` and `GroupBlock`).
enum Block: Sendable, Hashable {
    case session(SessionBlock)
    case group(GroupBlock)

    var start: Date {
        switch self {
        case .session(let b): return b.start
        case .group(let b): return b.start
        }
    }

    var category: String {
        switch self {
        case .session(let b): return b.category
        case .group(let b): return b.category
        }
    }

    var room: String {
        switch self {
        case .session(let b): return b.room
        case .group(let b): return b.room
        }
    }

    var mine: Bool {
        switch self {
        case .session(let b): return b.mine
        case .group(let b): return b.mine
        }
    }

    var anthropic: Bool {
        switch self {
        case .session(let b): return b.anthropic
        case .group(let b): return b.anthropic
        }
    }

    /// Stable list identity ("s-<id>" / "g-<key>"), Kotlin's LazyColumn key.
    var key: String {
        switch self {
        case .session(let b): return b.key
        case .group(let b): return b.key
        }
    }

    /// Kotlin `b as? SessionBlock`.
    var sessionBlock: SessionBlock? {
        if case .session(let b) = self { return b }
        return nil
    }

    /// Kotlin `b as? GroupBlock`.
    var groupBlock: GroupBlock? {
        if case .group(let b) = self { return b }
        return nil
    }

    /// The sessions the block shows: its session, or the group's (unfinished) kids.
    var sessions: [Session] {
        switch self {
        case .session(let b): return [b.session]
        case .group(let b): return b.kids
        }
    }
}

struct SessionBlock: Sendable, Hashable {
    let session: Session
    let category: String
    let mine: Bool
    let anthropic: Bool

    var start: Date { session.start }
    var room: String { session.room }
    var key: String { "s-" + session.id }
}

extension SessionBlock {
    /// Kotlin `SessionBlock(s, category, mine = …, anthropic = …)`.
    init(_ session: Session, _ category: String, mine: Bool, anthropic: Bool) {
        self.init(session: session, category: category, mine: mine, anthropic: anthropic)
    }
}

struct GroupBlock: Sendable, Hashable {
    let group: GroupInfo
    /// Kids not finished yet, sorted by start (never empty).
    let kids: [Session]

    var start: Date { kids[0].start }
    var category: String { group.category }
    var room: String { group.room }
    var mine: Bool { false }
    var anthropic: Bool { false }
    var key: String { "g-" + group.key }
}

extension GroupBlock {
    /// Kotlin `GroupBlock(g, kids)`.
    init(_ group: GroupInfo, _ kids: [Session]) {
        self.init(group: group, kids: kids)
    }
}

/// A half-hour block labelled with its earliest real start ("10:15 AM", not "10:00").
struct Slot: Sendable, Hashable {
    let dayKey: String
    let key: Int
    let start: Date
    let blocks: [Block]

    var label: String { TimeFormat.hma(start) }
}

extension Slot {
    /// Kotlin `Slot(dayKey, key, start, blocks)`.
    init(_ dayKey: String, _ key: Int, _ start: Date, _ blocks: [Block]) {
        self.init(dayKey: dayKey, key: key, start: start, blocks: blocks)
    }

    /// Cuts blocks already sorted by start into half-hour slots (``ScheduleLogic/slotKey(_:)``),
    /// each starting at its first block (the loop in Kotlin `dayView` and GoingLogic `filterDay`).
    static func build(_ dayKey: String, _ sorted: [Block]) -> [Slot] {
        var slots: [Slot] = []
        var cur: [Block] = []
        var curKey = Int.min
        var curStart: Date? = nil
        for b in sorted {
            let k = ScheduleLogic.slotKey(TimeFormat.minuteOfDay(b.start))
            if curStart == nil || k != curKey {
                if let st = curStart { slots.append(Slot(dayKey, curKey, st, cur)) }
                cur = []
                curKey = k
                curStart = b.start
            }
            cur.append(b)
        }
        if let st = curStart { slots.append(Slot(dayKey, curKey, st, cur)) }
        return slots
    }
}

/// Today's status line: "3 on now · Next at 10:15 AM".
struct DayStatus: Sendable, Hashable {
    let onNow: Int
    let nextStart: Date?
}

extension DayStatus {
    /// Kotlin `DayStatus(onNow, nextStart)`.
    init(_ onNow: Int, _ nextStart: Date?) {
        self.init(onNow: onNow, nextStart: nextStart)
    }
}

struct DayView: Sendable, Hashable {
    let day: Day
    let isToday: Bool
    /// Only for today.
    let status: DayStatus?
    /// "Sponsor-hosted · off-site" (Monday, with its co-located cards), "Co-located + off-site"
    /// (Monday without co-located data, as on the web) or "Off-site".
    let longsTitle: String
    let longs: [SessionBlock]
    /// List ``longs`` before the blocks: only Monday without co-located cards (the web's order).
    let longsFirst: Bool
    let slots: [Slot]
    /// Index into ``slots`` of the block the "Up next" line goes before, or -1.
    let upNextBefore: Int
    /// The "Co-located events" cards (Monday), shown above the blocks; empty on other days.
    let colo: [ColoCard]

    init(
        day: Day,
        isToday: Bool,
        status: DayStatus?,
        longsTitle: String,
        longs: [SessionBlock],
        longsFirst: Bool,
        slots: [Slot],
        upNextBefore: Int,
        colo: [ColoCard] = []
    ) {
        self.day = day
        self.isToday = isToday
        self.status = status
        self.longsTitle = longsTitle
        self.longs = longs
        self.longsFirst = longsFirst
        self.slots = slots
        self.upNextBefore = upNextBefore
        self.colo = colo
    }

    /// "That’s a wrap for today".
    var isEmpty: Bool { slots.isEmpty && longs.isEmpty && colo.isEmpty }
}

/// Identity of a break for de-duplication: the same start, end and title (emoji and case aside).
/// The title compares by UTF-16 units, like Kotlin's data-class equality.
struct BreakKey: Sendable, Hashable {
    let start: Date
    let end: Date?
    let title: String

    static func of(_ s: Session) -> BreakKey {
        BreakKey(start: s.start, end: s.end, title: TextMatch.normalize(ScheduleLogic.breakTitle(s.title)).kotlinTrim())
    }

    static func == (a: BreakKey, b: BreakKey) -> Bool {
        a.start == b.start && a.end == b.end && kotlinEquals(a.title, b.title)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
        for u in title.utf16 { hasher.combine(u) }
    }
}

struct DayTab: Sendable, Hashable {
    let key: String
    /// "Wednesday, Nov 11" (for accessibility).
    let title: String
    /// "Today" or "Wed".
    let label: String
    let number: Int
    /// I still have a talk to come that day: the pink "YOU" badge.
    let hasMine: Bool
}

struct LaterTalk: Sendable, Hashable {
    let session: Session
    let time: String
    let roomName: String
}

/// The pinned "You’re speaking" banner.
struct MineBanner: Sendable, Hashable {
    let next: Session
    /// "On now", "In 25 min", "In 1h 45m", "Tomorrow", "Wednesday".
    let countdown: String
    /// Live or within 45 min: pulse the countdown and say "Head to …".
    let soon: Bool
    let live: Bool
    /// "9:45 AM", or "Wed 9:45 AM" when not today.
    let nextTime: String
    /// "Head to Hall DE · Salt Palace L1 · Keynote".
    let nextWhere: String
    let later: [LaterTalk]
}

struct SearchDay: Sendable, Hashable {
    let day: Day
    let sessions: [SessionBlock]
}

extension SearchDay {
    /// Kotlin `SearchDay(day, sessions)`.
    init(_ day: Day, _ sessions: [SessionBlock]) {
        self.init(day: day, sessions: sessions)
    }
}

struct SearchResults: Sendable, Hashable {
    let count: Int
    let days: [SearchDay]

    /// "1 match", "12 matches".
    var heading: String { "\(count) \(count == 1 ? "match" : "matches")" }
}

extension SearchResults {
    /// Kotlin `SearchResults(count, days)`.
    init(_ count: Int, _ days: [SearchDay]) {
        self.init(count: count, days: days)
    }
}

struct CardStatus: Sendable, Hashable {
    let live: Bool
    let liveLabel: String?
    let progress: Float?

    static let NotLive = CardStatus(live: false, liveLabel: nil, progress: nil)
}
