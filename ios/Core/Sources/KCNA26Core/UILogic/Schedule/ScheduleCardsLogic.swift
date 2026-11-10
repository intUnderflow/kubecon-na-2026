import Foundation

/// The pure parts of Kotlin ui/schedule/ScheduleCards.kt (web `card(x)`, `seriesCard(g)`,
/// `.kid`, `.lrow`): what each card shows and which colours it picks, so the SwiftUI
/// `SessionCard`, `GroupCard`, `KidRow`, `BreakRow` and `WhereLine` only lay out. Helpers are
/// named after the composable they come from (`sessionCard…`, `groupCard…`, `kidRow…`).
enum ScheduleCardsLogic {
    /// Accessibility hint of every card / row that opens the details (Kotlin `onClickLabel`).
    static let OPEN_DETAILS = "Open details"

    // MARK: - SessionCard

    /// The card's eyebrow: a co-located talk (in search results) shows its event's name in place
    /// of "Event"; otherwise the category label ("" for breaks: no eyebrow).
    static func sessionCardLabel(_ index: ScheduleIndex, _ block: SessionBlock) -> String {
        index.coloEventOf(block.session)?.name ?? index.categoryLabel(block.category)
    }

    /// The outlined summit tag in the meta row: a Maintainer Summit note other than "Keynote".
    static func sessionCardTag(_ s: Session) -> String? {
        guard let tag = s.note, s.isMaintainerSummit, !kotlinEquals(tag, "Keynote") else { return nil }
        return tag
    }

    /// ``WhereLine``'s note ("Sold out", "All-Access pass"): KubeCon notes only (the summit's
    /// are tags).
    static func whereLineNote(_ s: Session) -> String? { s.isMaintainerSummit ? nil : s.note }

    /// The colours of a session card (Kotlin SessionCard's `fill` / `border` / `stripe` / `ink` /
    /// `muted` and the live bar's `progressColor`; `label` is the eyebrow's colour).
    struct SessionCardColors: Sendable, Hashable {
        let fill: PaletteRole
        let border: PaletteRole
        let stripe: PaletteRole
        /// Title and room.
        let ink: PaletteRole
        /// Time, duration, speakers, building.
        let muted: PaletteRole
        /// The eyebrow.
        let label: PaletteRole
        /// The live progress bar.
        let progress: PaletteRole
        /// The summit tag's outline, at ``tagBorderAlpha`` (Kotlin `c.onYou.copy(alpha = 0.6f)` on
        /// my cards, else `c.line`).
        let tagBorder: PaletteRole
        let tagBorderAlpha: Double
        /// The "Live · N min left" pill (background, text).
        let livePill: PaletteRole
        let livePillText: PaletteRole
        /// The where line's note.
        let note: PaletteRole
    }

    /// Kotlin SessionCard: mine (pink), Anthropic (clay tint), going (ink accent), live (pink
    /// border) or plain, in that order of precedence.
    static func sessionCardColors(_ category: String, mine: Bool, anthropic: Bool, going: Bool, live: Bool) -> SessionCardColors {
        let cat = PaletteRole.category(category)
        let fill: PaletteRole
        let border: PaletteRole
        let stripe: PaletteRole
        if mine {
            fill = .you; border = .you; stripe = .you
        } else if anthropic {
            fill = .anthropicCardBg; border = going ? .goingCardBorder : .anthropicCardBorder; stripe = .anthropic
        } else if going {
            fill = .goingCardBg; border = live ? .liveBorder : .goingCardBorder; stripe = cat
        } else if live {
            fill = .surface; border = .liveBorder; stripe = cat
        } else {
            fill = .surface; border = .line; stripe = cat
        }
        return SessionCardColors(
            fill: fill,
            border: border,
            stripe: stripe,
            ink: mine ? .onYou : .ink,
            muted: mine ? .onYou : .muted,
            label: mine ? .onYou : cat,
            progress: mine ? .onYou : .you,
            tagBorder: mine ? .onYou : .line,
            tagBorderAlpha: mine ? 0.6 : 1,
            livePill: mine ? .onYou : .you,
            livePillText: mine ? .you : .onYou,
            note: mine ? .onYou : .note
        )
    }

    /// Everything a session card shows (Kotlin `SessionCard`, web `card(x)`), in order: the meta
    /// row (eyebrow, time, duration, summit tag, "You’re speaking", "Anthropic", the live pill,
    /// "Clash"), the title, the speakers (``speakersLine`` in the app with `session.speakers`),
    /// the where line. A star toggle sits top-right when the screen passes one
    /// (``GoingUiLogic/STAR_RESERVE`` kept free).
    struct SessionCardModel: Sendable, Hashable {
        let session: Session
        /// "" = no eyebrow.
        let label: String
        /// "9:00–9:30 AM".
        let time: String
        let duration: String?
        let tag: String?
        /// The "You’re speaking" pill (``SessionText/YOU_SPEAKING``).
        let mine: Bool
        /// The "Anthropic" pill (``SessionText/ANTHROPIC``).
        let anthropic: Bool
        /// "Live · 12 min left" while live; nil otherwise.
        let livePill: String?
        /// The "Clash" tag (``GoingText/CLASH``).
        let clash: Bool
        let going: Bool
        let roomName: String
        /// "" = none.
        let building: String
        let note: String?
        /// The live bar (0...1), nil for none.
        let progress: Float?
        let colors: SessionCardColors
    }

    static func sessionCard(_ block: SessionBlock, _ status: CardStatus, _ index: ScheduleIndex, going: Bool = false, clash: Bool = false) -> SessionCardModel {
        let s = block.session
        return SessionCardModel(
            session: s,
            label: sessionCardLabel(index, block),
            time: TimeFormat.range(s),
            duration: TimeFormat.dur(s),
            tag: sessionCardTag(s),
            mine: block.mine,
            anthropic: block.anthropic,
            livePill: status.live ? status.liveLabel : nil,
            clash: clash,
            going: going,
            roomName: index.roomName(s.room),
            building: index.building(s.room),
            note: whereLineNote(s),
            progress: status.progress,
            colors: sessionCardColors(block.category, mine: block.mine, anthropic: block.anthropic, going: going, live: status.live)
        )
    }

    // MARK: - BreakRow

    /// Web `.lrow`: "9:00–9:30 AM", then **Coffee Break** (without the ☕) · room. Not tappable.
    static func breakRow(_ s: Session, _ index: ScheduleIndex) -> (time: String, title: String, room: String) {
        (TimeFormat.range(s), ScheduleLogic.breakTitle(s.title), index.roomName(s.room))
    }

    // MARK: - GroupCard

    /// A group collapses when it has more kids than this (web `kids.length > 12`)...
    static let GROUP_COLLAPSE_OVER = 12
    /// ...and then shows this many (web `kids.slice(0,6)`) and a "Show all N" button.
    static let GROUP_COLLAPSED_SHOWS = 6

    /// Web: all kids when expanded, ≤ 12 of them, or one is mine. Also keeps a jumped-to
    /// (`revealId`) or selected kid visible.
    static func groupCardShowsAll(_ kids: [Session], expanded: Bool, anyMine: Bool, revealId: String?, selectedId: String?) -> Bool {
        if expanded || kids.count <= GROUP_COLLAPSE_OVER || anyMine { return true }
        if let revealId, kids.contains(where: { $0.id == revealId }) { return true }
        if let selectedId, kids.contains(where: { $0.id == selectedId }) { return true }
        return false
    }

    /// "3 sessions" / "1 session".
    static func sessionsCount(_ n: Int) -> String { "\(n) \(n == 1 ? "session" : "sessions")" }

    /// The header's star mark (Kotlin `GoingMark`) description: "RSVP’d to 2 of these"; nil when none is starred.
    static func groupCardStarred(_ kids: [Session], _ goingIds: Set<String>) -> String? {
        let starred = kids.count { goingIds.contains($0.id) }
        return starred > 0 ? "RSVP’d to \(starred) of these" : nil
    }

    /// The collapse button: "Show all 14".
    static func showAllLabel(_ count: Int) -> String { "Show all \(count)" }

    /// One kid row of a group card or a co-located agenda (Kotlin `KidRow`'s arguments).
    struct KidRowModel: Sendable, Hashable {
        let session: Session
        let live: Bool
        let mine: Bool
        /// An Anthropic colleague is speaking (never set when mine).
        let anthropic: Bool
        /// The 2 pt ink ring (selected in the list–detail layout).
        let selected: Bool
        /// Scroll this row into view, then report it revealed (a banner jump's target).
        let reveal: Bool
        /// The hairline under the row (web `.kid` border-bottom: none on `.me` or the last row).
        let divider: Bool
        let going: Bool
        let clash: Bool
        /// A room to name under the speakers (co-located talks outside their event's main room).
        let place: String?

        /// "9:00" (Kotlin `TimeFormat.hm(kid.start)`), bold while live.
        var time: String { TimeFormat.hm(session.start) }

        /// The inline pill before the title: "You" (mine), "Anthropic" or "Live"; "Clash" follows it.
        var pill: KidPill? { kidRowPill(mine: mine, anthropic: anthropic, live: live) }

        /// The time's colour: white on my pink row, pink while live, else muted.
        var timeColor: PaletteRole { mine ? .onYou : (live ? .you : .muted) }

        /// Title colour (speakers and place: ``speakersColor`` / ``placeColor``).
        var titleColor: PaletteRole { mine ? .onYou : .ink }
        var speakersColor: PaletteRole { mine ? .onYou : .muted }
        var placeColor: PaletteRole { mine ? .onYou : .ink }

        /// Row background: pink (mine), clay tint (Anthropic), the faint going lift, or none.
        var background: PaletteRole? {
            if mine { return .you }
            if anthropic { return .anthropicRowBg }
            if going { return .goingRowBg }
            return nil
        }

        /// Starred (and not mine): an ink rule (``PaletteRole/goingRule``, 3 pt) down the left edge.
        var goingRule: Bool { going && !mine }

        /// Vertical padding of the row's text (Kotlin 9 dp mine, 7 dp otherwise; mine also gets 4 dp outside).
        var verticalPadding: Double { mine ? 9 : 7 }
    }

    /// Kotlin `KID_PILL_LABELS`: the inline pills of kid rows (web `.kid .pill`).
    enum KidPill: String, Sendable, Hashable, CaseIterable {
        case you
        case ant
        case live
        case clash

        var label: String {
            switch self {
            case .you: return "You"
            case .ant: return "Anthropic"
            case .live: return "Live"
            case .clash: return "Clash"
            }
        }

        /// (background, text): "You" white on pink rows, "Anthropic" clay, "Live" pink, "Clash" amber.
        var colors: (background: PaletteRole, text: PaletteRole) {
            switch self {
            case .you: return (.onYou, .you)
            case .ant: return (.anthropic, .onAnthropic)
            case .live: return (.you, .onYou)
            case .clash: return (.clash, .surface)
            }
        }
    }

    /// Kotlin KidRow `pillKey`: mine, else Anthropic, else live; nil for none.
    static func kidRowPill(mine: Bool, anthropic: Bool, live: Bool) -> KidPill? {
        if mine { return .you }
        if anthropic { return .ant }
        if live { return .live }
        return nil
    }

    /// The divider rule under row `i` of `count` (web: none on `.me` or `:last-child`).
    static func kidRowDivider(mine: Bool, _ i: Int, _ count: Int) -> Bool { !mine && i < count - 1 }

    /// Everything a group card shows (Kotlin `GroupCard`, web `seriesCard(g)`).
    struct GroupCardModel: Sendable, Hashable {
        let block: GroupBlock
        /// Category eyebrow ("" = none).
        let label: String
        /// The shown kids' span, "9:00–10:35 AM" (with the Going filter on, only the starred ones are left).
        let span: String
        /// "14 sessions".
        let count: String
        /// A kid is live: the "Live" pill and the live border.
        let anyLive: Bool
        /// The header star's description ("RSVP’d to 2 of these"); nil = no star.
        let starred: String?
        let title: String
        let roomName: String
        let building: String
        /// The kid rows to show (6 while collapsed).
        let kids: [KidRowModel]
        let showAll: Bool
        /// "Show all 14" while collapsed (tap: expand `block.group.key`); nil when every kid shows.
        let showAllLabel: String?

        var border: PaletteRole { anyLive ? .liveBorder : .line }
    }

    /// Kotlin GroupCard's derived state for `block` at `now` (pass the minute).
    static func groupCard(
        _ block: GroupBlock,
        _ now: Date,
        _ me: String?,
        _ index: ScheduleIndex,
        expanded: Bool,
        selectedId: String?,
        revealId: String?,
        goingIds: Set<String> = [],
        clashIds: Set<String> = []
    ) -> GroupCardModel {
        let g = block.group
        let kids = block.kids
        let kidLive = kids.map { ScheduleLogic.isLive($0, now) }
        let kidMine = kids.map { index.isMine($0, me) }
        let showAll = groupCardShowsAll(kids, expanded: expanded, anyMine: kidMine.contains(true), revealId: revealId, selectedId: selectedId)
        let shown = showAll ? kids.count : GROUP_COLLAPSED_SHOWS
        var rows: [KidRowModel] = []
        rows.reserveCapacity(shown)
        for i in 0..<shown {
            let k = kids[i]
            rows.append(KidRowModel(
                session: k,
                live: kidLive[i],
                mine: kidMine[i],
                anthropic: !kidMine[i] && index.hasAnthropic(k, me),
                selected: k.id == selectedId,
                reveal: k.id == revealId,
                divider: kidRowDivider(mine: kidMine[i], i, shown),
                going: goingIds.contains(k.id),
                clash: clashIds.contains(k.id),
                place: nil
            ))
        }
        let end = kids.map(\.effectiveEnd).max() ?? block.start
        return GroupCardModel(
            block: block,
            label: index.categoryLabel(g.category),
            span: ScheduleLogic.spanLabel(block.start, end),
            count: sessionsCount(kids.count),
            anyLive: kidLive.contains(true),
            starred: groupCardStarred(kids, goingIds),
            title: g.title,
            roomName: index.roomName(g.room),
            building: index.building(g.room),
            kids: rows,
            showAll: showAll,
            showAllLabel: showAll ? nil : showAllLabel(kids.count)
        )
    }
}
