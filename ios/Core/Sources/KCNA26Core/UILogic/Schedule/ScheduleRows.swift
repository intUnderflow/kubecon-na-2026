import Foundation

/// The schedule list flattened into rows, in the web's order: search box, "You’re speaking"
/// banner, my starred "Up next" row (today), then either the search results or the day
/// (heading, the "Co-located events" cards on Monday, half-hour blocks with the "Up next"
/// line, off-site section), then the footer. Pure: unit-tested in ScheduleRowsTests.
///
/// Port of ui/schedule/ScheduleRows.kt `sealed interface Row`. Named `ScheduleRow` (not `Row`)
/// because Core and the app are one module and `Row` is too generic a name there. Kotlin
/// `Row.Search` -> `.search`, `Row.Item(block, inSearch)` -> `.item(block, inSearch:)`, …;
/// `Row.Empty(title, text)` -> `.empty(ScheduleRow.Empty(title, text))` (the Going filter
/// passes an ``Empty`` into ``ScheduleRows/build(_:_:_:_:_:goingNext:empty:)``).
///
/// SwiftUI: `ForEach(rows, id: \.key)`; ``sticky`` rows are the headers of the
/// `LazyVStack(pinnedViews: [.sectionHeaders])` sections (``slotHead(_:)`` and ``section(key:title:)``).
enum ScheduleRow: Sendable, Hashable {
    case search

    case banner(MineBanner)

    case dayHead(DayView)

    /// Sticky heading of a named section (co-located/off-site, or a day in search results).
    case section(key: String, title: String)

    /// Sticky half-hour block heading.
    case slotHead(Slot)

    case upNext

    /// A session card, a break row or a group card. `inSearch` cards come from search results.
    case item(Block, inSearch: Bool = false)

    case searchHead(String)

    /// The empty state ("That’s a wrap for today", "No matches", or the Going filter's note).
    case empty(Empty)

    case footer

    /// One row of co-located event cards: one card, or two side by side in a wide list column
    /// (``ScheduleRows/coloColumns(_:)``). Keyed by its leading card, so the key survives a
    /// re-chunk (a card leaving when its event ends, a different column count) and the list
    /// keeps its place. Never empty.
    case colo([ColoCard])

    /// An open event's agenda, right under its card's row. `attached`: one card per row, so the
    /// agenda continues that card; otherwise (two per row) it's a full-width panel of its own.
    case coloAgenda(ColoCard, attached: Bool)

    /// My next (or live) starred session today.
    case goingNext(GoingNext)

    /// Kotlin `Row.Empty(title, text)`.
    struct Empty: Sendable, Hashable {
        let title: String
        let text: String

        init(_ title: String, _ text: String) {
            self.title = title
            self.text = text
        }
    }

    /// Stable list key (Kotlin `LazyColumn` key; SwiftUI `ForEach` id).
    var key: String {
        switch self {
        case .search: return "search"
        case .banner: return "mine"
        case .dayHead: return "dayhead"
        case .section(let key, _): return key
        case .slotHead(let slot): return "slot-\(slot.dayKey)-\(slot.key)"
        case .upNext: return "upnext"
        case .item(let block, let inSearch): return (inSearch ? "q" : "") + block.key
        case .searchHead: return "qhead"
        case .empty: return "empty"
        case .footer: return "footer"
        case .colo(let cards): return "colo-" + cards[0].key
        case .coloAgenda(let card, _): return "colo-agenda-" + card.key
        case .goingNext: return "goingnext"
        }
    }

    /// Kotlin's LazyColumn content type (rows of one kind reuse compositions). Kept for parity:
    /// it tells break rows (8), group cards (7) and session cards (9) apart. `goingNext` is 20
    /// (clear of the co-located rows' 13 and 14).
    var type: Int {
        switch self {
        case .search: return 0
        case .banner: return 1
        case .dayHead: return 2
        case .section: return 4
        case .slotHead: return 5
        case .upNext: return 6
        case .item(let block, _):
            switch block {
            case .group: return 7
            case .session(let b): return b.category == "log" ? 8 : 9
            }
        case .searchHead: return 10
        case .empty: return 11
        case .footer: return 12
        case .colo: return 13
        case .coloAgenda: return 14
        case .goingNext: return 20
        }
    }

    /// Pinned while its section scrolls (``section(key:title:)`` and ``slotHead(_:)``).
    var sticky: Bool {
        switch self {
        case .section, .slotHead: return true
        default: return false
        }
    }
}

/// Builds and searches the schedule rows (Kotlin `object ScheduleRows`).
enum ScheduleRows {
    static let WRAP_TITLE = "That’s a wrap for today"
    static let WRAP_TEXT = "Pick the next day above."
    static let NO_MATCHES_TITLE = "No matches"
    static let NO_MATCHES_TEXT = "Try a project, a speaker, or a room like “255 A”."

    /// Narrowest list content (points; Kotlin dp) that gets co-located cards two to a row. Below
    /// it a tile is too narrow to read: the unfolded list–detail pane is ~400 dp (368 dp of
    /// content), narrower than the cover screen, so both get one card per row and the same rows.
    /// On iOS: an iPhone in portrait and the iPad list pane get one per row.
    static let COLO_TWO_UP_MIN_DP: Double = 560

    /// Co-located cards per row for a list column with `contentWidthDp` (points) of content.
    static func coloColumns(_ contentWidthDp: Double) -> Int { contentWidthDp >= COLO_TWO_UP_MIN_DP ? 2 : 1 }

    /// Builds the rows. `search` non-nil means search mode (the day, banner and `goingNext`
    /// are not shown). `empty` is the Going filter's note: it replaces the "That’s a wrap" /
    /// "No matches" state, or follows the list when that isn't empty (only my talks are left).
    /// Co-located cards go `coloColumns` to a row; `coloOpen` holds the event keys whose agenda is open.
    static func build(
        _ view: DayView?,
        _ banner: MineBanner?,
        _ search: SearchResults?,
        _ coloColumns: Int = 1,
        _ coloOpen: Set<String> = [],
        goingNext: GoingNext? = nil,
        empty: ScheduleRow.Empty? = nil
    ) -> [ScheduleRow] {
        var rows: [ScheduleRow] = []
        rows.reserveCapacity(160)
        rows.append(.search)
        if let search {
            rows.append(.searchHead(search.heading))
            for d in search.days {
                rows.append(.section(key: "q-\(d.day.key)", title: d.day.label))
                for b in d.sessions { rows.append(.item(.session(b), inSearch: true)) }
            }
            if search.count == 0 {
                rows.append(.empty(empty ?? ScheduleRow.Empty(NO_MATCHES_TITLE, NO_MATCHES_TEXT)))
            } else if let empty {
                rows.append(.empty(empty))
            }
        } else {
            if let banner { rows.append(.banner(banner)) }
            if let goingNext { rows.append(.goingNext(goingNext)) }
            if let view {
                rows.append(.dayHead(view))
                addColo(&rows, view, coloColumns.coerceAtLeast(1), coloOpen)
                if view.longsFirst { addLongs(&rows, view) }
                for (i, sl) in view.slots.enumerated() {
                    if i == view.upNextBefore { rows.append(.upNext) }
                    rows.append(.slotHead(sl))
                    for b in sl.blocks { rows.append(.item(b)) }
                }
                if !view.longsFirst { addLongs(&rows, view) }
                if view.isEmpty {
                    rows.append(.empty(empty ?? ScheduleRow.Empty(WRAP_TITLE, WRAP_TEXT)))
                } else if let empty {
                    rows.append(.empty(empty))
                }
            }
        }
        rows.append(.footer)
        return rows
    }

    private static func addColo(_ rows: inout [ScheduleRow], _ view: DayView, _ columns: Int, _ open: Set<String>) {
        if view.colo.isEmpty { return }
        rows.append(.section(key: "colo-\(view.day.key)", title: ColoText.SECTION))
        for cards in view.colo.chunked(columns) {
            rows.append(.colo(cards))
            for c in cards where open.contains(c.key) {
                rows.append(.coloAgenda(c, attached: columns == 1))
            }
        }
    }

    private static func addLongs(_ rows: inout [ScheduleRow], _ view: DayView) {
        if view.longs.isEmpty { return }
        rows.append(.section(key: "long-\(view.day.key)", title: view.longsTitle))
        for b in view.longs { rows.append(.item(.session(b))) }
    }

    /// Index of the row showing `sessionId` (its own card, the group card it's in, or the open
    /// agenda of its co-located event, else that event's card), or -1.
    static func indexOfSession(_ rows: [ScheduleRow], _ sessionId: String) -> Int {
        let i = rows.firstIndex { r in
            switch r {
            case .item(let block, _):
                switch block {
                case .session(let b): return b.session.id == sessionId
                case .group(let g): return g.kids.contains { $0.id == sessionId }
                }
            case .coloAgenda(let card, _):
                return card.holds(sessionId)
            default:
                return false
            }
        }
        if let i { return i }
        return rows.firstIndex { r in
            if case .colo(let cards) = r { return cards.contains { $0.holds(sessionId) } }
            return false
        } ?? -1
    }

    /// Where a banner jump to `sessionId` lands, or -1 to keep waiting for the rows. `agenda`:
    /// the co-located event whose card the tap has just opened. Its talk is only revealed from the
    /// open agenda, and the jump's first look is at the rows from before the tap (card still
    /// collapsed), so it waits for that event's ``ScheduleRow/coloAgenda(_:attached:)`` rather
    /// than settling on the card head.
    static func jumpIndex(_ rows: [ScheduleRow], _ sessionId: String, _ agenda: String?) -> Int {
        guard let agenda else { return indexOfSession(rows, sessionId) }
        return rows.firstIndex { r in
            if case .coloAgenda(let card, _) = r { return card.key == agenda && card.holds(sessionId) }
            return false
        } ?? -1
    }

    /// After a jump lands on `row`, `sessionId` is inside it and must be scrolled into view
    /// itself: a group card's kid, an open agenda's row, or (the timeout fallback) the head of a
    /// card whose agenda is `open`, laid out right under it.
    static func revealsAfterJump(_ row: ScheduleRow?, _ sessionId: String, _ open: Set<String>) -> Bool {
        switch row {
        case .item(let block, _)?:
            return block.groupBlock?.kids.contains { $0.id == sessionId } == true
        case .coloAgenda(let card, _)?:
            return card.holds(sessionId)
        case .colo(let cards)?:
            return cards.contains { open.contains($0.key) && $0.holds(sessionId) }
        default:
            return false
        }
    }

    /// Index of the ``ScheduleRow/colo(_:)`` row showing event `key`'s card, or -1.
    static func indexOfColoCard(_ rows: [ScheduleRow], _ key: String) -> Int {
        rows.firstIndex { r in
            if case .colo(let cards) = r { return cards.contains { $0.key == key } }
            return false
        } ?? -1
    }
}
