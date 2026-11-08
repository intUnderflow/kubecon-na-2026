package app.kcna26.ui.session

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kcna26.data.Repository
import app.kcna26.data.Room
import app.kcna26.data.Session
import app.kcna26.data.hasAnthropic
import app.kcna26.data.isMine
import app.kcna26.details.DescriptionFormat
import app.kcna26.details.DetailInfo
import app.kcna26.details.DetailsResult
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.theme.categoryColor
import app.kcna26.time.rememberNowState
import app.kcna26.ui.going.GoingClashNote
import app.kcna26.ui.going.GoingReminderHint
import app.kcna26.ui.going.GoingToggleButton

/** Everything above the pinned Directions bar, in the web's sheetHTML order. */
@Composable
internal fun DetailsBody(
    session: Session,
    repo: Repository,
    room: Room?,
    result: DetailsResult?,
    showLoading: Boolean,
    me: String?,
    reserveCloseSpace: Boolean,
    openUrl: (String) -> Unit,
) {
    val colors = AppTheme.colors
    val type = AppTheme.type
    val info = (result as? DetailsResult.Found)?.info

    MetaRow(session, repo, Modifier.padding(end = if (reserveCloseSpace) 44.dp else 0.dp))
    Text(
        session.title,
        style = type.sheetTitle,
        color = colors.ink,
        modifier = Modifier
            .padding(top = 6.dp, bottom = 4.dp)
            .semantics { heading() },
    )
    WhereRow(session, room)
    ColoInfo(session, repo)
    Pills(session, mine = isMine(session, me), anthropic = repo.hasAnthropic(session, me))
    GoingClashNote(session) // starred and overlapping: "Clash" and what with

    val rows = remember(info?.speakers, session.speakers, me, repo) {
        SessionText.speakerRows(info?.speakers.orEmpty(), session.speakers, me, repo.anthropicSpeakers)
    }
    if (rows.isNotEmpty()) {
        SectionLabel(SessionText.speakersHeading(rows.size))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (row in rows) SpeakerItem(row)
        }
    }

    // Getting there (the web's .wf .loc): "Level 2 · Salt Palace · 251 A–C". The button is pinned below.
    val level = SessionText.levelLabel(room)
    val place = SessionText.buildingAndRoom(room)
    if (level != null && place != null) {
        SectionLabel(SessionText.GETTING_THERE)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.clearAndSetSemantics { contentDescription = "$level · $place" },
        ) {
            Box(
                Modifier
                    .background(colors.ink, RoundedCornerShape(6.dp))
                    .padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = 3.dp),
            ) {
                CapsText(level, type.levelBadge, color = colors.bg)
            }
            Spacer(Modifier.width(8.dp))
            CapsText(place, type.levelBadge, color = colors.muted)
        }
    }

    About(result, info, showLoading, openUrl)
    Links(session, SessionText.officialUrl(repo, session), info, openUrl)
}

/**
 * Category · "Wed 5:00–5:30 PM" · duration · tag (the web's `.meta`). A co-located session's
 * event name ("ArgoCon") is the eyebrow in place of the category.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MetaRow(session: Session, repo: Repository, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val type = AppTheme.type
    val event = SessionText.coloEyebrow(repo, session)
    val label = event ?: SessionText.categoryLabel(repo, session)
    val tag = SessionText.tag(session)
    FlowRow(
        modifier = modifier.padding(top = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        if (label.isNotEmpty()) {
            CapsText(label, type.meta.copy(fontWeight = FontWeight.Bold), color = categoryColor(if (event != null) "colo" else session.category))
        }
        CapsText(SessionText.dayAndTime(repo.dayOf(session), session), type.meta, color = colors.muted)
        SessionText.duration(session)?.let { CapsText(it, type.meta, color = colors.muted) }
        if (tag != null) {
            Box(
                Modifier
                    .border(1.dp, colors.line, RoundedCornerShape(5.dp))
                    .padding(start = 5.dp, end = 5.dp, top = 1.dp),
            ) {
                CapsText(tag, type.meta.copy(fontSize = 12.5.sp), color = colors.muted)
            }
        }
    }
}

/** Room · building · note (the web's `.where`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WhereRow(session: Session, room: Room?) {
    val colors = AppTheme.colors
    val base = AppTheme.type.small.copy(fontSize = 15.sp)
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(SessionText.roomName(room, session), style = base.copy(fontWeight = FontWeight.Bold), color = colors.ink)
        SessionText.buildingLabel(room)?.let { Text(it, style = base, color = colors.muted) }
        SessionText.whereNote(session)?.let {
            Text(it, style = base.copy(fontWeight = FontWeight.Bold), color = colors.note)
        }
    }
}

/**
 * Co-located extras under the where row: which events a shared break serves, the talk's format,
 * level and "Sponsored" tags (outlined, like the summit tag), and its topic.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColoInfo(session: Session, repo: Repository) {
    if (!session.isColocated) return
    val colors = AppTheme.colors
    val type = AppTheme.type
    SessionText.servesLine(repo, session)?.let {
        Text(it, style = type.small, color = colors.muted, modifier = Modifier.padding(top = 4.dp))
    }
    val tags = SessionText.coloTags(session)
    if (tags.isNotEmpty()) {
        FlowRow(
            modifier = Modifier.padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            for (tag in tags) {
                Box(
                    Modifier
                        .border(1.dp, colors.line, RoundedCornerShape(5.dp))
                        .padding(start = 6.dp, end = 6.dp, top = 3.dp, bottom = 2.dp),
                ) {
                    CapsText(tag, type.pill.copy(fontSize = 13.sp), color = if (tag == SessionText.SPONSORED) colors.note else colors.muted)
                }
            }
        }
    }
    session.topic?.let {
        Text(it, style = type.small, color = colors.muted, modifier = Modifier.padding(top = 6.dp))
    }
}

/** "You’re speaking", "Anthropic", "Live · N min left". Only this reads the ticking clock. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Pills(session: Session, mine: Boolean, anthropic: Boolean) {
    val now by rememberNowState()
    val live = SessionText.liveLabel(session, now)
    if (!mine && !anthropic && live == null) return
    val colors = AppTheme.colors
    FlowRow(
        modifier = Modifier.padding(top = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (mine) Pill(SessionText.YOU_SPEAKING, colors.you, colors.onYou)
        if (anthropic) Pill(SessionText.ANTHROPIC, colors.anthropic, colors.onAnthropic)
        if (live != null) Pill(live, colors.you, colors.onYou)
    }
}

@Composable
private fun Pill(text: String, bg: Color, fg: Color, small: Boolean = false) {
    Box(
        Modifier
            .background(bg, RoundedCornerShape(5.dp))
            .padding(
                start = if (small) 5.dp else 7.dp,
                end = if (small) 5.dp else 7.dp,
                top = if (small) 3.dp else 4.dp,
                bottom = if (small) 2.dp else 3.dp,
            ),
    ) {
        val style = if (small) AppTheme.type.badge else AppTheme.type.pill.copy(fontSize = 13.sp)
        CapsText(text, style, color = fg)
    }
}

/** `.panel h3`: Barlow 14sp, muted, uppercase. */
@Composable
private fun SectionLabel(text: String) {
    CapsText(
        text,
        AppTheme.type.sectionLabel,
        color = AppTheme.colors.muted,
        modifier = Modifier
            .padding(top = 18.dp, bottom = 6.dp)
            .semantics { heading() },
    )
}

/** Name ("You" in pink for me, clay plus a badge for Anthropic colleagues) over the tagline. */
@Composable
private fun SpeakerItem(row: SessionText.SpeakerRow) {
    val colors = AppTheme.colors
    val type = AppTheme.type
    Column(Modifier.semantics(mergeDescendants = true) {}) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                row.label,
                style = type.small.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold, lineHeight = 19.5.sp),
                color = when {
                    row.isMe -> colors.you
                    row.isAnthropic -> colors.anthropic
                    else -> colors.ink
                },
                modifier = Modifier.weight(1f, fill = false),
            )
            if (row.isAnthropic) {
                Spacer(Modifier.width(6.dp))
                Pill(SessionText.ANTHROPIC, colors.anthropic, colors.onAnthropic, small = true)
            }
        }
        if (row.tagline.isNotEmpty()) {
            Text(row.tagline, style = type.small, color = colors.muted)
        }
    }
}

/** About: the description as paragraphs and lists, or the loading / unavailable note. */
@Composable
private fun About(result: DetailsResult?, info: DetailInfo?, showLoading: Boolean, openUrl: (String) -> Unit) {
    val colors = AppTheme.colors
    val type = AppTheme.type
    when {
        result == null -> if (showLoading) {
            SectionLabel(SessionText.ABOUT)
            Text(SessionText.LOADING, style = type.description, color = colors.muted)
        }
        result == DetailsResult.Unavailable -> {
            SectionLabel(SessionText.ABOUT)
            Text(SessionText.UNAVAILABLE, style = type.small, color = colors.muted)
        }
        info?.description != null -> {
            val blocks = remember(info.description) { DescriptionFormat.parse(info.description) }
            if (blocks.isNotEmpty()) {
                SectionLabel(SessionText.ABOUT)
                Description(blocks, openUrl)
            }
        }
    }
}

@Composable
private fun Description(blocks: List<DescriptionFormat.Block>, openUrl: (String) -> Unit) {
    val colors = AppTheme.colors
    val style = AppTheme.type.description
    val linkColor = colors.category("talk")
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (block in blocks) {
            when (block) {
                is DescriptionFormat.Block.Paragraph ->
                    Text(rememberRich(block.text, linkColor, openUrl), style = style, color = colors.ink)
                is DescriptionFormat.Block.Heading ->
                    Text(
                        rememberRich(block.text, linkColor, openUrl),
                        style = style.copy(fontWeight = FontWeight.Bold),
                        color = colors.ink,
                        modifier = Modifier.semantics { heading() },
                    )
                is DescriptionFormat.Block.ListBlock ->
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        val markerWidth = if (block.items.any { it.ordered }) 28.dp else 18.dp
                        for (item in block.items) {
                            Row {
                                Text(item.marker, style = style, color = colors.muted, modifier = Modifier.width(markerWidth))
                                Text(
                                    rememberRich(item.text, linkColor, openUrl),
                                    style = style,
                                    color = colors.ink,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
            }
        }
    }
}

/** [DescriptionFormat.Rich] → AnnotatedString; links open in the browser via [openUrl]. */
@Composable
private fun rememberRich(rich: DescriptionFormat.Rich, linkColor: Color, openUrl: (String) -> Unit): AnnotatedString =
    remember(rich, linkColor, openUrl) {
        if (rich.spans.isEmpty()) return@remember AnnotatedString(rich.text)
        val linkStyles = TextLinkStyles(style = SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline))
        buildAnnotatedString {
            append(rich.text)
            for (sp in rich.spans) {
                if (sp.start >= sp.end || sp.end > rich.text.length) continue
                when (sp) {
                    is DescriptionFormat.Span.Bold -> addStyle(SpanStyle(fontWeight = FontWeight.Bold), sp.start, sp.end)
                    is DescriptionFormat.Span.Italic -> addStyle(SpanStyle(fontStyle = FontStyle.Italic), sp.start, sp.end)
                    is DescriptionFormat.Span.Link -> addLink(
                        LinkAnnotation.Url(sp.url, linkStyles) { openUrl(sp.url) },
                        sp.start,
                        sp.end,
                    )
                }
            }
        }
    }

/**
 * Slides ↗, Proposal and replies on GitHub ↗ (sessions with a [Session.discussionUrl]), an extra
 * summit link if the data has one, Official listing ↗ (the web's `.links`). All open in the browser.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Links(session: Session, official: String?, info: DetailInfo?, openUrl: (String) -> Unit) {
    val slides = info?.slidesUrl ?: session.slidesUrl
    val discussion = session.discussionUrl
    val link = info?.link
    FlowRow(
        modifier = Modifier.padding(top = 18.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (slides != null) LinkButton(SessionText.SLIDES, primary = true) { openUrl(slides) }
        if (discussion != null) LinkButton(SessionText.DISCUSSION, primary = true) { openUrl(discussion) }
        if (link != null) {
            val text = info.linkText ?: link
            LinkButton("$text ↗", primary = true) { openUrl(link) }
        }
        if (official != null) LinkButton(SessionText.OFFICIAL, primary = false) { openUrl(official) }
    }
}

@Composable
private fun LinkButton(text: String, primary: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val shape = RoundedCornerShape(Dimens.cardRadius)
    val padding = PaddingValues(horizontal = 16.dp)
    val mod = Modifier.heightIn(min = Dimens.touchTarget)
    if (primary) {
        Button(
            onClick = onClick,
            modifier = mod,
            shape = shape,
            contentPadding = padding,
            colors = ButtonDefaults.buttonColors(containerColor = colors.ink, contentColor = colors.bg),
        ) { CapsText(text, AppTheme.type.button) }
    } else {
        OutlinedButton(
            onClick = onClick,
            modifier = mod,
            shape = shape,
            contentPadding = padding,
            border = BorderStroke(1.dp, colors.line),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.ink),
        ) { CapsText(text, AppTheme.type.button) }
    }
}

/**
 * The pinned, thumb-reachable Directions button; disabled with the web's explanation for OFF.
 * The "Going" toggle sits beside it, with the notifications-off hint above when it applies.
 */
@Composable
internal fun DirectionsBar(
    session: Session,
    room: Room?,
    onDirections: (String) -> Unit,
    showDivider: () -> Boolean,
    horizontalPadding: Dp,
    bottomPadding: Dp,
) {
    val colors = AppTheme.colors
    val reason = SessionText.directionsUnavailable(room, session)
    Column(
        Modifier
            .fillMaxWidth()
            .drawBehind {
                if (showDivider()) drawLine(colors.line, Offset(0f, 0f), Offset(size.width, 0f), 1.dp.toPx())
            }
            .padding(start = horizontalPadding, end = horizontalPadding, top = 10.dp, bottom = 12.dp + bottomPadding),
    ) {
        GoingReminderHint(session, Modifier.widthIn(max = Dimens.maxTextWidth).padding(bottom = 8.dp))
        if (reason != null) {
            Text(
                reason,
                style = AppTheme.type.small,
                color = colors.muted,
                modifier = Modifier
                    .widthIn(max = Dimens.maxTextWidth)
                    .padding(bottom = 8.dp),
            )
        }
        Row(
            Modifier
                .widthIn(max = Dimens.maxTextWidth)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            GoingToggleButton(session)
            Button(
                onClick = { onDirections(session.id) },
                enabled = reason == null,
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 56.dp),
                shape = RoundedCornerShape(Dimens.cardRadius),
                contentPadding = PaddingValues(horizontal = 20.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.ink,
                    contentColor = colors.bg,
                    disabledContainerColor = colors.line,
                    disabledContentColor = colors.muted,
                ),
            ) {
                Icon(Icons.AutoMirrored.Filled.DirectionsWalk, contentDescription = null, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(8.dp))
                CapsText(SessionText.DIRECTIONS, AppTheme.type.button.copy(fontSize = 18.sp))
            }
        }
    }
}

/** The sheet's grab bar (the web's `.grab`). */
@Composable
internal fun GrabBar() {
    Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 10.dp), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .size(width = 42.dp, height = 5.dp)
                .background(AppTheme.colors.line, RoundedCornerShape(3.dp)),
        )
    }
}

/** The × button (the web's `.x`): 48 dp target, bg-coloured circle so it reads over scrolled text. */
@Composable
internal fun CloseButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    IconButton(
        onClick = onClick,
        modifier = modifier.size(Dimens.touchTarget),
        colors = IconButtonDefaults.iconButtonColors(containerColor = colors.bg, contentColor = colors.ink),
    ) {
        Icon(Icons.Filled.Close, contentDescription = "Close")
    }
}
