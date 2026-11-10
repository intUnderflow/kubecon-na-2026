@testable import KCNA26Core

/// Kotlin `is Row.X` / `as Row.X` for the schedule-row tests (ScheduleRowsTests, GoingRowsTests).
extension ScheduleRow {
    /// Kotlin `row::class`: the case name.
    var kind: String {
        switch self {
        case .search: return "Search"
        case .banner: return "Banner"
        case .dayHead: return "DayHead"
        case .section: return "Section"
        case .slotHead: return "SlotHead"
        case .upNext: return "UpNext"
        case .item: return "Item"
        case .searchHead: return "SearchHead"
        case .empty: return "Empty"
        case .footer: return "Footer"
        case .colo: return "Colo"
        case .coloAgenda: return "ColoAgenda"
        case .goingNext: return "GoingNext"
        }
    }

    var isBanner: Bool { kind == "Banner" }
    var isDayHead: Bool { kind == "DayHead" }
    var isSection: Bool { kind == "Section" }
    var isSlotHead: Bool { kind == "SlotHead" }
    var isItem: Bool { kind == "Item" }
    var isEmptyRow: Bool { kind == "Empty" }
    var isColo: Bool { kind == "Colo" }
    var isColoAgenda: Bool { kind == "ColoAgenda" }
    var isGoingNext: Bool { kind == "GoingNext" }

    /// `(row as? Row.Section)?.title`.
    var sectionTitle: String? {
        if case .section(_, let title) = self { return title }
        return nil
    }

    /// `(row as? Row.SlotHead)?.slot`.
    var slot: Slot? {
        if case .slotHead(let s) = self { return s }
        return nil
    }

    /// `(row as? Row.Item)?.block`.
    var itemBlock: Block? {
        if case .item(let b, _) = self { return b }
        return nil
    }

    /// `(row as? Row.SearchHead)?.heading`.
    var searchHeading: String? {
        if case .searchHead(let h) = self { return h }
        return nil
    }

    /// `row as? Row.Empty`.
    var emptyState: ScheduleRow.Empty? {
        if case .empty(let e) = self { return e }
        return nil
    }

    /// `(row as? Row.Colo)?.cards`.
    var coloCards: [ColoCard]? {
        if case .colo(let cards) = self { return cards }
        return nil
    }

    /// `row as? Row.ColoAgenda`: its card and `attached`.
    var agenda: (card: ColoCard, attached: Bool)? {
        if case .coloAgenda(let card, let attached) = self { return (card, attached) }
        return nil
    }

    /// `(row as? Row.GoingNext)?.next`.
    var goingNextValue: GoingNext? {
        if case .goingNext(let n) = self { return n }
        return nil
    }
}
