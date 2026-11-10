package app.kcna26.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.kcna26.data.Session
import app.kcna26.schedule.CardStatus
import app.kcna26.schedule.GroupBlock
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.schedule.ScheduleLogic
import app.kcna26.schedule.SessionBlock
import app.kcna26.theme.AppColors
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.theme.caps
import app.kcna26.time.TimeFormat
import app.kcna26.ui.going.ClashTag
import app.kcna26.ui.going.GoingMark
import app.kcna26.ui.going.GoingStarFrame
import app.kcna26.ui.going.StarReserve
import app.kcna26.ui.going.StarToggle
import app.kcna26.ui.going.clash
import app.kcna26.ui.going.goingCardBg
import app.kcna26.ui.going.goingCardBorder
import app.kcna26.ui.going.goingRowBg
import app.kcna26.ui.going.goingRule
import java.time.Instant

/**
 * Web `card(x)` for a regular session: category stripe, meta row with pills, title, speakers, room.
 * With [onToggleGoing], a star toggle sits in the top-right corner; [going] cards get a quiet ink
 * highlight and [clash] adds the "Clash" tag.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SessionCard(
    block: SessionBlock,
    status: CardStatus,
    me: String?,
    index: ScheduleIndex,
    selected: Boolean,
    wide: Boolean,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
    going: Boolean = false,
    clash: Boolean = false,
    onToggleGoing: ((String) -> Unit)? = null,
    starSpace: Boolean = false,
) {
    if (onToggleGoing != null) {
        GoingStarFrame(
            going,
            onToggle = { onToggleGoing(block.session.id) },
            onCard = block.mine,
            label = block.session.title,
            modifier = modifier,
        ) {
            SessionCard(block, status, me, index, selected, wide, onOpen, going = going, clash = clash, starSpace = true)
        }
        return
    }
    val c = AppTheme.colors
    val t = AppTheme.type
    val s = block.session
    val mine = block.mine
    val ant = block.anthropic
    val catColor = c.category(block.category)
    val shape = RoundedCornerShape(Dimens.cardRadius)

    val fill: Color
    val border: Color
    val stripe: Color
    when {
        mine -> { fill = c.you; border = c.you; stripe = c.you }
        ant -> { fill = c.anthropicCardBg; border = if (going) c.goingCardBorder else c.anthropicCardBorder; stripe = c.anthropic }
        going -> { fill = c.goingCardBg; border = if (status.live) c.liveBorder else c.goingCardBorder; stripe = catColor }
        status.live -> { fill = c.surface; border = c.liveBorder; stripe = catColor }
        else -> { fill = c.surface; border = c.line; stripe = catColor }
    }
    val ink = if (mine) c.onYou else c.ink
    val muted = if (mine) c.onYou else c.muted

    Column(
        modifier
            .fillMaxWidth()
            .then(if (mine) Modifier.shadow(10.dp, shape, ambientColor = c.you, spotColor = c.you) else Modifier)
            .clip(shape)
            .cardSurface(
                fill = fill,
                border = border,
                stripe = stripe,
                progress = status.progress,
                progressColor = if (mine) c.onYou else c.you,
                ring = if (selected) c.ink else null,
            )
            .semantics { this.selected = selected }
            .clickable(role = Role.Button, onClickLabel = "Open details") { onOpen(s.id) }
            .padding(start = Dimens.categoryStripe + 12.dp, end = 12.dp, top = 9.dp, bottom = 10.dp),
    ) {
        FlowRow(
            Modifier.padding(end = if (starSpace) StarReserve else 0.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            // Co-located talks (search results): the event's name is the eyebrow, in place of "Event".
            val label = index.coloEventOf(s)?.name ?: index.categoryLabel(block.category)
            if (label.isNotEmpty()) {
                CapsText(label, t.meta.copy(fontWeight = FontWeight.Bold), color = if (mine) c.onYou else catColor, maxLines = 2)
            }
            CapsText(TimeFormat.range(s), t.meta, color = muted, maxLines = 1)
            TimeFormat.dur(s)?.let { CapsText(it, t.meta, color = muted, maxLines = 1) }
            val tag = s.note
            if (s.isMaintainerSummit && tag != null && tag != "Keynote") {
                Pill(tag, Color.Transparent, muted, border = if (mine) c.onYou.copy(alpha = 0.6f) else c.line)
            }
            if (mine) Pill("You’re speaking", c.onYou, c.you)
            if (ant) Pill("Anthropic", c.anthropic, c.onAnthropic)
            if (status.live && status.liveLabel != null) {
                Pill(status.liveLabel, if (mine) c.onYou else c.you, if (mine) c.you else c.onYou)
            }
            if (clash) ClashTag(onCard = mine)
        }
        Text(
            s.title,
            style = when {
                mine -> t.cardTitleMine
                wide -> t.cardTitle.copy(fontSize = 17.sp)
                else -> t.cardTitle
            },
            color = ink,
            modifier = Modifier.padding(top = 4.dp, bottom = 2.dp, end = if (starSpace) StarReserve else 0.dp),
        )
        if (s.speakers.isNotEmpty()) {
            Text(
                remember(s.speakers, me, mine, c) { speakersLine(s.speakers, me, index.anthropicSpeakers, c, onMine = mine) },
                style = t.small,
                color = muted,
            )
        }
        WhereLine(
            roomName = index.roomName(s.room),
            building = index.building(s.room),
            note = if (!s.isMaintainerSummit) s.note else null,
            ink = ink,
            muted = muted,
            noteColor = if (mine) c.onYou else c.note,
            modifier = Modifier.padding(top = 5.dp),
        )
    }
}

/** Web `.where`: bold room, muted building, optional note ("Sold out") in the hands-on colour. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun WhereLine(
    roomName: String,
    building: String,
    note: String?,
    ink: Color,
    muted: Color,
    noteColor: Color,
    modifier: Modifier = Modifier,
) {
    val style = AppTheme.type.small
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(roomName, style = style.copy(fontWeight = FontWeight.Bold), color = ink)
        if (building.isNotEmpty()) Text(building, style = style, color = muted)
        if (note != null) Text(note, style = style.copy(fontWeight = FontWeight.Bold), color = noteColor)
    }
}

/** Web `.lrow`: a quiet dashed break row ("☕ Coffee Break" without the emoji · room). Not tappable, like the web. */
@Composable
internal fun BreakRow(session: Session, index: ScheduleIndex, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .dashedOutline(c.line, Dimens.cardRadius)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        CapsText(TimeFormat.range(session), AppTheme.type.meta.copy(lineHeight = 14.sp), Modifier.alignByBaseline(), color = c.muted, maxLines = 1)
        Spacer(Modifier.width(10.dp))
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.ink)) { append(ScheduleLogic.breakTitle(session.title)) }
                append(" · ")
                append(index.roomName(session.room))
            },
            style = AppTheme.type.small.copy(fontSize = 14.5.sp),
            color = c.muted,
            modifier = Modifier.alignByBaseline(),
        )
    }
}

/** How many kids a collapsed group shows (web `kids.slice(0,6)`) and when it collapses (> 12). */
private const val GROUP_COLLAPSE_OVER = 12
private const val GROUP_COLLAPSED_SHOWS = 6

/**
 * Web `seriesCard(g)`: one card for back-to-back sessions in a room. Long groups
 * show 6 kids and a "Show all N" button unless expanded or one of them is mine.
 * With [onToggleGoing], every kid row has a star; the header shows a filled star
 * when any kid is in [goingIds] (so a collapsed card still says so).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun GroupCard(
    block: GroupBlock,
    now: Instant,
    me: String?,
    index: ScheduleIndex,
    expanded: Boolean,
    selectedId: String?,
    revealId: String?,
    wide: Boolean,
    onExpand: (String) -> Unit,
    onOpen: (String) -> Unit,
    onRevealed: () -> Unit,
    modifier: Modifier = Modifier,
    goingIds: Set<String> = emptySet(),
    clashIds: Set<String> = emptySet(),
    onToggleGoing: ((String) -> Unit)? = null,
) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val g = block.group
    val kids = block.kids
    val kidLive = remember(kids, now) { kids.map { ScheduleLogic.isLive(it, now) } }
    val anyLive = kidLive.any { it }
    val kidMine = remember(kids, me) { kids.map { index.isMine(it, me) } }
    // Web: all kids when expanded, ≤ 12 of them, or one is mine. Also keep a jumped-to or selected kid visible.
    val showAll = expanded || kids.size <= GROUP_COLLAPSE_OVER || kidMine.any { it } ||
        (revealId != null && kids.any { it.id == revealId }) ||
        (selectedId != null && kids.any { it.id == selectedId })
    val shown = if (showAll) kids.size else GROUP_COLLAPSED_SHOWS
    val shape = RoundedCornerShape(Dimens.cardRadius)
    val catColor = c.category(g.category)
    val pills = rememberKidPills()

    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .cardSurface(fill = c.surface, border = if (anyLive) c.liveBorder else c.line, stripe = catColor)
            .padding(top = 9.dp, bottom = 10.dp),
    ) {
        val head = Modifier.padding(start = Dimens.categoryStripe + 12.dp, end = 12.dp)
        FlowRow(
            head,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            val label = index.categoryLabel(g.category)
            if (label.isNotEmpty()) CapsText(label, t.meta.copy(fontWeight = FontWeight.Bold), color = catColor, maxLines = 1)
            // The shown kids' span: with the Going filter on, only the starred ones are left.
            CapsText(ScheduleLogic.spanLabel(block.start, kids.maxOf { it.effectiveEnd }), t.meta, color = c.muted, maxLines = 1)
            CapsText("${kids.size} ${if (kids.size == 1) "session" else "sessions"}", t.meta, color = c.muted, maxLines = 1)
            if (anyLive) Pill("Live", c.you, c.onYou)
            val starred = kids.count { it.id in goingIds }
            if (starred > 0) GoingMark("RSVP’d to $starred of these")
        }
        Text(
            g.title,
            style = if (wide) t.cardTitle.copy(fontSize = 17.sp) else t.cardTitle,
            color = c.ink,
            modifier = head.padding(top = 4.dp, bottom = 2.dp),
        )
        WhereLine(index.roomName(g.room), index.building(g.room), null, c.ink, c.muted, c.note, head.padding(top = 5.dp))

        // Kids: the list is inset 8 dp less than the text so mine/Anthropic rows can bleed out (web margin: 0 -8px).
        Column(
            Modifier
                .padding(start = Dimens.categoryStripe + 4.dp, end = 4.dp, top = 8.dp)
                .drawBehind {
                    val inset = 8.dp.toPx()
                    val y = 0.5.dp.toPx()
                    drawLine(c.line, Offset(inset, y), Offset(size.width - inset, y), 1.dp.toPx())
                },
        ) {
            for (i in 0 until shown) {
                val k = kids[i]
                KidRow(
                    kid = k,
                    live = kidLive[i],
                    mine = kidMine[i],
                    ant = !kidMine[i] && index.hasAnthropic(k, me),
                    me = me,
                    index = index,
                    selected = k.id == selectedId,
                    reveal = k.id == revealId,
                    divider = !kidMine[i] && i < shown - 1, // web: .kid border-bottom, none on .me or :last-child
                    pills = pills,
                    colors = c,
                    onOpen = onOpen,
                    onRevealed = onRevealed,
                    going = k.id in goingIds,
                    clash = k.id in clashIds,
                    onToggleGoing = onToggleGoing,
                )
            }
        }
        if (!showAll) {
            Box(
                Modifier
                    .padding(start = Dimens.categoryStripe + 12.dp, end = 12.dp, top = 8.dp)
                    .fillMaxWidth()
                    .heightIn(min = Dimens.touchTarget)
                    .clip(RoundedCornerShape(8.dp))
                    .background(c.bg)
                    .border(1.dp, c.line, RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button) { onExpand(g.key) },
                contentAlignment = Alignment.Center,
            ) {
                CapsText("Show all ${kids.size}", t.meta, color = c.ink)
            }
        }
    }
}

/** Inline pill sizes for kid rows (web `.kid .pill`), measured once per density. */
internal class KidPills(val content: Map<String, InlineTextContent>)

/** Web `.kid` pills: "You" (mine), "Anthropic", "Live"; and "Clash" (starred, overlapping). */
private val KID_PILL_LABELS = mapOf("you" to "You", "ant" to "Anthropic", "live" to "Live", "clash" to "Clash")

private val KidPillStyle = TextStyle(fontWeight = FontWeight.Bold, fontSize = 11.5.sp, letterSpacing = 0.08.em)

@Composable
internal fun rememberKidPills(): KidPills {
    val measurer = rememberTextMeasurer(cacheSize = 4)
    val density = LocalDensity.current
    val base = AppTheme.type.pill.merge(KidPillStyle)
    val c = AppTheme.colors
    return remember(density, base, c) {
        fun pill(text: String, bg: Color, fg: Color): InlineTextContent {
            val m = measurer.measure(text.caps(), base)
            val w = with(density) { (m.size.width.toDp() + 10.dp + 6.dp).toSp() } // 5 dp padding each side + 6 dp gap
            val h = with(density) { (m.size.height.toDp() + 5.dp).toSp() }
            return InlineTextContent(Placeholder(w, h, PlaceholderVerticalAlign.TextCenter)) {
                Box(Modifier.padding(end = 6.dp)) {
                    CapsText(
                        text,
                        base,
                        Modifier
                            .background(bg, RoundedCornerShape(5.dp))
                            .padding(start = 5.dp, end = 5.dp, top = 3.dp, bottom = 2.dp),
                        color = fg,
                        maxLines = 1,
                    )
                }
            }
        }
        KidPills(
            mapOf(
                "you" to pill(KID_PILL_LABELS.getValue("you"), c.onYou, c.you),
                "ant" to pill(KID_PILL_LABELS.getValue("ant"), c.anthropic, c.onAnthropic),
                "live" to pill(KID_PILL_LABELS.getValue("live"), c.you, c.onYou),
                "clash" to pill(KID_PILL_LABELS.getValue("clash"), c.clash, c.surface),
            ),
        )
    }
}

/**
 * Web `.kid`: time | pill + title / speakers. Mine is a pink row, Anthropic a clay-tinted one.
 * [place]: a room to name under the speakers (co-located talks outside their event's main room).
 */
@Composable
internal fun KidRow(
    kid: Session,
    live: Boolean,
    mine: Boolean,
    ant: Boolean,
    me: String?,
    index: ScheduleIndex,
    selected: Boolean,
    reveal: Boolean,
    divider: Boolean,
    pills: KidPills,
    colors: AppColors,
    onOpen: (String) -> Unit,
    onRevealed: () -> Unit,
    place: String? = null,
    going: Boolean = false,
    clash: Boolean = false,
    onToggleGoing: ((String) -> Unit)? = null,
) {
    val c = colors
    val t = AppTheme.type
    val shape = RoundedCornerShape(8.dp)
    val requester = remember { BringIntoViewRequester() }
    if (reveal) {
        LaunchedEffect(kid.id) {
            requester.bringIntoView()
            onRevealed()
        }
    }
    val pillKey = when {
        mine -> "you"
        ant -> "ant"
        live -> "live"
        else -> null
    }
    val fg = if (mine) c.onYou else c.ink
    val star = onToggleGoing != null
    // With a star, the vertical padding moves onto the text so the 48 dp star doesn't grow the row.
    val vPad = if (mine) 9.dp else 7.dp
    Row(
        Modifier
            .fillMaxWidth()
            .bringIntoViewRequester(requester)
            .padding(vertical = if (mine) 4.dp else 0.dp)
            .clip(shape)
            .then(
                when {
                    mine -> Modifier.background(c.you)
                    ant -> Modifier.background(c.anthropicRowBg)
                    going -> Modifier.background(c.goingRowBg)
                    else -> Modifier
                },
            )
            .then(if (selected) Modifier.border(2.dp, c.ink, shape) else Modifier)
            .semantics { this.selected = selected }
            .clickable(role = Role.Button, onClickLabel = "Open details") { onOpen(kid.id) }
            .drawBehind {
                if (divider) {
                    val inset = 8.dp.toPx()
                    val y = size.height - 0.5.dp.toPx() // inside the clip
                    drawLine(c.line, Offset(inset, y), Offset(size.width - inset, y), 1.dp.toPx())
                }
                if (going && !mine) { // starred: an ink rule down the left edge
                    val w = 3.dp.toPx()
                    drawLine(c.goingRule, Offset(w / 2, 0f), Offset(w / 2, size.height), w)
                }
            }
            .heightIn(min = Dimens.touchTarget)
            .padding(start = 8.dp, end = if (star) 0.dp else 8.dp, top = if (star) 0.dp else vPad, bottom = if (star) 0.dp else vPad),
    ) {
        val textPad = Modifier.padding(vertical = if (star) vPad else 0.dp)
        CapsText(
            TimeFormat.hm(kid.start),
            if (live) t.kidTime.copy(fontWeight = FontWeight.Bold) else t.kidTime,
            textPad.width(50.dp),
            color = when {
                mine -> c.onYou
                live -> c.you
                else -> c.muted
            },
            maxLines = 1,
        )
        Spacer(Modifier.width(8.dp))
        Column(textPad.weight(1f)) {
            val title = remember(kid.title, pillKey, clash) {
                buildAnnotatedString {
                    if (pillKey != null) appendInlineContent(pillKey, KID_PILL_LABELS.getValue(pillKey) + " ")
                    if (clash) appendInlineContent("clash", KID_PILL_LABELS.getValue("clash") + " ")
                    append(kid.title)
                }
            }
            Text(title, style = t.kidTitle, color = fg, inlineContent = pills.content)
            if (kid.speakers.isNotEmpty()) {
                Text(
                    remember(kid.speakers, me, mine, c) { speakersLine(kid.speakers, me, index.anthropicSpeakers, c, onMine = mine) },
                    style = t.tiny,
                    color = if (mine) c.onYou else c.muted,
                    modifier = Modifier.padding(top = 1.dp),
                )
            }
            if (place != null) {
                Text(
                    place,
                    style = t.tiny.copy(fontWeight = FontWeight.Bold),
                    color = if (mine) c.onYou else c.ink,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
        if (onToggleGoing != null) StarToggle(going, { onToggleGoing(kid.id) }, label = kid.title, onCard = mine, iconSize = 21.dp)
    }
}
