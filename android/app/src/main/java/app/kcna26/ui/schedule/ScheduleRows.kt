package app.kcna26.ui.schedule

import androidx.compose.runtime.Immutable
import app.kcna26.going.GoingNext
import app.kcna26.schedule.Block
import app.kcna26.schedule.ColoCard
import app.kcna26.schedule.ColoText
import app.kcna26.schedule.DayView
import app.kcna26.schedule.GroupBlock
import app.kcna26.schedule.MineBanner
import app.kcna26.schedule.SearchResults
import app.kcna26.schedule.SessionBlock
import app.kcna26.schedule.Slot

/**
 * The schedule list flattened into LazyColumn rows, in the web's order:
 * search box, "You’re speaking" banner, my starred "Up next" row (today), then
 * either the search results or the
 * day (heading, the "Co-located events" cards on Monday, half-hour
 * blocks with the "Up next" line, off-site section), then the footer.
 * Pure: unit-tested in ScheduleRowsTest.
 */
@Immutable
internal sealed interface Row {
    /** Stable LazyColumn key. */
    val key: String
    /** LazyColumn content type, so compositions are reused between rows of the same kind. */
    val type: Int
    val sticky: Boolean get() = false

    data object Search : Row {
        override val key = "search"
        override val type = 0
    }

    data class Banner(val banner: MineBanner) : Row {
        override val key = "mine"
        override val type = 1
    }

    data class DayHead(val view: DayView) : Row {
        override val key = "dayhead"
        override val type = 2
    }

    /** Sticky heading of a named section (co-located/off-site, or a day in search results). */
    data class Section(override val key: String, val title: String) : Row {
        override val type = 4
        override val sticky = true
    }

    /** Sticky half-hour block heading. */
    data class SlotHead(val slot: Slot) : Row {
        override val key = "slot-${slot.dayKey}-${slot.key}"
        override val type = 5
        override val sticky = true
    }

    data object UpNext : Row {
        override val key = "upnext"
        override val type = 6
    }

    /** A session card, a break row or a group card. [inSearch] cards come from search results. */
    data class Item(val block: Block, val inSearch: Boolean = false) : Row {
        override val key = (if (inSearch) "q" else "") + block.key
        override val type = when {
            block is GroupBlock -> 7
            block is SessionBlock && block.category == "log" -> 8
            else -> 9
        }
    }

    data class SearchHead(val heading: String) : Row {
        override val key = "qhead"
        override val type = 10
    }

    data class Empty(val title: String, val text: String) : Row {
        override val key = "empty"
        override val type = 11
    }

    data object Footer : Row {
        override val key = "footer"
        override val type = 12
    }

    /**
     * One row of co-located event cards: one card, or two side by side in a wide list column
     * ([ScheduleRows.coloColumns]). Keyed by its leading card, so the key survives a re-chunk (a
     * card leaving when its event ends, a different column count) and the list keeps its place.
     */
    data class Colo(val cards: List<ColoCard>) : Row {
        override val key = "colo-" + cards.first().key
        override val type = 13
    }

    /**
     * An open event's agenda, right under its card's row. [attached]: one card per row, so the
     * agenda continues that card; otherwise (two per row) it's a full-width panel of its own.
     */
    data class ColoAgenda(val card: ColoCard, val attached: Boolean) : Row {
        override val key = "colo-agenda-" + card.key
        override val type = 14
    }

    /** My next (or live) starred session today (type 20: clear of the co-located rows' 13 and 14). */
    data class GoingNext(val next: app.kcna26.going.GoingNext) : Row {
        override val key = "goingnext"
        override val type = 20
    }
}

internal object ScheduleRows {
    const val WRAP_TITLE = "That’s a wrap for today"
    const val WRAP_TEXT = "Pick the next day above."
    const val NO_MATCHES_TITLE = "No matches"
    const val NO_MATCHES_TEXT = "Try a project, a speaker, or a room like “255 A”."

    /**
     * Narrowest list content (dp) that gets co-located cards two to a row. Below it a tile is too
     * narrow to read: the unfolded list–detail pane is ~400 dp (368 dp of content), narrower
     * than the cover screen, so both get one card per row and the same rows.
     */
    const val COLO_TWO_UP_MIN_DP = 560f

    /** Co-located cards per row for a list column with [contentWidthDp] of content. */
    fun coloColumns(contentWidthDp: Float): Int = if (contentWidthDp >= COLO_TWO_UP_MIN_DP) 2 else 1

    /**
     * Builds the rows. [search] non-null means search mode (the day, banner and [goingNext]
     * are not shown). [empty] is the Going filter's note: it replaces the "That’s a wrap" /
     * "No matches" state, or follows the list when that isn't empty (only my talks are left).
     * Co-located cards go [coloColumns] to a row; [coloOpen] holds the event keys whose agenda is open.
     */
    fun build(
        view: DayView?,
        banner: MineBanner?,
        search: SearchResults?,
        coloColumns: Int = 1,
        coloOpen: Set<String> = emptySet(),
        goingNext: GoingNext? = null,
        empty: Row.Empty? = null,
    ): List<Row> {
        val rows = ArrayList<Row>(160)
        rows += Row.Search
        if (search != null) {
            rows += Row.SearchHead(search.heading)
            for (d in search.days) {
                rows += Row.Section("q-${d.day.key}", d.day.label)
                for (b in d.sessions) rows += Row.Item(b, inSearch = true)
            }
            if (search.count == 0) rows += empty ?: Row.Empty(NO_MATCHES_TITLE, NO_MATCHES_TEXT) else if (empty != null) rows += empty
        } else {
            if (banner != null) rows += Row.Banner(banner)
            if (goingNext != null) rows += Row.GoingNext(goingNext)
            if (view != null) {
                rows += Row.DayHead(view)
                addColo(rows, view, coloColumns.coerceAtLeast(1), coloOpen)
                if (view.longsFirst) addLongs(rows, view)
                view.slots.forEachIndexed { i, sl ->
                    if (i == view.upNextBefore) rows += Row.UpNext
                    rows += Row.SlotHead(sl)
                    for (b in sl.blocks) rows += Row.Item(b)
                }
                if (!view.longsFirst) addLongs(rows, view)
                if (view.isEmpty) rows += empty ?: Row.Empty(WRAP_TITLE, WRAP_TEXT) else if (empty != null) rows += empty
            }
        }
        rows += Row.Footer
        return rows
    }

    private fun addColo(rows: MutableList<Row>, view: DayView, columns: Int, open: Set<String>) {
        if (view.colo.isEmpty()) return
        rows += Row.Section("colo-${view.day.key}", ColoText.SECTION)
        for (cards in view.colo.chunked(columns)) {
            rows += Row.Colo(cards)
            for (c in cards) if (c.key in open) rows += Row.ColoAgenda(c, attached = columns == 1)
        }
    }

    private fun addLongs(rows: MutableList<Row>, view: DayView) {
        if (view.longs.isEmpty()) return
        rows += Row.Section("long-${view.day.key}", view.longsTitle)
        for (b in view.longs) rows += Row.Item(b)
    }

    /**
     * Index of the row showing [sessionId] (its own card, the group card it's in, or the open
     * agenda of its co-located event, else that event's card), or -1.
     */
    fun indexOfSession(rows: List<Row>, sessionId: String): Int {
        val i = rows.indexOfFirst { r ->
            when (r) {
                is Row.Item -> when (val b = r.block) {
                    is SessionBlock -> b.session.id == sessionId
                    is GroupBlock -> b.kids.any { it.id == sessionId }
                }
                is Row.ColoAgenda -> r.card.holds(sessionId)
                else -> false
            }
        }
        if (i >= 0) return i
        return rows.indexOfFirst { r -> r is Row.Colo && r.cards.any { it.holds(sessionId) } }
    }

    /**
     * Where a banner jump to [sessionId] lands, or -1 to keep waiting for the rows. [agenda]: the
     * co-located event whose card the tap has just opened. Its talk is only revealed from the open
     * agenda, and the jump's first look is at the rows from before the tap (card still collapsed),
     * so it waits for that event's [Row.ColoAgenda] rather than settling on the card head.
     */
    fun jumpIndex(rows: List<Row>, sessionId: String, agenda: String?): Int {
        if (agenda == null) return indexOfSession(rows, sessionId)
        return rows.indexOfFirst { it is Row.ColoAgenda && it.card.key == agenda && it.card.holds(sessionId) }
    }

    /**
     * After a jump lands on [row], [sessionId] is inside it and must be scrolled into view itself:
     * a group card's kid, an open agenda's row, or (the timeout fallback) the head of a card whose
     * agenda is [open], composed right under it.
     */
    fun revealsAfterJump(row: Row?, sessionId: String, open: Set<String>): Boolean = when (row) {
        is Row.Item -> (row.block as? GroupBlock)?.kids?.any { it.id == sessionId } == true
        is Row.ColoAgenda -> row.card.holds(sessionId)
        is Row.Colo -> row.cards.any { it.key in open && it.holds(sessionId) }
        else -> false
    }

    /** Index of the [Row.Colo] showing event [key]'s card, or -1. */
    fun indexOfColoCard(rows: List<Row>, key: String): Int =
        rows.indexOfFirst { r -> r is Row.Colo && r.cards.any { it.key == key } }
}
