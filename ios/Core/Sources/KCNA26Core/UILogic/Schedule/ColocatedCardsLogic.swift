import Foundation

/// The pure parts of Kotlin ui/schedule/ColocatedCards.kt: the "Co-located events" section
/// (Monday), one compact card per CNCF-hosted co-located event with a glanceable live line;
/// tapping a card opens its agenda inline. With one card per row the card grows downwards (a
/// ``ScheduleRow/coloAgenda(_:attached:)`` drawn as the card's continuation); in a list column
/// wide enough for two (``ScheduleRows/coloColumns(_:)``) an open agenda is a full-width panel
/// right under its row, so neither tile moves. An agenda can be hidden from its foot as well as
/// from its card.
enum ColocatedCardsLogic {
    /// The card's state description (VoiceOver value).
    static let AGENDA_SHOWN = "Agenda shown"
    static let AGENDA_HIDDEN = "Agenda hidden"
    /// The card's tap hint.
    static let SHOW_AGENDA = "Show agenda"
    /// The card's tap hint when open, and the agenda's foot button.
    static let HIDE_AGENDA = "Hide agenda"
    static let EVENT_PAGE = "Event page ↗"
    static let OFFICIAL_LISTING = "Official listing ↗"

    static func agendaState(_ open: Bool) -> String { open ? AGENDA_SHOWN : AGENDA_HIDDEN }
    static func toggleHint(_ open: Bool) -> String { open ? HIDE_AGENDA : SHOW_AGENDA }

    /// The detached agenda's close button and the foot button's accessibility label.
    static func hideAgendaLabel(_ eventName: String) -> String { "Hide the \(eventName) agenda" }

    // MARK: - ColoCardRow

    /// One card of a ``ScheduleRow/colo(_:)`` row (Kotlin `ColoCardRow` -> `ColoEventCard` arguments).
    struct ColoTile: Sendable, Hashable {
        let card: ColoCard
        let open: Bool
        /// Two to a row (a narrower tile: smaller name, one more line for the live lines).
        let tile: Bool
        /// One per row and open: square bottom corners and no bottom border (the agenda continues it).
        let attachedBelow: Bool
        /// An open tile gets a 2 pt ring in the co-located colour.
        var ring: PaletteRole? { open && tile ? .category("colo") : nil }
        var border: PaletteRole { ColocatedCardsLogic.border(card) }
        /// Bottom padding under the row: none under a card whose agenda is attached.
        var bottomGap: Double { attachedBelow ? 0 : Dimens.cardGap }
    }

    /// The tiles of one row and how many empty slots pad it (`columns - cards.count`, so a lone
    /// last tile keeps the tile width).
    static func cardRow(_ cards: [ColoCard], _ columns: Int, _ open: Set<String>) -> (tiles: [ColoTile], spacers: Int) {
        if columns <= 1 {
            guard let card = cards.first else { return ([], 0) }
            let isOpen = open.contains(card.key)
            return ([ColoTile(card: card, open: isOpen, tile: false, attachedBelow: isOpen)], 0)
        }
        let tiles = cards.map { ColoTile(card: $0, open: open.contains($0.key), tile: true, attachedBelow: false) }
        return (tiles, max(0, columns - cards.count))
    }

    /// Live border while a talk is on, like the session cards.
    static func border(_ card: ColoCard) -> PaletteRole { card.live ? .liveBorder : .line }

    // MARK: - ColoEventCard

    /// The main room line: **room** (ink, bold), then two spaces and the building with
    /// no-break spaces, so the line breaks at most between the room and its building, never
    /// inside "Salt Palace L1". The line's own colour is muted.
    static func roomLine(_ index: ScheduleIndex, _ e: ColoEvent) -> [TextRun] {
        var runs = [TextRun(index.roomName(e.mainRoom), bold: true, role: .ink)]
        let b = index.building(e.mainRoom)
        if !b.isEmpty {
            runs.append(TextRun("  " + b.kotlinReplace(" ", "\u{00A0}")))
        }
        return runs
    }

    /// "Half day ·", "1:20–5:30 PM": each piece one unbreakable item of a flow row (it may
    /// wrap after "Half day ·" on a narrow tile, never inside the times). Muted, then the "You"
    /// / "Anthropic" pills (`card.mine`, `card.anthropic`).
    static func hoursPieces(_ e: ColoEvent) -> [String] {
        let parts = ColoText.hoursParts(e)
        return parts.enumerated().map { i, part in i < parts.count - 1 ? "\(part) ·" : part }
    }

    /// At most two entries ("Now" and "Next", or one of them, or "Starts"). The lead line may
    /// take two text lines; a "Next" under it takes one. A narrower tile gets one more each.
    static func lineMaxLines(_ i: Int, _ line: ColoLine, tile: Bool) -> Int {
        var isNext = false
        if case .next = line { isNext = true }
        let max = i > 0 && isNext ? 1 : 2
        return tile ? max + 1 : max
    }

    /// Kotlin `ColoLineText`: "NOW · 12 MIN LEFT" (pink, bold) / "NEXT 10:40" / "STARTS 9:00 AM"
    /// (muted, semibold) in the Barlow label face, then " · " and the talk's title in bold (pink
    /// for Now, else ink). The line's own colour: pink for Now, else muted. Run 0 is the label
    /// (Barlow 14.5, 0.05 em, tabular); `bold` there means Bold vs SemiBold.
    static func lineText(_ line: ColoLine, _ index: ScheduleIndex) -> [TextRun] {
        var isNow = false
        if case .now = line { isNow = true }
        var runs = [TextRun(ColoText.label(line, index.roomName).caps(), bold: isNow, role: isNow ? .you : .muted)]
        if let s = line.session {
            runs.append(TextRun(" · "))
            runs.append(TextRun(s.title, bold: true, role: isNow ? .you : .ink))
        }
        return runs
    }

    /// The colour of a live line (Kotlin `if (now) c.you else c.muted`).
    static func lineColor(_ line: ColoLine) -> PaletteRole {
        if case .now = line { return .you }
        return .muted
    }

    // MARK: - ColoAgendaCard

    /// One agenda row: a talk (a ``ScheduleCardsLogic/KidRowModel``, with the room named when
    /// it's outside the event's main room) or a quiet break (``breakText``).
    struct AgendaRow: Sendable, Hashable {
        let item: ColoItem
        let kid: ScheduleCardsLogic.KidRowModel
        /// For a break: **Coffee Break** · until 10:40 · Meeting room foyers (the time column has
        /// the start). Nil for a talk.
        let breakText: [TextRun]?
    }

    /// The agenda's rows (Kotlin `ColoAgendaCard`): every item, in order.
    static func agendaRows(
        _ card: ColoCard,
        _ index: ScheduleIndex,
        selectedId: String?,
        revealId: String?,
        goingIds: Set<String> = [],
        clashIds: Set<String> = []
    ) -> [AgendaRow] {
        let items = card.agenda
        return items.enumerated().map { i, item in
            let s = item.session
            let kid = ScheduleCardsLogic.KidRowModel(
                session: s,
                live: item.live,
                mine: item.mine,
                anthropic: item.anthropic,
                selected: s.id == selectedId,
                reveal: s.id == revealId,
                divider: ScheduleCardsLogic.kidRowDivider(mine: item.mine, i, items.count),
                going: goingIds.contains(s.id),
                clash: clashIds.contains(s.id),
                place: item.room.map { index.roomName($0) }
            )
            return AgendaRow(item: item, kid: kid, breakText: item.isBreak ? breakText(s, item.room, index) : nil)
        }
    }

    /// A break row's text: its title in bold, then " · " and each further part
    /// (``ColoText/breakParts(_:_:_:)``: "until 10:40", the place). Muted, 13.5 pt.
    static func breakText(_ s: Session, _ room: String?, _ index: ScheduleIndex) -> [TextRun] {
        let parts = ColoText.breakParts(s, room, index.roomName)
        return parts.enumerated().map { i, part in i == 0 ? TextRun(part, bold: true) : TextRun(" · \(part)") }
    }

    /// The time column of a break row: pink while live, else muted.
    static func breakTimeColor(_ item: ColoItem) -> PaletteRole { item.live ? .you : .muted }

    /// The event's info under its agenda (Kotlin `ColoFooter`): its pass note (bold, note amber)
    /// and links ("Event page ↗", "Official listing ↗"); nil when it has none of them.
    struct Footer: Sendable, Hashable {
        let passNote: String?
        /// (text, url), in order.
        let links: [Link]
    }

    struct Link: Sendable, Hashable {
        let text: String
        let url: String
    }

    static func footer(_ e: ColoEvent) -> Footer? {
        if e.passNote == nil && e.pageUrl == nil && e.infoUrl == nil { return nil }
        var links: [Link] = []
        if let url = e.pageUrl { links.append(Link(text: EVENT_PAGE, url: url)) }
        if let url = e.infoUrl { links.append(Link(text: OFFICIAL_LISTING, url: url)) }
        return Footer(passNote: e.passNote, links: links)
    }
}
