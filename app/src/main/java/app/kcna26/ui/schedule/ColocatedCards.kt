package app.kcna26.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.kcna26.schedule.ColoCard
import app.kcna26.schedule.ColoItem
import app.kcna26.schedule.ColoLine
import app.kcna26.schedule.ColoText
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.theme.AppColors
import app.kcna26.theme.AppTheme
import app.kcna26.theme.Barlow
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.theme.caps
import app.kcna26.time.TimeFormat

/*
 * The "Co-located events" section (Monday): one compact card per CNCF-hosted co-located event,
 * in the look of the web's `.card` (category stripe in the colo colour, Barlow uppercase name),
 * with a glanceable live line. Tapping a card opens its agenda inline: with one card per row
 * (the cover screen and the unfolded list pane) the card grows downwards (a [Row.ColoAgenda]
 * item drawn as the card's continuation); in a list column wide enough for two to a row
 * (ScheduleRows.coloColumns) an open agenda is a full-width panel right under its row, so
 * neither tile moves. An agenda can be hidden from its foot as well as from its card.
 */

/** One row of event cards: one card ([tile] = false) or two side by side ([tile] = true). */
@Composable
internal fun ColoCardRow(
    cards: List<ColoCard>,
    columns: Int,
    open: Set<String>,
    index: ScheduleIndex,
    onToggle: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (columns <= 1) {
        val card = cards.first()
        val isOpen = card.key in open
        ColoEventCard(
            card = card,
            open = isOpen,
            tile = false,
            attachedBelow = isOpen,
            index = index,
            onToggle = onToggle,
            modifier = modifier.padding(bottom = if (isOpen) 0.dp else Dimens.cardGap),
        )
        return
    }
    Row(
        modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .padding(bottom = Dimens.cardGap),
        horizontalArrangement = Arrangement.spacedBy(Dimens.cardGap),
    ) {
        for (card in cards) {
            ColoEventCard(
                card = card,
                open = card.key in open,
                tile = true,
                attachedBelow = false,
                index = index,
                onToggle = onToggle,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
            )
        }
        repeat(columns - cards.size) { Spacer(Modifier.weight(1f)) }
    }
}

/**
 * The collapsed card: event name, main room · building, hours (+ "You" / "Anthropic" markers),
 * and the live line ("Starts …", "Now …", "Next …"). The whole card toggles the agenda.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColoEventCard(
    card: ColoCard,
    open: Boolean,
    tile: Boolean,
    attachedBelow: Boolean,
    index: ScheduleIndex,
    onToggle: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val e = card.event
    val colo = c.category("colo")
    val r = Dimens.cardRadius
    val shape = if (attachedBelow) RoundedCornerShape(topStart = r, topEnd = r) else RoundedCornerShape(r)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .cardSegment(
                fill = c.surface,
                border = coloBorder(card, c),
                stripe = colo,
                top = true,
                bottom = !attachedBelow,
                ring = if (open && tile) colo else null,
            )
            .semantics { stateDescription = if (open) "Agenda shown" else "Agenda hidden" }
            .clickable(role = Role.Button, onClickLabel = if (open) "Hide agenda" else "Show agenda") { onToggle(e.key) }
            .heightIn(min = Dimens.touchTarget)
            .padding(start = Dimens.categoryStripe + 12.dp, end = 6.dp, top = 9.dp, bottom = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            CapsText(
                e.name,
                t.slotHeading.copy(
                    fontSize = if (tile) 16.sp else 18.sp,
                    lineHeight = if (tile) 17.sp else 19.sp,
                    letterSpacing = 0.04.em,
                ),
                Modifier
                    .weight(1f)
                    .padding(top = 2.dp)
                    .semantics { heading() },
                color = c.ink,
            )
            Icon(
                if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                contentDescription = null,
                tint = c.muted,
                modifier = Modifier.size(22.dp),
            )
        }
        Text(
            remember(e.mainRoom, c) {
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.ink)) { append(index.roomName(e.mainRoom)) }
                    val b = index.building(e.mainRoom)
                    // One line break at most: between the room and its building, never inside "Salt Palace L1".
                    if (b.isNotEmpty()) {
                        append("  ")
                        append(b.replace(' ', '\u00A0'))
                    }
                }
            },
            style = t.small,
            color = c.muted,
            modifier = Modifier.padding(top = 4.dp, end = 6.dp),
        )
        FlowRow(
            Modifier.padding(top = 5.dp, end = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            // "Half day · 1:20–5:30 PM" may wrap after "Half day ·" on a narrow tile, never inside the times.
            val parts = remember(e) { ColoText.hoursParts(e) }
            parts.forEachIndexed { i, part ->
                CapsText(if (i < parts.size - 1) "$part ·" else part, t.meta, color = c.muted, maxLines = 1)
            }
            if (card.mine) Pill("You", c.you, c.onYou)
            if (card.anthropic) Pill("Anthropic", c.anthropic, c.onAnthropic)
        }
        if (card.lines.isNotEmpty()) {
            // At most two entries ("Now" and "Next", or one of them, or "Starts"). The lead line may
            // take two text lines; a "Next" under it takes one. A narrower tile gets one more each.
            val lines = card.lines
            Column(Modifier.padding(top = 6.dp, end = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                lines.forEachIndexed { i, line ->
                    val max = if (i > 0 && line is ColoLine.Next) 1 else 2
                    ColoLineText(line, index, c, maxLines = if (tile) max + 1 else max)
                }
            }
        }
    }
}

/** "NOW · 12 MIN LEFT · <title>" in pink; "NEXT 10:40 · <title>" / "STARTS 9:00 AM · <title>" muted and ink. */
@Composable
private fun ColoLineText(line: ColoLine, index: ScheduleIndex, c: AppColors, maxLines: Int) {
    val t = AppTheme.type
    val now = line is ColoLine.Now
    val text = remember(line, c) {
        buildAnnotatedString {
            withStyle(
                SpanStyle(
                    fontFamily = Barlow,
                    fontWeight = if (now) FontWeight.Bold else FontWeight.SemiBold,
                    fontSize = 14.5.sp,
                    letterSpacing = 0.05.em,
                    fontFeatureSettings = "tnum",
                    color = if (now) c.you else c.muted,
                ),
            ) { append(ColoText.label(line, index::roomName).caps()) }
            val s = line.session
            if (s != null) {
                append(" · ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = if (now) c.you else c.ink)) { append(s.title) }
            }
        }
    }
    Text(text, style = t.small, color = if (now) c.you else c.muted, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

/**
 * An open event's agenda: the rest of its talks (mine pink, Anthropic tinted, live in pink, other
 * rooms named) and its breaks (quiet), then the event's pass note and links and a "Hide agenda"
 * button (so a long agenda can be closed from its foot). Every row opens the session's details.
 * [attached]: drawn as the continuation of the card above (one per row); otherwise a full-width
 * panel with its own heading and close button (two per row). [onHide] closes it.
 * With [onToggleGoing], every talk row has a "Going" star ([goingIds] filled, [clashIds] "Clash").
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ColoAgendaCard(
    card: ColoCard,
    attached: Boolean,
    me: String?,
    index: ScheduleIndex,
    selectedId: String?,
    revealId: String?,
    onHide: (String) -> Unit,
    onOpen: (String) -> Unit,
    onRevealed: () -> Unit,
    modifier: Modifier = Modifier,
    goingIds: Set<String> = emptySet(),
    clashIds: Set<String> = emptySet(),
    onToggleGoing: ((String) -> Unit)? = null,
) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val e = card.event
    val colo = c.category("colo")
    val r = Dimens.cardRadius
    val pills = rememberKidPills()
    Column(
        modifier
            .padding(bottom = Dimens.cardGap)
            .fillMaxWidth()
            .clip(if (attached) RoundedCornerShape(bottomStart = r, bottomEnd = r) else RoundedCornerShape(r))
            .cardSegment(fill = c.surface, border = coloBorder(card, c), stripe = colo, top = !attached, bottom = true)
            .padding(top = if (attached) 0.dp else 4.dp, bottom = 10.dp),
    ) {
        if (!attached) {
            Row(
                Modifier.padding(start = Dimens.categoryStripe + 12.dp, end = 0.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CapsText(
                    e.name,
                    t.slotHeading.copy(fontSize = 17.sp, lineHeight = 18.sp, letterSpacing = 0.04.em),
                    Modifier
                        .weight(1f)
                        .semantics { heading() },
                    color = c.ink,
                )
                IconButton(onClick = { onHide(e.key) }) {
                    Icon(Icons.Rounded.ExpandLess, contentDescription = "Hide the ${e.name} agenda", tint = c.muted)
                }
            }
        }
        // Rows: inset 8 dp less than the text so mine/Anthropic rows can bleed out (as in group cards).
        Column(
            Modifier
                .padding(start = Dimens.categoryStripe + 4.dp, end = 4.dp, top = if (attached) 0.dp else 2.dp)
                .drawBehind {
                    val inset = 8.dp.toPx()
                    val y = 0.5.dp.toPx()
                    drawLine(c.line, Offset(inset, y), Offset(size.width - inset, y), 1.dp.toPx())
                },
        ) {
            val items = card.agenda
            items.forEachIndexed { i, item ->
                val divider = !item.mine && i < items.size - 1 // web: .kid border-bottom, none on .me or :last-child
                if (item.isBreak) {
                    ColoBreakRow(item, index, item.session.id == selectedId, divider, c, onOpen)
                } else {
                    KidRow(
                        kid = item.session,
                        live = item.live,
                        mine = item.mine,
                        ant = item.anthropic,
                        me = me,
                        index = index,
                        selected = item.session.id == selectedId,
                        reveal = item.session.id == revealId,
                        divider = divider,
                        pills = pills,
                        colors = c,
                        onOpen = onOpen,
                        onRevealed = onRevealed,
                        place = item.room?.let { index.roomName(it) },
                        going = item.session.id in goingIds,
                        clash = item.session.id in clashIds,
                        onToggleGoing = onToggleGoing,
                    )
                }
            }
        }
        ColoFooter(card, c)
        HideAgendaButton(e.name, c) { onHide(e.key) }
    }
}

/** The agenda's last row: a full-width 48 dp "Hide agenda" button (the group cards' "Show all" look). */
@Composable
private fun HideAgendaButton(eventName: String, c: AppColors, onClick: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier
            .padding(start = Dimens.categoryStripe + 12.dp, end = 12.dp, top = 10.dp)
            .fillMaxWidth()
            .heightIn(min = Dimens.touchTarget)
            .clip(shape)
            .background(c.bg)
            .border(1.dp, c.line, shape)
            .clickable(role = Role.Button, onClickLabel = "Hide the $eventName agenda", onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.ExpandLess, contentDescription = null, tint = c.muted, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(4.dp))
        CapsText("Hide agenda", AppTheme.type.meta, color = c.ink, maxLines = 1)
    }
}

/** A quiet break row inside an agenda: "10:15  Coffee Break · until 10:40 · Meeting room foyers". Opens the menu. */
@Composable
private fun ColoBreakRow(
    item: ColoItem,
    index: ScheduleIndex,
    selected: Boolean,
    divider: Boolean,
    c: AppColors,
    onOpen: (String) -> Unit,
) {
    val t = AppTheme.type
    val s = item.session
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .then(if (selected) Modifier.border(2.dp, c.ink, shape) else Modifier)
            .semantics { this.selected = selected }
            .clickable(role = Role.Button, onClickLabel = "Open details") { onOpen(s.id) }
            .drawBehind {
                if (divider) {
                    val inset = 8.dp.toPx()
                    val y = size.height - 0.5.dp.toPx()
                    drawLine(c.line, Offset(inset, y), Offset(size.width - inset, y), 1.dp.toPx())
                }
            }
            .heightIn(min = Dimens.touchTarget)
            .padding(horizontal = 8.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CapsText(
            TimeFormat.hm(s.start),
            t.kidTime,
            Modifier.width(50.dp),
            color = if (item.live) c.you else c.muted,
            maxLines = 1,
        )
        Spacer(Modifier.width(8.dp))
        Text(
            remember(s, item.room) {
                // The time column has the start: the text gives the title (bold), the end and the place.
                val parts = ColoText.breakParts(s, item.room, index::roomName)
                buildAnnotatedString {
                    parts.forEachIndexed { i, part ->
                        if (i == 0) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(part) } else append(" · $part")
                    }
                }
            },
            style = t.tiny.copy(fontSize = 13.5.sp),
            color = c.muted,
            modifier = Modifier.weight(1f),
        )
    }
}

/** The event's info under its agenda: its pass note and links (the old placeholder's listing, the event page). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColoFooter(card: ColoCard, c: AppColors) {
    val e = card.event
    val uri = LocalUriHandler.current
    val open: (String) -> Unit = { url ->
        try {
            uri.openUri(url)
        } catch (ex: Exception) {
            // No browser: nothing to do, never crash.
        }
    }
    if (e.passNote == null && e.pageUrl == null && e.infoUrl == null) return
    FlowRow(
        Modifier.padding(start = Dimens.categoryStripe + 12.dp, end = 12.dp, top = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        e.passNote?.let { Text(it, style = AppTheme.type.small.copy(fontWeight = FontWeight.Bold), color = c.note) }
        e.pageUrl?.let { url -> ColoLink("Event page ↗", c) { open(url) } }
        e.infoUrl?.let { url -> ColoLink("Official listing ↗", c) { open(url) } }
    }
}

/** An outlined 48 dp link button (the details sheet's `.links a`). */
@Composable
private fun ColoLink(text: String, c: AppColors, onClick: () -> Unit) {
    val shape = RoundedCornerShape(Dimens.cardRadius)
    Box(
        Modifier
            .heightIn(min = Dimens.touchTarget)
            .clip(shape)
            .drawWithContent {
                drawContent()
                drawRoundRect(c.line, cornerRadius = CornerRadius(Dimens.cardRadius.toPx()), style = Stroke(1.dp.toPx()))
            }
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        CapsText(text, AppTheme.type.button.copy(fontSize = 14.sp), color = c.ink, maxLines = 1)
    }
}

/** Live border while a talk is on, like the session cards. */
private fun coloBorder(card: ColoCard, c: AppColors): Color = if (card.live) c.liveBorder else c.line

/**
 * [cardSurface] for a card that may be cut in two across LazyColumn items: the edge that isn't
 * [top] / [bottom] has no border line and square corners, so a card and its agenda read as one.
 * The caller clips to the matching shape. [ring]: a 2 dp selection-style outline (an open tile).
 */
private fun Modifier.cardSegment(
    fill: Color,
    border: Color,
    stripe: Color,
    top: Boolean,
    bottom: Boolean,
    ring: Color? = null,
    radius: Dp = Dimens.cardRadius,
): Modifier = drawWithContent {
    val r = radius.toPx()
    val bw = 1.dp.toPx()
    // Extend the rounded rect past an open edge (the clip cuts it), hiding that edge's line and corners.
    val over = r + 2 * bw
    val y0 = if (top) 0f else -over
    val y1 = if (bottom) size.height else size.height + over
    drawRoundRect(fill, topLeft = Offset(0f, y0), size = Size(size.width, y1 - y0), cornerRadius = CornerRadius(r))
    drawRoundRect(
        border,
        topLeft = Offset(bw / 2, y0 + bw / 2),
        size = Size(size.width - bw, y1 - y0 - bw),
        cornerRadius = CornerRadius(r - bw / 2),
        style = Stroke(bw),
    )
    drawRect(stripe, size = Size(Dimens.categoryStripe.toPx(), size.height))
    drawContent()
    if (ring != null) {
        val rw = 2.dp.toPx()
        drawRoundRect(
            ring,
            topLeft = Offset(rw / 2, y0 + rw / 2),
            size = Size(size.width - rw, y1 - y0 - rw),
            cornerRadius = CornerRadius(r - rw / 2),
            style = Stroke(rw),
        )
    }
}
