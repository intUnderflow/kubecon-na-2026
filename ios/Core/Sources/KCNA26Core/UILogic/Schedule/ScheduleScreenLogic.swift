import Foundation

/// The pure parts of Kotlin ui/schedule/ScheduleScreen.kt (the home screen, web `render`): the
/// chain of derived values the composable keeps in `remember`s, its event reducers and the
/// banner-jump rules, so the SwiftUI `ScheduleScreen` keeps only state and layout.
///
/// Screen state (Kotlin `rememberSaveable`; SwiftUI `@SceneStorage` / `@State`): the selected
/// day (`String?`), the search text, expanded group keys, open co-located event keys
/// (`coloOpen`), the RSVP'd filter (`goingOnly`) and `unstarred` (reset whenever `goingOnly` or
/// the day changes). Stars live in `GoingStore`, "me" in `SettingsStore`.
///
/// ```swift
/// let minute = ScheduleLogic.minuteOf(ticker.now)      // the schedule changes once a minute
/// let st = ScheduleScreenLogic.state(index, minute, settings.speakingAs, selectedDay: selectedDay,
///     query: ScheduleScreenLogic.query(searchText), goingOnly: goingOnly, goingIds: going.ids,
///     unstarred: unstarred, remindMinutes: going.remindMinutes)
/// let layout = ScheduleScreenLogic.listLayout(width, twoPane: twoPane, wideWindow: widthClass.isWide)
/// let rows = st.rows(layout.coloColumns, coloOpen)
/// ```
enum ScheduleScreenLogic {
    /// A banner jump to `id` (Kotlin's private `Jump`); `agenda`: the co-located event whose card
    /// the tap opened (its agenda holds the talk).
    struct Jump: Sendable, Hashable {
        let id: String
        let agenda: String?

        init(_ id: String, _ agenda: String?) {
            self.id = id
            self.agenda = agenda
        }
    }

    /// How long a banner jump waits for its target row to appear (ms).
    static let JUMP_WAIT_MS: Int64 = 2_000

    /// Height of a sticky block heading (points), so a jumped-to card isn't hidden under it:
    /// scroll to the row with this much offset (Kotlin `animateScrollToItem(i, -stickyPx)`).
    static let STICKY_HEADING_HEIGHT: Double = 36

    /// The search query: the field's text, trimmed (Kotlin `search.text.toString().trim()`).
    /// Searching = a non-empty query.
    static func query(_ searchText: String) -> String { searchText.kotlinTrim() }

    /// The RSVP'd filter's keep rule (Kotlin `keepGoing`): starred, mine, or unstarred while the
    /// filter is on (stays listed with an outlined star, so a stray tap is undone in place, until
    /// the filter is toggled or the day changes).
    static func keepGoing(_ goingIds: Set<String>, _ me: String?, _ unstarred: Set<String>) -> @Sendable (Session) -> Bool {
        { s in GoingLogic.keeps(s, goingIds, me) || unstarred.contains(s.id) }
    }

    /// Everything the screen derives from its inputs (Kotlin's `remember` chain), at one minute.
    struct State: Sendable, Hashable {
        /// The minute everything was computed at (Kotlin `minute`).
        let minute: Date
        let searching: Bool
        /// The day shown (``ScheduleLogic/resolveDayKey(_:_:_:)``); nil only without days.
        let dayKey: String?
        let tabs: [DayTab]
        /// Header clock: "9:05 AM MST" / "Times in MST".
        let clock: String
        /// The whole day (nil while searching).
        let fullView: DayView?
        let banner: MineBanner?
        /// Search results before the RSVP'd filter (nil when not searching).
        let allResults: SearchResults?
        /// The day as listed (filtered when `goingOnly`).
        let view: DayView?
        /// The results as listed (filtered when `goingOnly`).
        let results: SearchResults?
        /// The "Up next" (RSVP) row; nil while searching.
        let goingNext: GoingNext?
        /// Starred sessions that clash (their cards get the "Clash" tag).
        let clashIds: Set<String>
        /// The RSVP'd filter's note, or nil.
        let goingEmpty: ScheduleRow.Empty?

        /// The list rows (``ScheduleRows/build(_:_:_:_:_:goingNext:empty:)``).
        func rows(_ coloColumns: Int, _ coloOpen: Set<String>) -> [ScheduleRow] {
            ScheduleRows.build(view, banner, results, coloColumns, coloOpen, goingNext: goingNext, empty: goingEmpty)
        }
    }

    /// Kotlin ScheduleScreen's derived values. `now` is truncated to the minute.
    static func state(
        _ index: ScheduleIndex,
        _ now: Date,
        _ me: String?,
        selectedDay: String?,
        query: String,
        goingOnly: Bool,
        goingIds: Set<String>,
        unstarred: Set<String>,
        remindMinutes: Int
    ) -> State {
        let minute = ScheduleLogic.minuteOf(now)
        let searching = !query.isEmpty
        let dayKey = ScheduleLogic.resolveDayKey(index.days, minute, selectedDay)
        let fullView: DayView? = searching ? nil : dayKey.flatMap { index.dayView($0, minute, me) }
        let banner = index.banner(dayKey, minute, me, searching: searching)
        let allResults: SearchResults? = query.isEmpty ? nil : index.search(query, minute, me)
        let keep = keepGoing(goingIds, me, unstarred)
        let view: DayView? = goingOnly ? fullView.map { GoingLogic.filterDay($0, minute, keep) } : fullView
        let results: SearchResults? = goingOnly ? allResults.map { GoingLogic.filterSearch($0, keep) } : allResults
        let goingNext: GoingNext? = searching ? nil : GoingLogic.upNext(index, dayKey, goingIds, me, minute)
        let clashIds = Set(GoingLogic.clashes(index, goingIds, me, minute).keys)
        let note = GoingLogic.emptyText(goingOnly, fullView, view, allResults, results, index, goingIds, minute, remindMinutes)
        return State(
            minute: minute,
            searching: searching,
            dayKey: dayKey,
            tabs: index.dayTabs(minute, me),
            clock: ScheduleLogic.clockLabel(index.days, minute),
            fullView: fullView,
            banner: banner,
            allResults: allResults,
            view: view,
            results: results,
            goingNext: goingNext,
            clashIds: clashIds,
            goingEmpty: note.map { ScheduleRow.Empty($0.title, $0.text) }
        )
    }

    /// The list column's layout (Kotlin's `BoxWithConstraints` block), from the screen's width.
    struct ListLayout: Sendable, Hashable {
        /// Side padding: one centred column of at most 760 pt (web `.wrap`), 16 pt margins on phones.
        let side: Double
        /// A roomy list (not the list pane, ≥ 640 pt): wide cards (17 pt titles).
        let roomy: Bool
        /// Roomy in a wide window: the large day / search headings (36 pt).
        let large: Bool
        /// Co-located cards per row, from the list column itself (not the window).
        let coloColumns: Int
    }

    static func listLayout(_ maxWidth: Double, twoPane: Bool, wideWindow: Bool) -> ListLayout {
        let side = max(Dimens.pagePadding, (maxWidth - Dimens.maxContentWidth) / 2)
        let roomy = !twoPane && maxWidth >= 640
        return ListLayout(
            side: side,
            roomy: roomy,
            large: roomy && wideWindow,
            coloColumns: ScheduleRows.coloColumns(maxWidth - side * 2)
        )
    }

    /// The session highlighted in the list: the open one, in the list–detail layout only.
    static func highlight(twoPane: Bool, _ selectedSessionId: String?) -> String? { twoPane ? selectedSessionId : nil }

    /// What a banner talk tap does (Kotlin `onTalk`): clear the search, select the talk's day,
    /// open its co-located event's card (the agenda holds the talk), send ``jump``, then open the
    /// details.
    struct TalkTap: Sendable, Hashable {
        let selectedDay: String
        let coloOpen: Set<String>
        let jump: Jump
    }

    static func onTalk(_ index: ScheduleIndex, _ s: Session, _ coloOpen: Set<String>) -> TalkTap {
        let event = index.coloEventOf(s)?.key
        var open = coloOpen
        if let event { open.insert(event) }
        return TalkTap(selectedDay: s.day, coloOpen: open, jump: Jump(s.id, event))
    }

    /// Kotlin `onToggleColo`: open or close event `key`'s agenda.
    static func toggleColo(_ open: Set<String>, _ key: String) -> Set<String> {
        var next = open
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        return next
    }

    /// Kotlin `onToggleGoing`: after `GoingStore.toggle(id)` returned `nowGoing`, a session
    /// unstarred while the filter is on stays listed.
    static func unstarredAfterToggle(_ unstarred: Set<String>, _ id: String, nowGoing: Bool, goingOnly: Bool) -> Set<String> {
        if !nowGoing && goingOnly {
            var next = unstarred
            next.insert(id)
            return next
        }
        return unstarred
    }

    /// The banner jump (Kotlin's `LaunchedEffect` over the jumps): wait up to ``JUMP_WAIT_MS``
    /// for ``jumpTarget(_:_:)`` (re-check on every rows change), else use
    /// ``jumpFallback(_:_:)``, else give up. Scroll there with ``STICKY_HEADING_HEIGHT`` of
    /// offset; then, if ``ScheduleRows/revealsAfterJump(_:_:_:)``, set `revealId = jump.id` (the
    /// kid / agenda row scrolls itself into view and clears it). A user scroll cancels the jump.
    static func jumpTarget(_ rows: [ScheduleRow], _ jump: Jump) -> Int? {
        let i = ScheduleRows.jumpIndex(rows, jump.id, jump.agenda)
        return i >= 0 ? i : nil
    }

    /// The timeout fallback: wherever the talk is now, or nil.
    static func jumpFallback(_ rows: [ScheduleRow], _ jump: Jump) -> Int? {
        let i = ScheduleRows.indexOfSession(rows, jump.id)
        return i >= 0 ? i : nil
    }

    /// Hiding an agenda (often from its foot, ~2,000 pt below its card): after collapsing it,
    /// the row to scroll back to when the card's head is above the screen (so the list doesn't
    /// land mid-section), else nil. `rows`: the rows before the collapse; the list's first
    /// visible row and how far it is scrolled past that row's top.
    static func hideColoScrollTarget(_ rows: [ScheduleRow], _ key: String, firstVisibleIndex: Int, firstVisibleOffset: Double) -> Int? {
        let i = ScheduleRows.indexOfColoCard(rows, key)
        if i >= 0 && (i < firstVisibleIndex || (i == firstVisibleIndex && firstVisibleOffset > 0)) { return i }
        return nil
    }

    /// Under the "Up next" row: the notifications-off hint (hidden when notifications are on),
    /// when its reminder is still to come.
    static func goingNextShowsHint(_ next: GoingNext, _ remindMinutes: Int) -> Bool { !next.live && remindMinutes > 0 }
}
