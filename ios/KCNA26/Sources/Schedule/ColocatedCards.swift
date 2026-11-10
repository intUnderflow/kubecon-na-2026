import SwiftUI

// Kotlin ui/schedule/ColocatedCards.kt: the "Co-located events" section (Monday). One compact
// card per CNCF-hosted co-located event, in the look of the web's `.card` (category stripe in the
// colo colour, Barlow uppercase name), with a glanceable live line. Tapping a card opens its
// agenda inline: with one card per row the card grows downwards (a `.coloAgenda` row drawn as the
// card's continuation: `cardSurface(edges:)`); in a list column wide enough for two to a row an
// open agenda is a full-width panel right under its row, so neither tile moves. An agenda can be
// hidden from its foot as well as from its card. Texts and rules: Core's `ColocatedCardsLogic`.

// MARK: - ColoCardRow

/// One row of event cards (Kotlin `ColoCardRow`): one card, or `columns` tiles side by side of
/// equal height (a lone last tile keeps the tile width).
struct ColoCardRow: View {
    let cards: [ColoCard]
    let columns: Int
    let open: Set<String>
    let index: ScheduleIndex
    let onToggle: (String) -> Void

    init(cards: [ColoCard], columns: Int, open: Set<String>, index: ScheduleIndex, onToggle: @escaping (String) -> Void) {
        self.cards = cards
        self.columns = columns
        self.open = open
        self.index = index
        self.onToggle = onToggle
    }

    var body: some View {
        let row = ColocatedCardsLogic.cardRow(cards, columns, open)
        if columns <= 1 {
            if let tile = row.tiles.first {
                ColoEventCard(tile: tile, index: index, onToggle: onToggle)
                    .padding(.bottom, CGFloat(tile.bottomGap))
            }
        } else {
            HStack(alignment: .top, spacing: CGFloat(Dimens.cardGap)) {
                ForEach(row.tiles, id: \.card.key) { tile in
                    ColoEventCard(tile: tile, index: index, onToggle: onToggle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(0..<row.spacers, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            // Kotlin height(IntrinsicSize.Min) + fillMaxHeight: tiles of one row share a height.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, CGFloat(Dimens.cardGap))
        }
    }
}

// MARK: - ColoEventCard

/// The collapsed card (Kotlin `ColoEventCard`): event name, main room · building, hours (+ "You"
/// / "Anthropic" markers) and the live line ("Starts …", "Now …", "Next …"). The whole card
/// toggles the agenda; an open tile gets a ring in the colo colour, an open single card loses
/// its bottom edge (the agenda continues it).
private struct ColoEventCard: View {
    let tile: ColocatedCardsLogic.ColoTile
    let index: ScheduleIndex
    let onToggle: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let card: ColoCard = tile.card
        let e: ColoEvent = card.event
        let open: Bool = tile.open
        let key: String = e.key
        let nameStyle: AppTextStyle = type.slotHeading.copy(size: tile.tile ? 16 : 18, lineHeight: tile.tile ? 17 : 19, letterSpacing: 0.04)
        let ring: Color? = tile.ring.map { colors.color($0) }
        Button {
            onToggle(key)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    CapsText(e.name, style: nameStyle, color: colors.ink)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    AppIconImage(open ? .expandLess : .expandMore, size: 22)
                        .foregroundStyle(colors.muted)
                }
                runsText(ColocatedCardsLogic.roomLine(index, e), style: type.small, colors: colors)
                    .appTextStyle(type.small)
                    .foregroundStyle(colors.muted)
                    .padding(.top, 4)
                    .padding(.trailing, 6)
                hours(card)
                    .padding(.top, 5)
                    .padding(.trailing, 6)
                if !card.lines.isEmpty {
                    lines(card.lines)
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                }
            }
            .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
            .padding(.trailing, 6)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget), maxHeight: .infinity, alignment: .topLeading)
            .cardSurface(
                fill: colors.surface,
                border: colors.color(tile.border),
                stripe: colors.category("colo"),
                ring: ring,
                edges: tile.attachedBelow ? .top : .all
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: ColocatedCardsLogic.agendaState(open)))
        .accessibilityHint(Text(verbatim: ColocatedCardsLogic.toggleHint(open)))
    }

    /// "Half day ·", "1:20–5:30 PM" (each piece whole), then the "You" / "Anthropic" pills.
    private func hours(_ card: ColoCard) -> some View {
        let pieces: [String] = ColocatedCardsLogic.hoursPieces(card.event)
        return FlowRow(horizontalSpacing: 8, verticalSpacing: 4, itemAlignment: .center) {
            ForEach(0..<pieces.count, id: \.self) { i in
                CapsText(pieces[i], style: type.meta, color: colors.muted, lineLimit: 1)
            }
            if card.mine {
                Pill(SessionText.YOU, tone: .you)
            }
            if card.anthropic {
                Pill(SessionText.ANTHROPIC, tone: .anthropic)
            }
        }
    }

    /// At most two entries; the lead line may take two text lines, a "Next" under it one; a
    /// narrower tile gets one more each.
    private func lines(_ lines: [ColoLine]) -> some View {
        let isTile: Bool = tile.tile
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<lines.count, id: \.self) { i in
                ColoLineText(line: lines[i], index: index, maxLines: ColocatedCardsLogic.lineMaxLines(i, lines[i], tile: isTile))
            }
        }
    }
}

/// "NOW · 12 MIN LEFT · <title>" in pink; "NEXT 10:40 · <title>" / "STARTS 9:00 AM · <title>"
/// muted and ink (Kotlin `ColoLineText`). The label is Barlow 14.5 (bold for Now, else semibold).
private struct ColoLineText: View {
    let line: ColoLine
    let index: ScheduleIndex
    let maxLines: Int

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let runs: [TextRun] = ColocatedCardsLogic.lineText(line, index)
        lineText(runs)
            .appTextStyle(type.small)
            .foregroundStyle(colors.color(ColocatedCardsLogic.lineColor(line)))
            .lineLimit(maxLines)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineText(_ runs: [TextRun]) -> Text {
        var text = Text(verbatim: "")
        for (i, run) in runs.enumerated() {
            var piece = Text(verbatim: run.text)
            if i == 0 {
                // Run 0: the label, in Barlow (Kotlin SpanStyle(fontFamily = Barlow, 14.5 sp, 0.05 em, tnum)).
                let label: AppTextStyle = AppTextStyle.barlow(14.5, run.bold ? .bold : .semibold, spacing: 0.05)
                piece = piece.appFont(label)
            } else if run.bold {
                piece = piece.font(type.small.bold.font)
            }
            if let role = run.role {
                piece = piece.foregroundStyle(colors.color(role))
            }
            text = text + piece
        }
        return text
    }
}

// MARK: - ColoAgendaCard

/// An open event's agenda (Kotlin `ColoAgendaCard`): the rest of its talks (mine pink, Anthropic
/// tinted, live in pink, other rooms named) and its breaks (quiet), then the event's pass note
/// and links and a "Hide agenda" button (so a long agenda can be closed from its foot). Every row
/// opens the session's details. `attached`: drawn as the continuation of the card above (one per
/// row); otherwise a full-width panel with its own heading and close button (two per row). With
/// `onToggleGoing`, every talk row has a star (`goingIds` filled, `clashIds` "Clash").
struct ColoAgendaCard: View {
    let card: ColoCard
    let attached: Bool
    let me: String?
    let index: ScheduleIndex
    let selectedId: String?
    let revealId: String?
    let onHide: (String) -> Void
    let onOpen: (String) -> Void
    let onRevealed: (String) -> Void
    var goingIds: Set<String>
    var clashIds: Set<String>
    var onToggleGoing: ((String) -> Void)?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        card: ColoCard,
        attached: Bool,
        me: String?,
        index: ScheduleIndex,
        selectedId: String?,
        revealId: String?,
        onHide: @escaping (String) -> Void,
        onOpen: @escaping (String) -> Void,
        onRevealed: @escaping (String) -> Void,
        goingIds: Set<String> = [],
        clashIds: Set<String> = [],
        onToggleGoing: ((String) -> Void)? = nil
    ) {
        self.card = card
        self.attached = attached
        self.me = me
        self.index = index
        self.selectedId = selectedId
        self.revealId = revealId
        self.onHide = onHide
        self.onOpen = onOpen
        self.onRevealed = onRevealed
        self.goingIds = goingIds
        self.clashIds = clashIds
        self.onToggleGoing = onToggleGoing
    }

    var body: some View {
        let e: ColoEvent = card.event
        let key: String = e.key
        let rows = ColocatedCardsLogic.agendaRows(card, index, selectedId: selectedId, revealId: revealId,
                                                  goingIds: goingIds, clashIds: clashIds)
        VStack(alignment: .leading, spacing: 0) {
            if !attached {
                panelHeading(e)
            }
            // Rows: inset 8 pt less than the text so mine/Anthropic rows can bleed out (as in group cards).
            // The rule is drawn inside the padding (Kotlin `padding(...).drawBehind`), along the rows' top edge.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.item.session.id) { row in
                    if let breakText = row.breakText {
                        ColoBreakRow(row: row, text: breakText, onOpen: onOpen)
                    } else {
                        KidRow(model: row.kid, me: me, index: index, onOpen: onOpen, onRevealed: onRevealed, onToggleGoing: onToggleGoing)
                    }
                }
            }
            .background(alignment: .top) {
                KidListRule()
            }
            .padding(.leading, CGFloat(Dimens.categoryStripe) + 4)
            .padding(.trailing, 4)
            .padding(.top, attached ? 0 : 2)
            if let footer = ColocatedCardsLogic.footer(e) {
                ColoFooter(footer: footer)
            }
            HideAgendaButton(eventName: e.name) {
                onHide(key)
            }
        }
        .padding(.top, attached ? 0 : 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(
            fill: colors.surface,
            border: colors.color(ColocatedCardsLogic.border(card)),
            stripe: colors.category("colo"),
            edges: attached ? .bottom : .all
        )
        .padding(.bottom, CGFloat(Dimens.cardGap))
    }

    /// The detached panel's heading: the event name and a close button.
    private func panelHeading(_ e: ColoEvent) -> some View {
        let key: String = e.key
        let side = CGFloat(Dimens.touchTarget)
        return HStack(alignment: .center, spacing: 0) {
            CapsText(e.name, style: type.slotHeading.copy(size: 17, lineHeight: 18, letterSpacing: 0.04), color: colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button {
                onHide(key)
            } label: {
                AppIconImage(.expandLess, size: 24)
                    .foregroundStyle(colors.muted)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: ColocatedCardsLogic.hideAgendaLabel(e.name)))
        }
        .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
    }
}

/// The agenda's last row (Kotlin `HideAgendaButton`): a full-width 48 pt "Hide agenda" button
/// (the group cards' "Show all" look).
private struct HideAgendaButton: View {
    let eventName: String
    let action: () -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .circular)
        Button(action: action) {
            HStack(alignment: .center, spacing: 4) {
                AppIconImage(.expandLess, size: 20)
                    .foregroundStyle(colors.muted)
                CapsText(ColocatedCardsLogic.HIDE_AGENDA, style: type.meta, color: colors.ink, lineLimit: 1)
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget))
            .background { shape.fill(colors.bg) }
            .overlay { shape.strokeBorder(colors.line, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: ColocatedCardsLogic.hideAgendaLabel(eventName)))
        .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
        .padding(.trailing, 12)
        .padding(.top, 10)
    }
}

/// A quiet break row inside an agenda (Kotlin `ColoBreakRow`): "10:15  **Coffee Break** · until
/// 10:40 · Meeting room foyers". Opens the details (the menu).
private struct ColoBreakRow: View {
    let row: ColocatedCardsLogic.AgendaRow
    let text: [TextRun]
    let onOpen: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .circular)
        let s: Session = row.item.session
        let id: String = s.id
        let selected: Bool = row.kid.selected
        let textStyle: AppTextStyle = type.tiny.copy(size: 13.5)
        Button {
            onOpen(id)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                CapsText(TimeFormat.hm(s.start), style: type.kidTime,
                         color: colors.color(ColocatedCardsLogic.breakTimeColor(row.item)), lineLimit: 1)
                    .frame(width: 50, alignment: .leading)
                runsText(text, style: textStyle, colors: colors)
                    .appTextStyle(textStyle)
                    .foregroundStyle(colors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget), alignment: .leading)
            .background {
                if row.kid.divider {
                    Rectangle()
                        .fill(colors.line)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .overlay {
                if selected {
                    shape.strokeBorder(colors.ink, lineWidth: 2)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: ScheduleCardsLogic.OPEN_DETAILS))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The event's info under its agenda (Kotlin `ColoFooter`): its pass note and links ("Event page
/// ↗", "Official listing ↗"). A link nothing can open does nothing.
private struct ColoFooter: View {
    let footer: ColocatedCardsLogic.Footer

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.openURL) private var openURL

    var body: some View {
        FlowRow(horizontalSpacing: 8, verticalSpacing: 8, itemAlignment: .center) {
            if let note = footer.passNote {
                Text(verbatim: note)
                    .appTextStyle(type.small.bold)
                    .foregroundStyle(colors.note)
            }
            ForEach(footer.links, id: \.text) { link in
                let url: String = link.url
                Button {
                    if let u = URL(string: url) {
                        openURL(u)
                    }
                } label: {
                    CapsText(link.text, style: type.button.copy(size: 14), color: colors.ink, lineLimit: 1)
                }
                .buttonStyle(OutlineButtonStyle(horizontalPadding: 14))
            }
        }
        .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
        .padding(.trailing, 12)
        .padding(.top, 10)
    }
}
