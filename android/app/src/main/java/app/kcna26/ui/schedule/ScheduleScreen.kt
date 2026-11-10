package app.kcna26.ui.schedule

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.data.Session
import app.kcna26.going.GoingLogic
import app.kcna26.schedule.GroupBlock
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.schedule.ScheduleLogic
import app.kcna26.schedule.SessionBlock
import app.kcna26.theme.Dimens
import app.kcna26.time.rememberNowState
import app.kcna26.ui.adaptive.LocalWidthClass
import app.kcna26.ui.going.GOING_CHANNEL
import app.kcna26.ui.going.GoingChip
import app.kcna26.ui.going.GoingNextCard
import app.kcna26.ui.going.NotificationsOffHint
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The home screen: brand + clock and day tabs on top, then one scrolling column
 * with the search box, the pinned "You’re speaking" banner, the day heading and
 * today's status, half-hour blocks of cards
 * (sticky block headings, "Up next" line, group cards, quiet break rows) or the
 * search results, and the footer. Port of schedule_app.js `render`.
 *
 * State that survives fold/unfold and process death: the selected day, the
 * search text, expanded groups, open co-located event cards, the "Going" filter
 * (rememberSaveable) and the scroll position (rememberLazyListState). The stars live
 * in `graph.going`. The shell keeps this call at one composition position in both layouts.
 *
 * Monday's co-located events are cards above the blocks (see ColocatedCards.kt): one
 * per row, or two in a list column of ≥ 560 dp ([ScheduleRows.coloColumns]). The
 * unfolded list–detail pane (~400 dp) is narrower than the cover screen, so both get
 * one per row: the same rows, so the restored scroll index means the same row.
 *
 * Insets: the shell applied the horizontal ones; this screen pads the top
 * (status bar) in the header and the bottom (navigation bar, keyboard) in the list.
 *
 * @param selectedSessionId session open in the details pane/sheet; highlighted in two-pane mode.
 * @param onOpenSession open a session's details (sheet on compact, pane on wide).
 * @param onOpenDirections full-screen Directions for a session (the "Up next" row's shortcut; the details have the button).
 * @param onOpenSettings open the Settings screen.
 * @param twoPane true when this is the ~400 dp list pane of the unfolded list–detail layout.
 */
@Composable
fun ScheduleScreen(
    selectedSessionId: String?,
    onOpenSession: (sessionId: String) -> Unit,
    onOpenDirections: (sessionId: String) -> Unit,
    onOpenSettings: () -> Unit,
    twoPane: Boolean,
    modifier: Modifier = Modifier,
) {
    val graph = LocalAppGraph.current
    val repo = graph.repository
    val index = remember(repo) { ScheduleIndex.of(repo) }
    LaunchedEffect(index) { withContext(Dispatchers.Default) { index.prewarmSearch() } }
    val me by graph.settings.speakingAs.collectAsStateWithLifecycle()

    // The schedule only changes once a minute: recompute on minute boundaries, not every 15 s tick.
    val nowState = rememberNowState(graph.clock)
    val minute by remember(nowState) { derivedStateOf { ScheduleLogic.minuteOf(nowState.value) } }

    var selectedDay by rememberSaveable { mutableStateOf<String?>(null) }
    val search = rememberTextFieldState()
    val query by remember(search) { derivedStateOf { search.text.toString().trim() } }
    var expanded by rememberSaveable(saver = StringSetSaver) { mutableStateOf(emptySet<String>()) }
    var coloOpen by rememberSaveable(saver = StringSetSaver) { mutableStateOf(emptySet<String>()) }
    // "Going": stars (persisted in graph.going) and the day header's filter chip (saveable).
    val goingStore = graph.going
    val goingIds by goingStore.ids.collectAsStateWithLifecycle()
    val remindMinutes by goingStore.remindMinutes.collectAsStateWithLifecycle()
    var goingOnly by rememberSaveable { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val searching = query.isNotEmpty()

    val dayKey = remember(index, minute, selectedDay) { ScheduleLogic.resolveDayKey(index.days, minute, selectedDay) }
    val tabs = remember(index, minute, me) { index.dayTabs(minute, me) }
    val clock = remember(index, minute) { ScheduleLogic.clockLabel(index.days, minute) }
    val fullView = remember(index, dayKey, minute, me, searching) {
        if (searching || dayKey == null) null else index.dayView(dayKey, minute, me)
    }
    val banner = remember(index, dayKey, minute, me, searching) { index.banner(dayKey, minute, me, searching) }
    val allResults = remember(index, query, minute, me) { if (query.isEmpty()) null else index.search(query, minute, me) }
    // Unstarred while the filter is on: stays listed (outlined star, so a stray tap is undone in place)
    // until the filter is toggled or the day changes.
    val unstarred = rememberSaveable(goingOnly, dayKey, saver = StringSetSaver) { mutableStateOf(emptySet<String>()) }
    val keepGoing: (Session) -> Boolean = remember(goingIds, me, unstarred.value) {
        val kept = unstarred.value
        { s -> GoingLogic.keeps(s, goingIds, me) || s.id in kept }
    }
    val view = remember(fullView, goingOnly, keepGoing, minute) {
        if (goingOnly && fullView != null) GoingLogic.filterDay(fullView, minute, keepGoing) else fullView
    }
    val results = remember(allResults, goingOnly, keepGoing) {
        if (goingOnly && allResults != null) GoingLogic.filterSearch(allResults, keepGoing) else allResults
    }
    val goingNext = remember(index, dayKey, minute, goingIds, me, searching) {
        if (searching) null else GoingLogic.upNext(index, dayKey, goingIds, me, minute)
    }
    val clashIds = remember(index, goingIds, me, minute) { GoingLogic.clashes(index, goingIds, me, minute).keys }
    val goingEmpty = remember(goingOnly, fullView, view, allResults, results, goingIds, index, minute, remindMinutes) {
        GoingLogic.emptyText(goingOnly, fullView, view, allResults, results, index, goingIds, minute, remindMinutes)
            ?.let { (title, text) -> Row.Empty(title, text) }
    }

    // Banner taps jump to the talk in the list (web data-jump), then open it. The jump waits for the
    // new day's rows (the tap also switches day and clears search); a drag simply interrupts it.
    // The rows are built below, where the list column's width is known.
    val jumps = remember { Channel<Jump>(Channel.CONFLATED) }
    var revealId by remember { mutableStateOf<String?>(null) }
    val stickyPx = with(LocalDensity.current) { STICKY_HEADING_HEIGHT.roundToPx() }

    // Back with the keyboard up only hides the keyboard (the query and its results stay);
    // a second Back clears the search. Without the IME check this handler, registered
    // when the first letter is typed, would run before the keyboard's own Back.
    val keyboard = LocalSoftwareKeyboardController.current
    val imeInsets = WindowInsets.ime
    val density = LocalDensity.current
    val imeUp by remember(imeInsets, density) { derivedStateOf { imeInsets.getBottom(density) > 0 } }
    BackHandler(enabled = searching || imeUp) {
        if (imeUp) {
            keyboard?.hide()
            focus.clearFocus()
        } else {
            search.clearText()
        }
    }

    val openSession: (String) -> Unit = remember(onOpenSession, focus) {
        { id ->
            focus.clearFocus()
            onOpenSession(id)
        }
    }
    val onTalk: (Session) -> Unit = { s ->
        search.clearText()
        selectedDay = s.day
        // A co-located talk is inside its event's card: open the card's agenda; the jump waits for it.
        val event = index.coloEventOf(s)?.key
        if (event != null) coloOpen = coloOpen + event
        jumps.trySend(Jump(s.id, event))
        openSession(s.id)
    }
    val onDay: (String) -> Unit = { key ->
        search.clearText()
        selectedDay = key
        scope.launch { listState.scrollToItem(0) } // web: window.scrollTo({top:0})
    }
    val onExpand: (String) -> Unit = { key -> expanded = expanded + key }
    val onToggleColo: (String) -> Unit = { key -> coloOpen = if (key in coloOpen) coloOpen - key else coloOpen + key }
    val onToggleGoing: (String) -> Unit = remember(goingStore, goingOnly, unstarred) {
        { id -> if (!goingStore.toggle(id) && goingOnly) unstarred.value += id }
    }
    val goingChip: @Composable () -> Unit = { GoingChip(goingOnly, onToggle = { goingOnly = !goingOnly }) }
    val highlight = if (twoPane) selectedSessionId else null
    val wideWindow = LocalWidthClass.current.isWide
    val bottom = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()

    BoxWithConstraints(modifier.fillMaxSize()) {
        // One centred column, at most 760 dp (web .wrap); 16 dp margins on phones and in the list pane.
        val side = max(Dimens.pagePadding, (maxWidth - Dimens.maxContentWidth) / 2)
        val roomy = !twoPane && maxWidth >= 640.dp
        val large = roomy && wideWindow
        // Co-located cards two to a row only when the list column itself is wide (not the window).
        val coloColumns = ScheduleRows.coloColumns((maxWidth - side * 2).value)
        val rows = remember(view, banner, results, coloColumns, coloOpen, goingNext, goingEmpty) {
            ScheduleRows.build(view, banner, results, coloColumns, coloOpen, goingNext, goingEmpty)
        }
        val latestRows = rememberUpdatedState(rows)
        LaunchedEffect(listState, stickyPx) {
            for (j in jumps) {
                // A co-located talk: wait for its just-opened agenda (the first look sees the rows from
                // before the tap). If it never shows, fall back to wherever the talk is now.
                val i = withTimeoutOrNull(JUMP_WAIT_MS) {
                    snapshotFlow { ScheduleRows.jumpIndex(latestRows.value, j.id, j.agenda) }.first { it >= 0 }
                } ?: ScheduleRows.indexOfSession(latestRows.value, j.id).takeIf { it >= 0 } ?: continue
                try {
                    listState.animateScrollToItem(i, -stickyPx)
                    if (ScheduleRows.revealsAfterJump(latestRows.value.getOrNull(i), j.id, coloOpen)) revealId = j.id
                } catch (e: CancellationException) {
                    if (!currentCoroutineContext().isActive) throw e // screen left; otherwise the user scrolled
                }
            }
        }
        // Hiding an agenda (often from its foot, ~2,000 dp below its card): collapse it and, if
        // the card's head is above the screen, bring it back so the list doesn't land mid-section.
        val onHideColo: (String) -> Unit = { key ->
            coloOpen = coloOpen - key
            val i = ScheduleRows.indexOfColoCard(rows, key)
            val first = listState.firstVisibleItemIndex
            if (i >= 0 && (i < first || (i == first && listState.firstVisibleItemScrollOffset > 0))) {
                scope.launch { listState.scrollToItem(i, -stickyPx) }
            }
        }
        Column(Modifier.fillMaxSize()) {
            ScheduleHeader(
                clock = clock,
                tabs = tabs,
                currentDay = dayKey,
                searching = searching,
                sidePadding = side,
                onDay = onDay,
                onSettings = onOpenSettings,
            )
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = side, end = side, bottom = bottom + 16.dp),
            ) {
                for (r in rows) {
                    if (r.sticky) {
                        stickyHeader(key = r.key, contentType = r.type) {
                            when (r) {
                                is Row.SlotHead -> RuledHeading(r.slot.label)
                                is Row.Section -> RuledHeading(r.title, topPadding = 16.dp)
                                else -> Unit
                            }
                        }
                        continue
                    }
                    item(key = r.key, contentType = r.type) {
                        when (r) {
                            Row.Search -> ScheduleSearchField(search)
                            is Row.Banner -> MineBannerCard(r.banner, onTalk)
                            is Row.GoingNext -> Column {
                                GoingNextCard(
                                    r.next,
                                    onOpen = { onTalk(r.next.session) },
                                    onDirections = { onOpenDirections(r.next.session.id) },
                                )
                                // Its reminder can't reach me: say so right here (hidden when notifications are on).
                                if (!r.next.live && remindMinutes > 0) NotificationsOffHint(GOING_CHANNEL, Modifier.padding(top = 6.dp))
                            }
                            is Row.DayHead -> DayHeading(r.view, large, trailing = goingChip)
                            Row.UpNext -> UpNextLine()
                            is Row.SearchHead -> SearchHeading(r.heading, large, trailing = goingChip)
                            is Row.Empty -> EmptyState(r.title, r.text)
                            Row.Footer -> ScheduleFooter()
                            is Row.Item -> when (val b = r.block) {
                                is SessionBlock ->
                                    if (b.category == "log") {
                                        BreakRow(b.session, index, Modifier.padding(bottom = Dimens.cardGap))
                                    } else {
                                        SessionCard(
                                            block = b,
                                            status = index.cardStatus(b.session, minute),
                                            me = me,
                                            index = index,
                                            selected = b.session.id == highlight,
                                            wide = roomy,
                                            onOpen = openSession,
                                            modifier = Modifier.padding(bottom = Dimens.cardGap),
                                            going = b.session.id in goingIds,
                                            clash = b.session.id in clashIds,
                                            onToggleGoing = onToggleGoing,
                                        )
                                    }
                                is GroupBlock -> GroupCard(
                                    block = b,
                                    now = minute,
                                    me = me,
                                    index = index,
                                    expanded = b.group.key in expanded,
                                    selectedId = highlight,
                                    revealId = revealId,
                                    wide = roomy,
                                    onExpand = onExpand,
                                    onOpen = openSession,
                                    onRevealed = { revealId = null },
                                    modifier = Modifier.padding(bottom = Dimens.cardGap),
                                    goingIds = goingIds,
                                    clashIds = clashIds,
                                    onToggleGoing = onToggleGoing,
                                )
                            }
                            is Row.Colo -> ColoCardRow(
                                cards = r.cards,
                                columns = coloColumns,
                                open = coloOpen,
                                index = index,
                                onToggle = onToggleColo,
                            )
                            is Row.ColoAgenda -> ColoAgendaCard(
                                card = r.card,
                                attached = r.attached,
                                me = me,
                                index = index,
                                selectedId = highlight,
                                revealId = revealId,
                                onHide = onHideColo,
                                onOpen = openSession,
                                onRevealed = { revealId = null },
                                goingIds = goingIds,
                                clashIds = clashIds,
                                onToggleGoing = onToggleGoing,
                            )
                            is Row.Section, is Row.SlotHead -> Unit
                        }
                    }
                }
            }
        }
    }
}

/** A banner jump to [id]; [agenda]: the co-located event whose card the tap opened (its agenda holds the talk). */
private data class Jump(val id: String, val agenda: String?)

/** How long a banner jump waits for its target row to appear. */
private const val JUMP_WAIT_MS = 2_000L

/** Height of a sticky block heading, so a jumped-to card isn't hidden under it. */
private val STICKY_HEADING_HEIGHT = 36.dp

/** Saves the set of expanded group keys across fold/unfold and process death. */
private val StringSetSaver: Saver<MutableState<Set<String>>, Any> = listSaver(
    save = { ArrayList(it.value) },
    restore = { mutableStateOf(it.toSet()) },
)
