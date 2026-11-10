import SwiftUI

/// Kotlin ui/schedule/ScheduleScreen.kt `ScheduleScreen`: the home screen and the root of the
/// navigation stack (the shell hides the navigation bar; this screen draws its own header).
/// Brand + clock and day tabs on top, then one scrolling column with the search box, the
/// "You’re speaking" banner, my RSVP'd "Up next" row, the day heading and today's status,
/// half-hour blocks of cards (pinned block headings, the "Up next" line, group cards, quiet break
/// rows) or the search results, and the footer. Port of schedule_app.js `render`.
///
/// Everything it shows is Core's: ``ScheduleScreenLogic/state(_:_:_:selectedDay:query:goingOnly:goingIds:unstarred:remindMinutes:)``
/// (Kotlin's `remember` chain, recomputed per minute), ``ScheduleScreenLogic/listLayout(_:twoPane:wideWindow:)``
/// (Kotlin's `BoxWithConstraints` block) and ``ScheduleRows`` (the list rows, grouped into pinned
/// sections by ``ScheduleRows/sections(_:)``).
///
/// State that survives width-class changes and process death (Kotlin `rememberSaveable`):
/// `@SceneStorage` for the selected day, the search text, expanded groups, open co-located
/// cards, the RSVP'd filter and `unstarred` (kept per filter state and day). The stars live in
/// `graph.going`, "me" in `graph.settings`. The shell keeps this view at one position in both
/// layouts, so its `@State` (scroll position, ticker) survives too.
///
/// "Now" ticks every 15 s (Core `NowTicker`, paused in the background); the list follows the
/// minute. Banner taps jump to the talk in the list (opening its co-located card's agenda first)
/// and open it; the jump waits up to 2 s for the new rows; a jumped-to card lands under its
/// pinned heading (``ScheduleScreenLogic/STICKY_HEADING_HEIGHT``).
///
/// - Parameters:
///   - selectedSessionId: the session whose details are open (sheet or pane); highlighted in
///     the list in the list–detail layout only.
///   - onOpenSession: open a session's details (``NavModel/openSession(_:)``).
///   - onOpenDirections: open Directions for a session (``NavModel/openDirections(_:)``): the
///     "Up next" row's walk button.
///   - onOpenSettings: open Settings (``NavModel/openSettings()``).
///   - twoPane: wide window, the list sits next to the details pane (Kotlin `twoPane`).
struct ScheduleScreen: View {
    let selectedSessionId: String?
    let onOpenSession: (String) -> Void
    let onOpenDirections: (String) -> Void
    let onOpenSettings: () -> Void
    let twoPane: Bool

    @Environment(AppGraph.self) private var graph
    @Environment(\.widthClass) private var widthClass

    // Kotlin rememberSaveable (survives fold/unfold and process death): scene storage.
    @SceneStorage("schedule.selectedDay") private var selectedDay: String?
    @SceneStorage("schedule.search") private var searchText: String = ""
    @SceneStorage("schedule.expanded") private var expandedText: String = ""
    @SceneStorage("schedule.coloOpen") private var coloOpenText: String = ""
    @SceneStorage("schedule.goingOnly") private var goingOnly: Bool = false
    @SceneStorage("schedule.unstarred") private var unstarredText: String = ""

    @State private var ticker: NowTicker?
    @State private var revealId: String?
    @State private var pendingJump: PendingJump?
    @State private var jumpSerial = 0
    @State private var memo = ScheduleScreenMemo()
    @FocusState private var searchFocused: Bool

    /// The list's scroll view, as the coordinate space the co-located card rows measure their top in.
    fileprivate static let listSpace: NamedCoordinateSpace = NamedCoordinateSpace.named("schedule.list")

    init(
        selectedSessionId: String?,
        onOpenSession: @escaping (String) -> Void,
        onOpenDirections: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        twoPane: Bool
    ) {
        self.selectedSessionId = selectedSessionId
        self.onOpenSession = onOpenSession
        self.onOpenDirections = onOpenDirections
        self.onOpenSettings = onOpenSettings
        self.twoPane = twoPane
    }

    var body: some View {
        let index: ScheduleIndex = ScheduleIndex.of(graph.repository)
        let me: String? = graph.settings.speakingAs
        let goingIds: Set<String> = graph.going.ids
        let remindMinutes: Int = graph.going.remindMinutes
        // The schedule only changes once a minute: everything below works on the minute.
        let minute: Date = ScheduleLogic.minuteOf(NowTicking.now(ticker, clock: graph.clock))
        let dayKey: String? = ScheduleLogic.resolveDayKey(index.days, minute, selectedDay)
        let unstarredKey: String = ScheduleScreenLogic.unstarredKey(goingOnly: goingOnly, dayKey: dayKey)
        let unstarred: Set<String> = ScheduleScreenLogic.SavedUnstarred.decode(unstarredText).ids(for: unstarredKey)
        let inputs = ScheduleScreenMemo.Inputs(
            index: ObjectIdentifier(index),
            minute: minute,
            me: me,
            selectedDay: selectedDay,
            query: ScheduleScreenLogic.query(searchText),
            goingOnly: goingOnly,
            goingIds: goingIds,
            unstarred: unstarred,
            remindMinutes: remindMinutes
        )
        let st: ScheduleScreenLogic.State = memo.state(inputs, index)
        GeometryReader { geo in
            let layout: ScheduleScreenLogic.ListLayout = ScheduleScreenLogic.listLayout(
                Double(geo.size.width), twoPane: twoPane, wideWindow: widthClass.isWide
            )
            let ctx = ListContext(
                index: index,
                st: st,
                layout: layout,
                me: me,
                goingIds: goingIds,
                remindMinutes: remindMinutes,
                unstarredKey: unstarredKey,
                highlight: ScheduleScreenLogic.highlight(twoPane: twoPane, selectedSessionId),
                expanded: expanded,
                coloOpen: coloOpen
            )
            ScrollViewReader { proxy in
                screen(ctx, proxy)
            }
        }
        .ticksNow($ticker, clock: graph.clock)
        .task(id: ObjectIdentifier(index)) {
            let idx: ScheduleIndex = index
            await Task.detached(priority: .utility) { idx.prewarmSearch() }.value
        }
        // Kotlin rememberSaveable(goingOnly, dayKey): another filter state or day starts afresh.
        .onChange(of: unstarredKey) { _, key in
            unstarredText = ScheduleScreenLogic.SavedUnstarred(key: key, ids: []).encoded
        }
    }

    // MARK: - Layout

    /// The header, then the list (Kotlin's Column of ScheduleHeader and LazyColumn).
    private func screen(_ ctx: ListContext, _ proxy: ScrollViewProxy) -> some View {
        let rows: [ScheduleRow] = memo.rows(ctx.st, ctx.layout.coloColumns, ctx.coloOpen)
        let sections: [ScheduleRowSection] = memo.lastSections
        let side = CGFloat(ctx.layout.side)
        let rowKeys: [String] = rows.map(\.key)
        return VStack(spacing: 0) {
            ScheduleHeader(
                clock: ctx.st.clock,
                tabs: ctx.st.tabs,
                currentDay: ctx.st.dayKey,
                searching: ctx.st.searching,
                sidePadding: side,
                onDay: { key in onDay(proxy, key) },
                onSettings: onOpenSettings
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.id) { section in
                        Section {
                            ForEach(section.rows, id: \.key) { row in
                                listRow(row, ctx, proxy)
                            }
                        } header: {
                            if let header = section.header {
                                sectionHeader(header)
                            }
                        }
                    }
                }
                .padding(.horizontal, side)
                .padding(.bottom, 16)
            }
            .coordinateSpace(ScheduleScreen.listSpace)
        }
        // The banner jump: re-checked whenever the rows change, until it lands or times out.
        .onChange(of: rowKeys) { _, _ in
            tryJump(proxy)
        }
        .onChange(of: pendingJump) { _, _ in
            tryJump(proxy)
        }
        .task(id: pendingJump) {
            await waitForJump(proxy)
        }
    }

    /// Kotlin `stickyHeader` content: a half-hour block or a named section.
    @ViewBuilder
    private func sectionHeader(_ row: ScheduleRow) -> some View {
        switch row {
        case .slotHead(let slot):
            RuledHeading(slot.label)
        case .section(_, let title):
            RuledHeading(title, topPadding: 16)
        default:
            EmptyView()
        }
    }

    /// One list row, with the hooks the scrolling needs: the jump anchor above its top, whether
    /// it is laid out, and (co-located card rows) where its top is.
    private func listRow(_ row: ScheduleRow, _ ctx: ListContext, _ proxy: ScrollViewProxy) -> some View {
        let key: String = row.key
        let memo: ScheduleScreenMemo = memo
        var isColo = false
        if case .colo = row { isColo = true }
        return rowContent(row, ctx, proxy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                JumpAnchor(id: ScheduleScreen.jumpAnchorId(key))
            }
            .background {
                if isColo {
                    RowTopReader(key: key, memo: memo)
                }
            }
            .onAppear {
                memo.realized.insert(key)
            }
            .onDisappear {
                memo.realized.remove(key)
            }
    }

    /// Kotlin's `when (r)` over the rows.
    @ViewBuilder
    private func rowContent(_ row: ScheduleRow, _ ctx: ListContext, _ proxy: ScrollViewProxy) -> some View {
        switch row {
        case .search:
            ScheduleSearchField(text: $searchText, focus: $searchFocused)
        case .banner(let banner):
            MineBannerCard(banner: banner, onTalk: { s in onTalk(ctx.index, s) })
        case .goingNext(let next):
            VStack(alignment: .leading, spacing: 0) {
                GoingNextCard(
                    next,
                    onOpen: { onTalk(ctx.index, next.session) },
                    onDirections: { onOpenDirections(next.session.id) }
                )
                // Its reminder can't reach me: say so right here (hidden when notifications are on).
                if ScheduleScreenLogic.goingNextShowsHint(next, ctx.remindMinutes) {
                    NotificationsOffHint(channel: .going, padding: EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
                }
            }
        case .dayHead(let view):
            DayHeading(view, large: ctx.layout.large) {
                goingChip
            }
        case .upNext:
            UpNextLine()
        case .searchHead(let heading):
            SearchHeading(heading, large: ctx.layout.large) {
                goingChip
            }
        case .empty(let empty):
            EmptyState(title: empty.title, text: empty.text)
        case .footer:
            ScheduleFooter()
        case .item(let block, _):
            itemRow(block, ctx, proxy)
        case .colo(let cards):
            ColoCardRow(cards: cards, columns: ctx.layout.coloColumns, open: ctx.coloOpen, index: ctx.index, onToggle: { key in
                toggleColo(key)
            })
        case .coloAgenda(let card, let attached):
            ColoAgendaCard(
                card: card,
                attached: attached,
                me: ctx.me,
                index: ctx.index,
                selectedId: ctx.highlight,
                revealId: revealId,
                onHide: { key in hideColo(proxy, key) },
                onOpen: { id in openSession(id) },
                onRevealed: { id in revealed(proxy, id) },
                goingIds: ctx.goingIds,
                clashIds: ctx.st.clashIds,
                onToggleGoing: { id in toggleGoing(id, ctx.unstarredKey) }
            )
        case .section, .slotHead:
            EmptyView()
        }
    }

    /// A session card, a break row or a group card.
    @ViewBuilder
    private func itemRow(_ block: Block, _ ctx: ListContext, _ proxy: ScrollViewProxy) -> some View {
        let gap = CGFloat(Dimens.cardGap)
        switch block {
        case .session(let b):
            if b.category == "log" {
                BreakRow(session: b.session, index: ctx.index)
                    .padding(.bottom, gap)
            } else {
                SessionCard(
                    block: b,
                    status: ctx.index.cardStatus(b.session, ctx.st.minute),
                    me: ctx.me,
                    index: ctx.index,
                    selected: b.session.id == ctx.highlight,
                    wide: ctx.layout.roomy,
                    onOpen: { id in openSession(id) },
                    going: ctx.goingIds.contains(b.session.id),
                    clash: ctx.st.clashIds.contains(b.session.id),
                    onToggleGoing: { id in toggleGoing(id, ctx.unstarredKey) }
                )
                .padding(.bottom, gap)
            }
        case .group(let g):
            GroupCard(
                block: g,
                now: ctx.st.minute,
                me: ctx.me,
                index: ctx.index,
                expanded: ctx.expanded.contains(g.group.key),
                selectedId: ctx.highlight,
                revealId: revealId,
                wide: ctx.layout.roomy,
                onExpand: { key in expand(key) },
                onOpen: { id in openSession(id) },
                onRevealed: { id in revealed(proxy, id) },
                goingIds: ctx.goingIds,
                clashIds: ctx.st.clashIds,
                onToggleGoing: { id in toggleGoing(id, ctx.unstarredKey) }
            )
            .padding(.bottom, gap)
        }
    }

    /// The day / search heading's RSVP'd filter chip.
    private var goingChip: some View {
        GoingChip(on: goingOnly, onToggle: { goingOnly.toggle() })
    }

    // MARK: - Saved sets

    private var expanded: Set<String> { ScheduleScreenLogic.decodeSet(expandedText) }
    private var coloOpen: Set<String> { ScheduleScreenLogic.decodeSet(coloOpenText) }

    // MARK: - Events

    /// Opening a session hides the keyboard (Kotlin `focus.clearFocus()`).
    private func openSession(_ id: String) {
        searchFocused = false
        onOpenSession(id)
    }

    /// Kotlin `onTalk` (banner and "Up next" taps): clear the search, select the talk's day,
    /// open its co-located event's card (its agenda holds the talk), jump there, open the details.
    private func onTalk(_ index: ScheduleIndex, _ s: Session) {
        let tap = ScheduleScreenLogic.onTalk(index, s, coloOpen)
        searchText = ""
        selectedDay = tap.selectedDay
        coloOpenText = ScheduleScreenLogic.encodeSet(tap.coloOpen)
        jumpSerial += 1
        pendingJump = PendingJump(jump: tap.jump, serial: jumpSerial)
        openSession(s.id)
    }

    /// Kotlin `onDay`: clear the search, select the day, back to the top (web `window.scrollTo({top:0})`).
    private func onDay(_ proxy: ScrollViewProxy, _ key: String) {
        searchText = ""
        selectedDay = key
        Task { @MainActor in
            proxy.scrollTo(ScheduleRow.search.key, anchor: .top)
        }
    }

    private func expand(_ key: String) {
        var next = expanded
        next.insert(key)
        expandedText = ScheduleScreenLogic.encodeSet(next)
    }

    private func toggleColo(_ key: String) {
        coloOpenText = ScheduleScreenLogic.encodeSet(ScheduleScreenLogic.toggleColo(coloOpen, key))
    }

    /// Kotlin `onToggleGoing`: star / unstar; unstarred with the filter on, it stays listed.
    private func toggleGoing(_ id: String, _ unstarredKey: String) {
        let nowGoing: Bool = graph.going.toggle(id)
        let saved = ScheduleScreenLogic.SavedUnstarred.decode(unstarredText)
        let next = saved.afterToggle(id, nowGoing: nowGoing, goingOnly: goingOnly, currentKey: unstarredKey)
        if next != saved {
            unstarredText = next.encoded
        }
    }

    /// Kotlin `onHideColo`: hiding an agenda (often from its foot, ~2,000 pt below its card)
    /// collapses it and, if the card's head is above the screen, brings it back so the list
    /// doesn't land mid-section.
    private func hideColo(_ proxy: ScrollViewProxy, _ key: String) {
        let rows: [ScheduleRow] = memo.lastRows
        var open = coloOpen
        open.remove(key)
        coloOpenText = ScheduleScreenLogic.encodeSet(open)
        let i = ScheduleRows.indexOfColoCard(rows, key)
        let top: Double? = i >= 0 ? memo.rowTops[rows[i].key] : nil
        if let target = ScheduleScreenLogic.hideColoScrollTarget(rows, key, cardTop: top) {
            scrollToRow(proxy, rows[target].key, animated: false)
        }
    }

    /// A kid row being revealed after a jump scrolls itself into view (Kotlin `bringIntoView`).
    private func revealed(_ proxy: ScrollViewProxy, _ id: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(kidRowScrollId(id), anchor: nil)
        }
        revealId = nil
    }

    // MARK: - Banner jumps

    /// The jump's target in the current rows, if it is there yet (Kotlin `jumpIndex >= 0`).
    private func tryJump(_ proxy: ScrollViewProxy) {
        guard let p = pendingJump else { return }
        guard let i = ScheduleScreenLogic.jumpTarget(memo.lastRows, p.jump) else { return }
        pendingJump = nil
        land(proxy, i, p.jump)
    }

    /// Kotlin `withTimeoutOrNull(JUMP_WAIT_MS)`: if the target never shows, fall back to wherever
    /// the talk is now, or give up.
    private func waitForJump(_ proxy: ScrollViewProxy) async {
        guard let p = pendingJump else { return }
        try? await Task.sleep(nanoseconds: UInt64(ScheduleScreenLogic.JUMP_WAIT_MS) * 1_000_000)
        guard !Task.isCancelled, pendingJump == p else { return }
        pendingJump = nil
        if let i = ScheduleScreenLogic.jumpFallback(memo.lastRows, p.jump) {
            land(proxy, i, p.jump)
        }
    }

    /// Scroll to row `i` (under its pinned heading); then, if the talk is inside that row (a
    /// group card's kid, an agenda row), reveal it.
    private func land(_ proxy: ScrollViewProxy, _ i: Int, _ jump: ScheduleScreenLogic.Jump) {
        guard let row = memo.lastRows.getOrNull(i) else { return }
        let memo: ScheduleScreenMemo = memo
        scrollToRow(proxy, row.key, animated: true) {
            if ScheduleRows.revealsAfterJump(memo.lastRows.getOrNull(i), jump.id, coloOpen) {
                revealId = jump.id
            }
        }
    }

    /// Kotlin `scrollToItem(i, -stickyPx)`: the row's top lands ``ScheduleScreenLogic/STICKY_HEADING_HEIGHT``
    /// below the list's top, under its pinned heading. SwiftUI scrolls to the row's jump anchor
    /// (a view that ends at the row's top); a row not laid out yet is first scrolled to so the
    /// anchor exists. `then` runs once the scroll is done.
    private func scrollToRow(_ proxy: ScrollViewProxy, _ key: String, animated: Bool, then done: (@MainActor () -> Void)? = nil) {
        let anchor: String = ScheduleScreen.jumpAnchorId(key)
        let laidOut: Bool = memo.realized.contains(key)
        let animation: Animation? = animated ? .easeInOut(duration: 0.35) : nil
        let settle: UInt64 = animated ? 400_000_000 : 30_000_000
        Task { @MainActor in
            if !laidOut {
                withAnimation(animation) {
                    proxy.scrollTo(key, anchor: .top)
                }
                try? await Task.sleep(nanoseconds: settle)
            }
            withAnimation(animation) {
                proxy.scrollTo(anchor, anchor: .top)
            }
            if let done {
                if animated {
                    try? await Task.sleep(nanoseconds: settle)
                }
                done()
            }
        }
    }

    /// Scroll id of a row's jump anchor.
    fileprivate static func jumpAnchorId(_ rowKey: String) -> String { "jump-" + rowKey }
}

// MARK: - Helpers

/// What the rows of one render share.
private struct ListContext {
    let index: ScheduleIndex
    let st: ScheduleScreenLogic.State
    let layout: ScheduleScreenLogic.ListLayout
    let me: String?
    let goingIds: Set<String>
    let remindMinutes: Int
    let unstarredKey: String
    /// The session highlighted in the list (list–detail layout only).
    let highlight: String?
    let expanded: Set<String>
    let coloOpen: Set<String>
}

/// A banner jump waiting for its row (Kotlin's conflated `Channel<Jump>`: a new tap replaces it).
private struct PendingJump: Equatable {
    let jump: ScheduleScreenLogic.Jump
    let serial: Int
}

/// Kotlin's `remember` keys, as a cache: the screen state is recomputed only when an input
/// changes (the body also runs on every 15 s tick and on taps that change nothing here), the
/// rows only when the state, the column count or the open cards change. Also holds what the
/// scrolling measures (rows laid out, co-located card row tops). Not observable: writing it
/// never re-renders anything.
private final class ScheduleScreenMemo {
    struct Inputs: Equatable {
        let index: ObjectIdentifier
        let minute: Date
        let me: String?
        let selectedDay: String?
        let query: String
        let goingOnly: Bool
        let goingIds: Set<String>
        let unstarred: Set<String>
        let remindMinutes: Int
    }

    private struct RowsKey: Equatable {
        let generation: Int
        let columns: Int
        let open: Set<String>
    }

    private var inputs: Inputs?
    private var cached: ScheduleScreenLogic.State?
    private var generation = 0
    private var rowsKey: RowsKey?

    /// The rows of the latest render (Kotlin `rememberUpdatedState(rows)`).
    private(set) var lastRows: [ScheduleRow] = []
    /// ``lastRows`` in pinned sections.
    private(set) var lastSections: [ScheduleRowSection] = []
    /// Keys of the rows currently laid out (their jump anchors exist).
    var realized: Set<String> = []
    /// Last measured top of each co-located card row, relative to the list's top (points).
    var rowTops: [String: Double] = [:]

    func state(_ inputs: Inputs, _ index: ScheduleIndex) -> ScheduleScreenLogic.State {
        if let cached, self.inputs == inputs {
            return cached
        }
        let st = ScheduleScreenLogic.state(
            index,
            inputs.minute,
            inputs.me,
            selectedDay: inputs.selectedDay,
            query: inputs.query,
            goingOnly: inputs.goingOnly,
            goingIds: inputs.goingIds,
            unstarred: inputs.unstarred,
            remindMinutes: inputs.remindMinutes
        )
        self.inputs = inputs
        cached = st
        generation += 1
        return st
    }

    /// `st` must be the state ``state(_:_:)`` returned last.
    func rows(_ st: ScheduleScreenLogic.State, _ columns: Int, _ open: Set<String>) -> [ScheduleRow] {
        let key = RowsKey(generation: generation, columns: columns, open: open)
        if rowsKey == key {
            return lastRows
        }
        lastRows = st.rows(columns, open)
        lastSections = ScheduleRows.sections(lastRows)
        rowsKey = key
        return lastRows
    }
}

/// A 1 × 36 pt invisible view ending at its row's top edge: scrolling it to the list's top puts
/// the row ``ScheduleScreenLogic/STICKY_HEADING_HEIGHT`` below, under its pinned heading.
private struct JumpAnchor: View {
    let id: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: CGFloat(ScheduleScreenLogic.STICKY_HEADING_HEIGHT))
            .alignmentGuide(.top) { d in d[.bottom] }
            .id(id)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Records a row's top edge in the list's viewport (negative = scrolled past the top).
private struct RowTopReader: View {
    let key: String
    let memo: ScheduleScreenMemo

    var body: some View {
        GeometryReader { g in
            let top: CGFloat = g.frame(in: ScheduleScreen.listSpace).minY
            Color.clear
                .onAppear {
                    memo.rowTops[key] = Double(top)
                }
                .onChange(of: top) { _, y in
                    memo.rowTops[key] = Double(y)
                }
        }
        .accessibilityHidden(true)
    }
}
