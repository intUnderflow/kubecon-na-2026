import SwiftUI

// Kotlin ui/schedule/ScheduleCards.kt: the session card (web `card(x)`), the where line, the
// quiet break row (`.lrow`), the group card (`seriesCard(g)`) and its kid rows (`.kid`). What each
// shows and which colours it picks come from Core's `ScheduleCardsLogic`.

/// Scroll identity of a kid row (group card or co-located agenda), for the banner jump's reveal.
func kidRowScrollId(_ sessionId: String) -> String { "kid-" + sessionId }

// MARK: - SessionCard

/// Web `card(x)` for a regular session (Kotlin `SessionCard`): category stripe, meta row with
/// pills, title, speakers, room. With `onToggleGoing`, a star toggle sits in the top-right
/// corner; `going` cards get a quiet ink highlight and `clash` adds the "Clash" tag. Mine is pink
/// (with the pink glow), Anthropic clay-tinted, live has a pink border and the progress bar.
/// `selected` (list–detail layout) draws the 2 pt ink ring; `wide` the 17 pt title.
struct SessionCard: View {
    let block: SessionBlock
    let status: CardStatus
    let me: String?
    let index: ScheduleIndex
    let selected: Bool
    let wide: Bool
    let onOpen: (String) -> Void
    var going: Bool
    var clash: Bool
    var onToggleGoing: ((String) -> Void)?

    init(
        block: SessionBlock,
        status: CardStatus,
        me: String?,
        index: ScheduleIndex,
        selected: Bool,
        wide: Bool,
        onOpen: @escaping (String) -> Void,
        going: Bool = false,
        clash: Bool = false,
        onToggleGoing: ((String) -> Void)? = nil
    ) {
        self.block = block
        self.status = status
        self.me = me
        self.index = index
        self.selected = selected
        self.wide = wide
        self.onOpen = onOpen
        self.going = going
        self.clash = clash
        self.onToggleGoing = onToggleGoing
    }

    var body: some View {
        let model = ScheduleCardsLogic.sessionCard(block, status, index, going: going, clash: clash)
        if let onToggleGoing {
            let id: String = block.session.id
            GoingStarFrame(going: going, onToggle: { onToggleGoing(id) }, onCard: block.mine, label: block.session.title) {
                SessionCardBody(model: model, me: me, index: index, selected: selected, wide: wide, starSpace: true, onOpen: onOpen)
            }
        } else {
            SessionCardBody(model: model, me: me, index: index, selected: selected, wide: wide, starSpace: false, onOpen: onOpen)
        }
    }
}

/// The card itself (the whole card opens the details).
private struct SessionCardBody: View {
    let model: ScheduleCardsLogic.SessionCardModel
    let me: String?
    let index: ScheduleIndex
    let selected: Bool
    let wide: Bool
    let starSpace: Bool
    let onOpen: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let s: Session = model.session
        let cc = model.colors
        let ink: Color = colors.color(cc.ink)
        let muted: Color = colors.color(cc.muted)
        let reserve: CGFloat = starSpace ? CGFloat(GoingUiLogic.STAR_RESERVE) : 0
        let id: String = s.id
        let card = Button {
            onOpen(id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                meta(muted: muted)
                    .padding(.trailing, reserve)
                Text(verbatim: s.title)
                    .appTextStyle(titleStyle)
                    .foregroundStyle(ink)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .padding(.trailing, reserve)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !s.speakers.isEmpty {
                    speakersLine(s.speakers, me: me, anthropic: index.anthropicSpeakers, colors: colors, onMine: model.mine, style: type.small)
                        .appTextStyle(type.small)
                        .foregroundStyle(muted)
                }
                WhereLine(roomName: model.roomName, building: model.building, note: model.note,
                          ink: ink, muted: muted, noteColor: colors.color(cc.note))
                    .padding(.top, 5)
            }
            .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
            .padding(.trailing, 12)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(
                fill: colors.color(cc.fill),
                border: colors.color(cc.border),
                stripe: colors.color(cc.stripe),
                progress: model.progress,
                progressColor: colors.color(cc.progress),
                ring: selected ? colors.ink : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: ScheduleCardsLogic.OPEN_DETAILS))
        .accessibilityAddTraits(selected ? .isSelected : [])
        if model.mine {
            card.mineShadow(colors.you)
        } else {
            card
        }
    }

    private var titleStyle: AppTextStyle {
        if model.mine { return type.cardTitleMine }
        return wide ? type.cardTitle.copy(size: 17) : type.cardTitle
    }

    /// Eyebrow (category, or a co-located talk's event), time, duration, summit tag, then the
    /// "You’re speaking" / "Anthropic" / live pills and "Clash".
    private func meta(muted: Color) -> some View {
        let cc = model.colors
        return FlowRow(horizontalSpacing: 10, verticalSpacing: 4, itemAlignment: .center) {
            if !model.label.isEmpty {
                CapsText(model.label, style: type.meta.bold, color: colors.color(cc.label), lineLimit: 2)
            }
            CapsText(model.time, style: type.meta, color: muted, lineLimit: 1)
            if let duration = model.duration {
                CapsText(duration, style: type.meta, color: muted, lineLimit: 1)
            }
            if let tag = model.tag {
                Pill(tag, background: Color.clear, content: muted,
                     border: colors.color(cc.tagBorder).opacity(cc.tagBorderAlpha))
            }
            if model.mine {
                Pill(SessionText.YOU_SPEAKING, tone: .onYou)
            }
            if model.anthropic {
                Pill(SessionText.ANTHROPIC, tone: .anthropic)
            }
            if let live = model.livePill {
                Pill(live, background: colors.color(cc.livePill), content: colors.color(cc.livePillText))
            }
            if model.clash {
                ClashTag(onCard: model.mine)
            }
        }
    }
}

// MARK: - WhereLine

/// Web `.where` (Kotlin `WhereLine`): bold room, muted building, optional note ("Sold out") in
/// the hands-on colour, wrapping as whole pieces.
struct WhereLine: View {
    let roomName: String
    let building: String
    let note: String?
    let ink: Color
    let muted: Color
    let noteColor: Color

    @Environment(\.appType) private var type

    init(roomName: String, building: String, note: String?, ink: Color, muted: Color, noteColor: Color) {
        self.roomName = roomName
        self.building = building
        self.note = note
        self.ink = ink
        self.muted = muted
        self.noteColor = noteColor
    }

    var body: some View {
        FlowRow(horizontalSpacing: 8, verticalSpacing: 2) {
            Text(verbatim: roomName)
                .appTextStyle(type.small.bold)
                .foregroundStyle(ink)
            if !building.isEmpty {
                Text(verbatim: building)
                    .appTextStyle(type.small)
                    .foregroundStyle(muted)
            }
            if let note {
                Text(verbatim: note)
                    .appTextStyle(type.small.bold)
                    .foregroundStyle(noteColor)
            }
        }
    }
}

// MARK: - BreakRow

/// Web `.lrow` (Kotlin `BreakRow`): a quiet dashed break row, "9:00–9:30 AM  **Coffee Break** ·
/// room" (without the ☕). Not tappable, like the web.
struct BreakRow: View {
    let session: Session
    let index: ScheduleIndex

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(session: Session, index: ScheduleIndex) {
        self.session = session
        self.index = index
    }

    var body: some View {
        let row = ScheduleCardsLogic.breakRow(session, index)
        let textStyle: AppTextStyle = type.small.copy(size: 14.5)
        let runs: [TextRun] = [TextRun(row.title, bold: true, role: .ink), TextRun(" · "), TextRun(row.room)]
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CapsText(row.time, style: type.meta.copy(lineHeight: 14), color: colors.muted, lineLimit: 1)
            runsText(runs, style: textStyle, colors: colors)
                .appTextStyle(textStyle)
                .foregroundStyle(colors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashedOutline(colors.line, radius: CGFloat(Dimens.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - GroupCard

/// Web `seriesCard(g)` (Kotlin `GroupCard`): one card for back-to-back sessions in a room. Long
/// groups show 6 kids and a "Show all N" button unless expanded, one of them is mine, or a kid is
/// selected / being revealed by a banner jump. With `onToggleGoing`, every kid row has a star;
/// the header shows a filled star when any kid is starred (so a collapsed card still says so).
struct GroupCard: View {
    let block: GroupBlock
    let now: Date
    let me: String?
    let index: ScheduleIndex
    let expanded: Bool
    let selectedId: String?
    let revealId: String?
    let wide: Bool
    let onExpand: (String) -> Void
    let onOpen: (String) -> Void
    /// A kid row scrolled itself into view for a banner jump (the screen scrolls to
    /// ``kidRowScrollId(_:)`` and clears its reveal id).
    let onRevealed: (String) -> Void
    var goingIds: Set<String>
    var clashIds: Set<String>
    var onToggleGoing: ((String) -> Void)?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        block: GroupBlock,
        now: Date,
        me: String?,
        index: ScheduleIndex,
        expanded: Bool,
        selectedId: String?,
        revealId: String?,
        wide: Bool,
        onExpand: @escaping (String) -> Void,
        onOpen: @escaping (String) -> Void,
        onRevealed: @escaping (String) -> Void,
        goingIds: Set<String> = [],
        clashIds: Set<String> = [],
        onToggleGoing: ((String) -> Void)? = nil
    ) {
        self.block = block
        self.now = now
        self.me = me
        self.index = index
        self.expanded = expanded
        self.selectedId = selectedId
        self.revealId = revealId
        self.wide = wide
        self.onExpand = onExpand
        self.onOpen = onOpen
        self.onRevealed = onRevealed
        self.goingIds = goingIds
        self.clashIds = clashIds
        self.onToggleGoing = onToggleGoing
    }

    var body: some View {
        let m = ScheduleCardsLogic.groupCard(block, now, me, index, expanded: expanded, selectedId: selectedId,
                                             revealId: revealId, goingIds: goingIds, clashIds: clashIds)
        let catColor: Color = colors.category(block.group.category)
        let textLeading: CGFloat = CGFloat(Dimens.categoryStripe) + 12
        VStack(alignment: .leading, spacing: 0) {
            head(m, catColor: catColor)
                .padding(.leading, textLeading)
                .padding(.trailing, 12)
            // Kids: inset 8 pt less than the text so mine/Anthropic rows can bleed out (web margin: 0 -8px).
            // The rule is drawn inside the padding (Kotlin `padding(...).drawBehind`): along the
            // kids' top edge, 8 pt in from the kid list's own edges.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(m.kids, id: \.session.id) { kid in
                    KidRow(model: kid, me: me, index: index, onOpen: onOpen, onRevealed: onRevealed, onToggleGoing: onToggleGoing)
                }
            }
            .background(alignment: .top) {
                KidListRule()
            }
            .padding(.leading, CGFloat(Dimens.categoryStripe) + 4)
            .padding(.trailing, 4)
            .padding(.top, 8)
            if let label = m.showAllLabel {
                showAllButton(label)
                    .padding(.leading, textLeading)
                    .padding(.trailing, 12)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(fill: colors.surface, border: colors.color(m.border), stripe: catColor)
    }

    /// Eyebrow, the kids' span, "14 sessions", "Live", the star mark; the title; the where line.
    private func head(_ m: ScheduleCardsLogic.GroupCardModel, catColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowRow(horizontalSpacing: 10, verticalSpacing: 4, itemAlignment: .center) {
                if !m.label.isEmpty {
                    CapsText(m.label, style: type.meta.bold, color: catColor, lineLimit: 1)
                }
                CapsText(m.span, style: type.meta, color: colors.muted, lineLimit: 1)
                CapsText(m.count, style: type.meta, color: colors.muted, lineLimit: 1)
                if m.anyLive {
                    Pill("Live", tone: .you)
                }
                if let starred = m.starred {
                    GoingMark(starred)
                }
            }
            Text(verbatim: m.title)
                .appTextStyle(wide ? type.cardTitle.copy(size: 17) : type.cardTitle)
                .foregroundStyle(colors.ink)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            WhereLine(roomName: m.roomName, building: m.building, note: nil, ink: colors.ink, muted: colors.muted, noteColor: colors.note)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func showAllButton(_ label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .circular)
        let key: String = block.group.key
        return Button {
            onExpand(key)
        } label: {
            CapsText(label, style: type.meta, color: colors.ink)
                .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget))
                .background { shape.fill(colors.bg) }
                .overlay { shape.strokeBorder(colors.line, lineWidth: 1) }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// The hairline above a group card's or an agenda's kid rows, inset 8 pt at both ends.
struct KidListRule: View {
    @Environment(\.appColors) private var colors

    var body: some View {
        Rectangle()
            .fill(colors.line)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
    }
}

// MARK: - KidRow

/// Web `.kid` (Kotlin `KidRow`): time | pills + title / speakers / place. Mine is a pink row
/// (4 pt margins), Anthropic a clay-tinted one, starred a faint lift with an ink rule down the
/// left edge; live times are bold pink; `selected` draws the 2 pt ink ring. The row opens the
/// details; with `onToggleGoing` the 48 pt star (21 pt glyph) sits at its trailing edge. When
/// the model's `reveal` is set the row reports itself (`onRevealed(id)`) so the screen scrolls it
/// into view (Kotlin `bringIntoView`); its scroll id is ``kidRowScrollId(_:)``.
///
/// Compose draws the pills inline at the start of the title text; SwiftUI can't put a background
/// on a `Text` span, so they lead the title in a baseline-aligned row (the title wraps beside them).
struct KidRow: View {
    let model: ScheduleCardsLogic.KidRowModel
    let me: String?
    let index: ScheduleIndex
    let onOpen: (String) -> Void
    let onRevealed: (String) -> Void
    var onToggleGoing: ((String) -> Void)?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        model: ScheduleCardsLogic.KidRowModel,
        me: String?,
        index: ScheduleIndex,
        onOpen: @escaping (String) -> Void,
        onRevealed: @escaping (String) -> Void,
        onToggleGoing: ((String) -> Void)? = nil
    ) {
        self.model = model
        self.me = me
        self.index = index
        self.onOpen = onOpen
        self.onRevealed = onRevealed
        self.onToggleGoing = onToggleGoing
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .circular)
        let kid: Session = model.session
        let id: String = kid.id
        let star: Bool = onToggleGoing != nil
        HStack(alignment: .top, spacing: 0) {
            Button {
                onOpen(id)
            } label: {
                content
                    .padding(.vertical, CGFloat(model.verticalPadding))
                    .padding(.leading, 8)
                    .padding(.trailing, star ? 0 : 8)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget), alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(verbatim: ScheduleCardsLogic.OPEN_DETAILS))
            .accessibilityAddTraits(model.selected ? .isSelected : [])
            if let onToggleGoing {
                StarToggle(going: model.going, onToggle: { onToggleGoing(id) }, label: kid.title, onCard: model.mine, iconSize: 21)
            }
        }
        .background {
            rowBackground
        }
        .overlay {
            if model.selected {
                shape.strokeBorder(colors.ink, lineWidth: 2)
            }
        }
        .clipShape(shape)
        .padding(.vertical, model.mine ? 4 : 0)
        .id(kidRowScrollId(id))
        .task(id: model.reveal) {
            guard model.reveal else { return }
            await Task.yield()
            onRevealed(id)
        }
    }

    /// Time column (50 pt), then the pills, title, speakers and place.
    private var content: some View {
        let kid: Session = model.session
        let timeStyle: AppTextStyle = model.live ? type.kidTime.bold : type.kidTime
        let fg: Color = colors.color(model.titleColor)
        return HStack(alignment: .top, spacing: 8) {
            CapsText(model.time, style: timeStyle, color: colors.color(model.timeColor), lineLimit: 1)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let pill = model.pill {
                        kidPill(pill)
                    }
                    if model.clash {
                        kidPill(.clash)
                    }
                    Text(verbatim: kid.title)
                        .appTextStyle(type.kidTitle)
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !kid.speakers.isEmpty {
                    speakersLine(kid.speakers, me: me, anthropic: index.anthropicSpeakers, colors: colors, onMine: model.mine, style: type.tiny)
                        .appTextStyle(type.tiny)
                        .foregroundStyle(colors.color(model.speakersColor))
                        .padding(.top, 1)
                }
                if let place = model.place {
                    Text(verbatim: place)
                        .appTextStyle(type.tiny.bold)
                        .foregroundStyle(colors.color(model.placeColor))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func kidPill(_ pill: ScheduleCardsLogic.KidPill) -> some View {
        let roles = pill.colors
        return Pill(pill.label, background: colors.color(roles.background), content: colors.color(roles.text), size: .kid)
    }

    /// Mine pink / Anthropic tint / starred lift, the starred ink rule down the left edge, and
    /// the divider under the row (inset 8 pt; none on mine or the last row).
    private var rowBackground: some View {
        ZStack(alignment: .leading) {
            if let bg = model.background {
                Rectangle().fill(colors.color(bg))
            }
            if model.goingRule {
                Rectangle()
                    .fill(colors.goingRule)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            }
            if model.divider {
                Rectangle()
                    .fill(colors.line)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}
