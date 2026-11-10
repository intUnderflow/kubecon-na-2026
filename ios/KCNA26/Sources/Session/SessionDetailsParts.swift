import SwiftUI

// Kotlin ui/session/SessionDetailsParts.kt: the pieces of the session details (web sheetHTML),
// laid out in the web's order by `DetailsBody`, and the pinned `DirectionsBar` under them.
// What is shown and in which state is Core's (`SessionDetailsLogic`, strings `SessionText`);
// these views only lay out. The RSVP parts (clash note, reminder hint, RSVP button) are the
// Going views (Going/GoingUi.swift).

// MARK: - DetailsBody

/// Everything above the pinned Directions bar, in the web's sheetHTML order (Kotlin
/// `DetailsBody`): meta row, title (a heading), where row, co-located extras, pills, the clash
/// note, speakers, getting there, about, links.
///
/// - Parameters:
///   - result: the details lookup so far (nil: still loading).
///   - showLoading: "Loading…" may show (set ``SessionDetailsLogic/LOADING_DELAY_MS`` after opening).
///   - reserveCloseSpace: keep the meta row clear of the × button.
struct DetailsBody: View {
    let session: Session
    let repo: Repository
    let room: Room?
    let result: DetailsResult?
    let showLoading: Bool
    let me: String?
    let reserveCloseSpace: Bool

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        session: Session,
        repo: Repository,
        room: Room?,
        result: DetailsResult?,
        showLoading: Bool,
        me: String?,
        reserveCloseSpace: Bool
    ) {
        self.session = session
        self.repo = repo
        self.room = room
        self.result = result
        self.showLoading = showLoading
        self.me = me
        self.reserveCloseSpace = reserveCloseSpace
    }

    var body: some View {
        let info: DetailInfo? = result?.info
        let detailSpeakers: [SpeakerTagline] = info?.speakers ?? []
        let rows: [SessionText.SpeakerRow] = SessionText.speakerRows(
            detailSpeakers, session.speakers, me, repo.anthropicSpeakers
        )
        let reserve = CGFloat(SessionDetailsLogic.metaTrailingReserve(closeButton: reserveCloseSpace))
        let official: String? = SessionText.officialUrl(repo, session)
        VStack(alignment: .leading, spacing: 0) {
            MetaRow(meta: SessionDetailsLogic.meta(repo, session))
                .padding(.trailing, reserve)
            Text(verbatim: session.title)
                .appTextStyle(type.sheetTitle)
                .foregroundStyle(colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            WhereRow(session: session, room: room)
            if let colo = SessionDetailsLogic.coloInfo(repo, session) {
                DetailsColoInfo(info: colo)
            }
            DetailsPills(session: session, mine: isMine(session, me), anthropic: repo.hasAnthropic(session, me))
            // Starred and overlapping: "Clash" and what with.
            GoingClashNote(session: session)
            if !rows.isEmpty {
                DetailsSectionLabel(SessionText.speakersHeading(rows.count))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.indices, id: \.self) { i in
                        SpeakerItem(row: rows[i])
                    }
                }
            }
            // Getting there (the web's .wf .loc): "Level 2 · Salt Palace · 251 A–C". The button is pinned below.
            if let there = SessionDetailsLogic.gettingThere(room) {
                DetailsSectionLabel(SessionText.GETTING_THERE)
                GettingThereLine(there: there)
            }
            AboutSection(result: result, showLoading: showLoading)
            LinksRow(links: SessionDetailsLogic.links(session, official, info))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Meta, where, co-located extras

/// Category · "Wed 5:00–5:30 PM" · duration · tag (the web's `.meta`; Kotlin `MetaRow`). A
/// co-located session's event name ("ArgoCon") is the eyebrow in place of the category.
private struct MetaRow: View {
    let meta: SessionDetailsLogic.Meta

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        FlowRow(horizontalSpacing: 10, verticalSpacing: 4, itemAlignment: .center) {
            if !meta.label.isEmpty {
                CapsText(meta.label, style: type.meta.bold, color: colors.category(meta.labelCategory))
            }
            CapsText(meta.dayAndTime, style: type.meta, color: colors.muted)
            if let duration = meta.duration {
                CapsText(duration, style: type.meta, color: colors.muted)
            }
            if let tag = meta.tag {
                CapsText(tag, style: type.meta.copy(size: 12.5), color: colors.muted)
                    .padding(EdgeInsets(top: 1, leading: 5, bottom: 0, trailing: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .circular)
                            .strokeBorder(colors.line, lineWidth: 1)
                    }
            }
        }
        .padding(.top, 2)
    }
}

/// Room · building · note (the web's `.where`; Kotlin `WhereRow`): the room in bold ink, the
/// building muted, a KubeCon note ("Sold out") in bold note amber.
private struct WhereRow: View {
    let session: Session
    let room: Room?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let base: AppTextStyle = type.small.copy(size: 15)
        FlowRow(horizontalSpacing: 8, verticalSpacing: 2) {
            Text(verbatim: SessionText.roomName(room, session))
                .appTextStyle(base.bold)
                .foregroundStyle(colors.ink)
            if let building = SessionText.buildingLabel(room) {
                Text(verbatim: building)
                    .appTextStyle(base)
                    .foregroundStyle(colors.muted)
            }
            if let note = SessionText.whereNote(session) {
                Text(verbatim: note)
                    .appTextStyle(base.bold)
                    .foregroundStyle(colors.note)
            }
        }
    }
}

/// Co-located extras under the where row (Kotlin `ColoInfo`): which events a shared break
/// serves, the talk's format, level and "Sponsored" tags (outlined, like the summit tag;
/// "Sponsored" in note amber), and its topic.
private struct DetailsColoInfo: View {
    let info: SessionDetailsLogic.ColoInfo

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let tags: [String] = info.tags
        VStack(alignment: .leading, spacing: 0) {
            if let serves = info.serves {
                Text(verbatim: serves)
                    .appTextStyle(type.small)
                    .foregroundStyle(colors.muted)
                    .padding(.top, 4)
            }
            if !tags.isEmpty {
                FlowRow(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(tags.indices, id: \.self) { i in
                        tagView(tags[i])
                    }
                }
                .padding(.top, 8)
            }
            if let topic = info.topic {
                Text(verbatim: topic)
                    .appTextStyle(type.small)
                    .foregroundStyle(colors.muted)
                    .padding(.top, 6)
            }
        }
    }

    private func tagView(_ tag: String) -> some View {
        let tint: Color = colors.color(SessionDetailsLogic.coloTagColor(tag))
        return CapsText(tag, style: type.pill.copy(size: 13), color: tint)
            .padding(EdgeInsets(top: 3, leading: 6, bottom: 2, trailing: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .circular)
                    .strokeBorder(colors.line, lineWidth: 1)
            }
    }
}

// MARK: - Pills

/// "You’re speaking", "Anthropic", "Live · N min left" (Kotlin `Pills`). Only this reads the
/// ticking clock (``NowReader``, every 15 s), so the live countdown moves while the details are open.
private struct DetailsPills: View {
    let session: Session
    let mine: Bool
    let anthropic: Bool

    var body: some View {
        let s: Session = session
        let mineFlag: Bool = mine
        let anthropicFlag: Bool = anthropic
        NowReader { now in
            DetailsPillsLine(pills: SessionDetailsLogic.pills(s, mine: mineFlag, anthropic: anthropicFlag, now: now))
        }
    }
}

/// The pills as a flow row (8 pt top margin), or a zero-size placeholder: never an empty view,
/// so ``NowReader`` keeps ticking and the "Live" pill appears when the session starts.
private struct DetailsPillsLine: View {
    let pills: [SessionDetailsLogic.Pill]

    @Environment(\.appColors) private var colors

    var body: some View {
        if pills.isEmpty {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        } else {
            FlowRow(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(pills.indices, id: \.self) { i in
                    Pill(
                        pills[i].text,
                        background: colors.color(pills[i].background),
                        content: colors.color(pills[i].content),
                        size: .large
                    )
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Section label, speakers, getting there

/// `.panel h3` (Kotlin's private `SectionLabel`): the shared ``SectionLabel`` (Barlow 14,
/// muted, caps, a heading) with the details' 18 pt above and 6 pt below.
private struct DetailsSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        SectionLabel(text)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }
}

/// One speaker (Kotlin `SpeakerItem`): the name ("You" in pink for me, clay plus a small
/// "Anthropic" badge for colleagues, else ink) over the tagline; read as one element.
private struct SpeakerItem: View {
    let row: SessionText.SpeakerRow

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let nameStyle: AppTextStyle = type.small.copy(size: 15, lineHeight: 19.5, weight: .bold)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Kotlin weight(1f, fill = false): wraps beside the badge, never pushes it out.
                Text(verbatim: row.label)
                    .appTextStyle(nameStyle)
                    .foregroundStyle(colors.color(SessionDetailsLogic.speakerColor(row)))
                if row.isAnthropic {
                    Pill(SessionText.ANTHROPIC, tone: .anthropic, size: .badge)
                        .fixedSize()
                        .padding(.leading, 6)
                }
            }
            if !row.tagline.isEmpty {
                Text(verbatim: row.tagline)
                    .appTextStyle(type.small)
                    .foregroundStyle(colors.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The web's `.wf .loc` (Kotlin's getting-there row): an ink "LEVEL 2" badge, then "SALT
/// PALACE · 251 A–C" in muted; VoiceOver reads "Level 2 · Salt Palace · 251 A–C".
private struct GettingThereLine: View {
    let there: SessionDetailsLogic.GettingThere

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            CapsText(there.level, style: type.levelBadge, color: colors.bg)
                .padding(EdgeInsets(top: 4, leading: 8, bottom: 3, trailing: 8))
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .circular)
                        .fill(colors.ink)
                }
            CapsText(there.place, style: type.levelBadge, color: colors.muted)
                .padding(.leading, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: there.accessibilityLabel))
    }
}

// MARK: - About

/// About (Kotlin `About`): the description as paragraphs and lists, or the loading /
/// unavailable note, or nothing (``SessionDetailsLogic/about(_:showLoading:)``).
private struct AboutSection: View {
    let result: DetailsResult?
    let showLoading: Bool

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        switch SessionDetailsLogic.about(result, showLoading: showLoading) {
        case .hidden:
            EmptyView()
        case .loading:
            VStack(alignment: .leading, spacing: 0) {
                DetailsSectionLabel(SessionText.ABOUT)
                Text(verbatim: SessionText.LOADING)
                    .appTextStyle(type.description)
                    .foregroundStyle(colors.muted)
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 0) {
                DetailsSectionLabel(SessionText.ABOUT)
                Text(verbatim: SessionText.UNAVAILABLE)
                    .appTextStyle(type.small)
                    .foregroundStyle(colors.muted)
            }
        case .description(let blocks):
            VStack(alignment: .leading, spacing: 0) {
                DetailsSectionLabel(SessionText.ABOUT)
                DescriptionText(blocks: blocks)
            }
        }
    }
}

/// The description (Kotlin `Description`): paragraphs, bold headings and lists with a hanging
/// indent (a muted marker column of ``SessionDetailsLogic/markerWidth(_:)``), 12 pt apart; bold,
/// italic and links inline. Links are underlined in the talk colour and open in the browser
/// (`openURL`, through the text's link attributes).
struct DescriptionText: View {
    let blocks: [DescriptionFormat.Block]

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(blocks: [DescriptionFormat.Block]) {
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { i in
                block(blocks[i])
            }
        }
    }

    @ViewBuilder
    private func block(_ block: DescriptionFormat.Block) -> some View {
        let style: AppTextStyle = type.description
        switch block {
        case .paragraph(let rich):
            richText(rich, style: style)
        case .heading(let rich):
            richText(rich, style: style.bold)
                .accessibilityAddTraits(.isHeader)
        case .listBlock(let items):
            let markerWidth = CGFloat(SessionDetailsLogic.markerWidth(items))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { j in
                    HStack(alignment: .top, spacing: 0) {
                        Text(verbatim: items[j].marker)
                            .appTextStyle(style)
                            .foregroundStyle(colors.muted)
                            .frame(width: markerWidth, alignment: .leading)
                        richText(items[j].text, style: style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// One block's text: Kotlin `Text(rememberRich(...), style = style, color = ink)`.
    private func richText(_ rich: DescriptionFormat.Rich, style: AppTextStyle) -> some View {
        let link: Color = colors.category("talk")
        return Text(DescriptionText.attributed(rich, style: style, linkColor: link))
            .appTextStyle(style)
            .foregroundStyle(colors.ink)
            // Text draws links in the tint colour.
            .tint(link)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Kotlin `rememberRich`: ``DescriptionFormat/Rich`` -> one `AttributedString` run per
    /// ``DescriptionFormat/Rich/runs`` piece. Bold runs use `style`'s bold face (the bundled
    /// Atkinson Bold), italic ones its italic (`Font.italic()`), links the talk colour, an
    /// underline and their URL (a run whose URL doesn't parse stays plain text). Unstyled runs
    /// take the font `.appTextStyle(style)` sets on the text.
    static func attributed(_ rich: DescriptionFormat.Rich, style: AppTextStyle, linkColor: Color) -> AttributedString {
        var out = AttributedString()
        for run in rich.runs {
            var piece = AttributedString(run.text)
            if run.bold || run.italic {
                let face: AppTextStyle = run.bold ? style.bold : style
                let font: Font = run.italic ? face.font.italic() : face.font
                piece.font = font
            }
            if let target = run.url.flatMap({ URL(string: $0) }) {
                piece.link = target
                piece.foregroundColor = linkColor
                piece.underlineStyle = Text.LineStyle.single
            }
            out.append(piece)
        }
        return out
    }
}

// MARK: - Links

/// Slides ↗, Proposal and replies on GitHub ↗, an extra summit link, Official listing ↗ (the
/// web's `.links`; Kotlin `Links`), all opening in the browser. 18 pt above, 4 below, even when
/// empty (as Kotlin's FlowRow).
private struct LinksRow: View {
    let links: [SessionDetailsLogic.Link]

    var body: some View {
        FlowRow(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(links.indices, id: \.self) { i in
                LinkButton(link: links[i])
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

/// Kotlin `LinkButton`: ink-filled (primary) or outlined, card radius, 48 pt high, 16 pt in.
private struct LinkButton: View {
    let link: SessionDetailsLogic.Link

    @Environment(\.appType) private var type
    @Environment(\.openURL) private var openURL

    var body: some View {
        let target: String = link.url
        let open: OpenURLAction = openURL
        let button = Button {
            // A bad URL: nothing to do, never crash.
            if let url = URL(string: target) {
                open(url)
            }
        } label: {
            CapsText(link.text, style: type.button)
        }
        if link.primary {
            button.buttonStyle(InkButtonStyle(horizontalPadding: 16))
        } else {
            button.buttonStyle(OutlineButtonStyle(horizontalPadding: 16))
        }
    }
}

// MARK: - DirectionsBar

/// The pinned, thumb-reachable bar under the details (Kotlin `DirectionsBar`): the RSVP toggle
/// and the Directions button side by side (56 pt), the web's explanation above them when
/// Directions is unavailable (the button is then disabled), and the notifications-off hint above
/// everything when this session has a reminder to come. A hairline tops it while the details can
/// scroll further.
struct DirectionsBar: View {
    let session: Session
    let room: Room?
    let onDirections: (String) -> Void
    let showDivider: Bool
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        session: Session,
        room: Room?,
        onDirections: @escaping (String) -> Void,
        showDivider: Bool,
        horizontalPadding: CGFloat,
        bottomPadding: CGFloat
    ) {
        self.session = session
        self.room = room
        self.onDirections = onDirections
        self.showDivider = showDivider
        self.horizontalPadding = horizontalPadding
        self.bottomPadding = bottomPadding
    }

    var body: some View {
        let bar: (reason: String?, enabled: Bool) = SessionDetailsLogic.directionsBar(room, session)
        let maxWidth = CGFloat(Dimens.maxTextWidth)
        let id: String = session.id
        let go: (String) -> Void = onDirections
        // spacing 0: the hidden reminder hint takes no room.
        VStack(alignment: .leading, spacing: 0) {
            GoingReminderHint(session: session, padding: EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .widthIn(max: maxWidth)
            if let reason = bar.reason {
                Text(verbatim: reason)
                    .appTextStyle(type.small)
                    .foregroundStyle(colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .widthIn(max: maxWidth)
                    .padding(.bottom, 8)
            }
            HStack(alignment: .top, spacing: 8) {
                GoingToggleButton(session: session)
                Button {
                    go(id)
                } label: {
                    HStack(spacing: 8) {
                        AppIconImage(.directionsWalk, size: 22)
                        CapsText(SessionText.DIRECTIONS, style: type.button.copy(size: 18), lineLimit: 1)
                    }
                }
                .buttonStyle(InkButtonStyle(minHeight: 56, horizontalPadding: 20, fillsWidth: true))
                .disabled(!bar.enabled)
            }
            .widthIn(max: maxWidth)
        }
        .padding(.leading, horizontalPadding)
        .padding(.trailing, horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12 + bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showDivider {
                HairlineDivider()
            }
        }
    }
}

// MARK: - Grab bar, close button

/// The sheet's grab bar (the web's `.grab`; Kotlin `GrabBar`, 42 × 5 between 10 pt margins). On
/// iOS the system drag indicator draws the bar (it also lets VoiceOver resize the sheet), so this
/// keeps only its room at the top of the content, under the indicator.
struct GrabBar: View {
    init() {}

    var body: some View {
        Color.clear
            .frame(height: 25)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// The × button (the web's `.x`; Kotlin `CloseButton`): a 48 pt target, a `bg`-coloured circle
/// so it reads over scrolled text. VoiceOver: "Close".
struct CloseButton: View {
    let onClick: () -> Void

    @Environment(\.appColors) private var colors

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var body: some View {
        let side = CGFloat(Dimens.touchTarget)
        Button(action: onClick) {
            AppIconImage(.close, size: 24)
                .foregroundStyle(colors.ink)
                .frame(width: side, height: side)
                .background {
                    Circle().fill(colors.bg)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: SessionDetailsLogic.CLOSE))
    }
}

// MARK: - Previews

#Preview("Description") {
    ThemePreview {
        DescriptionText(blocks: DescriptionFormat.parse(
            "A **bold** start, some *italic* words and [a link](https://kubernetes.io).\n" +
            "A second line.\n\n" +
            "# A heading\n\n" +
            "\\- one item\n\\- another item, long enough to wrap onto a second line under the first\n\n" +
            "1\\. first\n2\\. second"
        ))
    }
}

#Preview("Speakers, getting there, links") {
    ThemePreview {
        SpeakerItem(row: SessionText.SpeakerRow("You", "Engineer, Anthropic", isMe: true, isAnthropic: false))
        SpeakerItem(row: SessionText.SpeakerRow("Ada Lovelace", "Analyst", isMe: false, isAnthropic: true))
        SpeakerItem(row: SessionText.SpeakerRow("Grace Hopper", "", isMe: false, isAnthropic: false))
        GettingThereLine(there: SessionDetailsLogic.GettingThere(level: "Level 2", place: "Salt Palace · 251 A–C"))
        LinksRow(links: [
            SessionDetailsLogic.Link(text: SessionText.SLIDES, url: "https://example.com", primary: true),
            SessionDetailsLogic.Link(text: SessionText.OFFICIAL, url: "https://example.com", primary: false),
        ])
        CloseButton(onClick: {})
    }
}
