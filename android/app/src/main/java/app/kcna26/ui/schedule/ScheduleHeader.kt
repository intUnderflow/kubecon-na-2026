package app.kcna26.ui.schedule

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kcna26.data.Session
import app.kcna26.schedule.DayTab
import app.kcna26.schedule.DayView
import app.kcna26.schedule.MineBanner
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.theme.caps
import app.kcna26.time.TimeFormat

/**
 * Web `header.top`: brand + clock (+ Settings), then the day tabs. Stays put
 * above the list; draws behind the status bar.
 */
@Composable
internal fun ScheduleHeader(
    clock: String,
    tabs: List<DayTab>,
    currentDay: String?,
    searching: Boolean,
    sidePadding: Dp,
    onDay: (String) -> Unit,
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AppTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .background(c.bg)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top)),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(start = sidePadding, end = (sidePadding - 12.dp).coerceAtLeast(0.dp))
                .heightIn(min = Dimens.touchTarget),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                buildAnnotatedString {
                    append("KUBECON ")
                    withStyle(SpanStyle(color = c.you)) { append("NA") }
                    append(" 2026")
                },
                style = AppTheme.type.brand,
                color = c.ink,
                maxLines = 1,
                modifier = Modifier
                    .weight(1f)
                    .semantics { heading() },
            )
            CapsText(clock, AppTheme.type.clock, color = c.muted, maxLines = 1)
            IconButton(onClick = onSettings) {
                Icon(Icons.Rounded.Settings, contentDescription = "Settings", tint = c.muted)
            }
        }
        DayTabs(
            tabs = tabs,
            currentDay = if (searching) null else currentDay,
            onDay = onDay,
            modifier = Modifier.padding(start = sidePadding, end = sidePadding, top = 6.dp, bottom = 10.dp),
        )
        HorizontalDivider(color = c.line)
    }
}

/** Web `.days`: equal-width tabs; the current one inverted; a pink "YOU" badge on days I still speak. */
@Composable
private fun DayTabs(tabs: List<DayTab>, currentDay: String?, onDay: (String) -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val shape = RoundedCornerShape(Dimens.cardRadius)
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (tab in tabs) {
            val on = tab.key == currentDay
            Box(Modifier.weight(1f)) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 50.dp)
                        .clip(shape)
                        .background(if (on) c.ink else c.surface)
                        .border(1.dp, if (on) c.ink else c.line, shape)
                        .selectable(selected = on, role = Role.Tab) { onDay(tab.key) }
                        .semantics {
                            contentDescription = (if (tab.label == "Today") "Today, " else "") + tab.title +
                                (if (tab.hasMine) ", you’re speaking" else "")
                        }
                        .padding(top = 7.dp, bottom = 6.dp, start = 2.dp, end = 2.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
                ) {
                    CapsText(tab.label, t.dayTabLabel, color = if (on) c.bg.copy(alpha = 0.75f) else c.muted, maxLines = 1)
                    CapsText(tab.number.toString(), t.dayTabNumber, color = if (on) c.bg else c.ink, maxLines = 1)
                }
                if (tab.hasMine) {
                    CapsText(
                        "You",
                        t.badge,
                        Modifier
                            .clearAndSetSemantics {} // part of the tab's description
                            .align(Alignment.TopEnd)
                            .offset(x = 4.dp, y = (-7).dp)
                            .background(c.you, RoundedCornerShape(5.dp))
                            .padding(start = 5.dp, end = 5.dp, top = 3.dp, bottom = 2.dp),
                        color = c.onYou,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** Web `.search`: "Search talks, speakers, rooms" with a clear button. */
@Composable
internal fun ScheduleSearchField(state: TextFieldState, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val keyboard = LocalSoftwareKeyboardController.current
    val shape = RoundedCornerShape(Dimens.cardRadius)
    BasicTextField(
        state = state,
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 14.dp),
        textStyle = AppTheme.type.body.copy(color = c.ink),
        cursorBrush = SolidColor(c.you),
        lineLimits = TextFieldLineLimits.SingleLine,
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            imeAction = ImeAction.Search,
        ),
        onKeyboardAction = { keyboard?.hide() },
        decorator = { inner ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = Dimens.touchTarget)
                    .clip(shape)
                    .background(c.surface)
                    .border(1.dp, c.line, shape)
                    .padding(start = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = c.muted, modifier = Modifier.size(19.dp))
                Spacer(Modifier.width(9.dp))
                Box(Modifier.weight(1f).padding(vertical = 11.dp)) {
                    if (state.text.isEmpty()) {
                        Text("Search talks, speakers, rooms", style = AppTheme.type.body, color = c.muted, maxLines = 1)
                    }
                    inner()
                }
                if (state.text.isNotEmpty()) {
                    IconButton(onClick = { state.clearText() }) {
                        Icon(Icons.Rounded.Close, contentDescription = "Clear search", tint = c.muted)
                    }
                } else {
                    Spacer(Modifier.width(12.dp))
                }
            }
        },
    )
}

/**
 * Web `.dayhead`: day name, subtitle, and today's "3 on now · Next at 10:15 AM".
 * [trailing] sits at the end of the day name's line (the Going filter chip).
 */
@Composable
internal fun DayHeading(view: DayView, large: Boolean, modifier: Modifier = Modifier, trailing: @Composable (() -> Unit)? = null) {
    val c = AppTheme.colors
    val t = AppTheme.type
    Column(modifier.padding(top = 18.dp, bottom = 4.dp)) {
        HeadingLine(trailing) {
            CapsText(
                view.day.label,
                if (large) t.dayHeading.copy(fontSize = 36.sp, lineHeight = 37.sp) else t.dayHeading,
                it.semantics { heading() },
                color = c.ink,
            )
        }
        Text(
            view.day.subtitle,
            style = t.body,
            color = c.muted,
            modifier = Modifier
                .padding(top = 4.dp)
                .widthIn(max = Dimens.maxTextWidth),
        )
        val st = view.status
        if (st != null) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = c.you, fontWeight = FontWeight.Bold)) { append(st.onNow.toString()) }
                    append(" ON NOW")
                    if (st.nextStart != null) {
                        append(" · NEXT AT ")
                        withStyle(SpanStyle(color = c.ink, fontWeight = FontWeight.Bold)) { append(TimeFormat.hma(st.nextStart).caps()) }
                    }
                },
                style = t.status,
                color = c.muted,
                modifier = Modifier.padding(top = 10.dp),
            )
        }
    }
}

/** Web search heading: "12 matches", with an optional [trailing] chip at the end of the line. */
@Composable
internal fun SearchHeading(text: String, large: Boolean, modifier: Modifier = Modifier, trailing: @Composable (() -> Unit)? = null) {
    val t = AppTheme.type
    HeadingLine(trailing, modifier.padding(top = 18.dp, bottom = 4.dp)) {
        CapsText(
            text,
            if (large) t.dayHeading.copy(fontSize = 36.sp, lineHeight = 37.sp) else t.dayHeading,
            it.semantics { heading() },
            color = AppTheme.colors.ink,
        )
    }
}

/** A heading ([title] gets the modifier to use) with an optional [trailing] item at the end of its line. */
@Composable
private fun HeadingLine(
    trailing: @Composable (() -> Unit)?,
    modifier: Modifier = Modifier,
    title: @Composable (Modifier) -> Unit,
) {
    if (trailing == null) {
        Box(modifier) { title(Modifier) }
        return
    }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        title(Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        trailing()
    }
}

/**
 * Web `.mine`: "You’re speaking" with a countdown chip, my next talk (time,
 * title, "Head to {room} · {building}"), and my later talks that day. Tapping a
 * talk jumps to it in the list and opens it.
 */
@Composable
internal fun MineBannerCard(banner: MineBanner, onTalk: (Session) -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val shape = RoundedCornerShape(Dimens.bannerRadius)
    val white = c.onYou
    Column(
        modifier
            .padding(top = 12.dp)
            .fillMaxWidth()
            .shadow(10.dp, shape, ambientColor = c.you, spotColor = c.you)
            .clip(shape)
            .background(c.you)
            .padding(start = 14.dp, end = 14.dp, top = 11.dp, bottom = 4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CapsText("You’re speaking", t.bannerLabel, Modifier.weight(1f).semantics { heading() }, color = white, maxLines = 1)
            Countdown(banner.countdown, pulse = banner.soon)
        }
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .clickable(role = Role.Button, onClickLabel = "Open details") { onTalk(banner.next) }
                .padding(top = 8.dp, bottom = 10.dp),
        ) {
            CapsText(banner.nextTime, t.bannerTime, color = white.copy(alpha = 0.9f))
            Text(banner.next.title, style = t.bannerTitle, color = white, modifier = Modifier.padding(top = 2.dp))
            Text(
                banner.nextWhere,
                style = t.small.copy(fontSize = 14.5.sp, fontWeight = if (banner.soon) FontWeight.Bold else FontWeight.Normal),
                color = if (banner.soon) white else white.copy(alpha = 0.92f),
                modifier = Modifier.padding(top = 3.dp),
            )
        }
        if (banner.later.isNotEmpty()) {
            HorizontalDivider(color = white.copy(alpha = 0.3f))
            banner.later.forEachIndexed { i, x ->
                if (i > 0) HorizontalDivider(color = white.copy(alpha = 0.18f))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = Dimens.touchTarget)
                        .clip(RoundedCornerShape(8.dp))
                        .clickable(role = Role.Button, onClickLabel = "Open details") { onTalk(x.session) }
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    CapsText(x.time, t.bannerTime.copy(letterSpacing = t.bannerCountdown.letterSpacing), color = white, maxLines = 1)
                    Spacer(Modifier.width(10.dp))
                    Text(
                        buildAnnotatedString {
                            append(x.session.title)
                            append(" ")
                            withStyle(SpanStyle(color = white.copy(alpha = 0.8f))) { append(x.roomName) }
                        },
                        style = t.small.copy(fontSize = 14.5.sp, lineHeight = 19.sp),
                        color = white,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

/** Web `.mine-h .cd`: white chip with pink text; pulses while the talk is soon or on. */
@Composable
private fun Countdown(text: String, pulse: Boolean) {
    val c = AppTheme.colors
    val scale = if (pulse) {
        val tr = rememberInfiniteTransition(label = "cd")
        tr.animateFloat(
            initialValue = 1f,
            targetValue = 1.08f,
            animationSpec = infiniteRepeatable(tween(800, easing = FastOutSlowInEasing), RepeatMode.Reverse),
            label = "cdScale",
        )
    } else {
        null
    }
    CapsText(
        text,
        AppTheme.type.bannerCountdown,
        Modifier
            .graphicsLayer {
                val s = scale?.value ?: 1f
                scaleX = s
                scaleY = s
            }
            .background(c.onYou, RoundedCornerShape(6.dp))
            .padding(start = 7.dp, end = 7.dp, top = 4.dp, bottom = 3.dp),
        color = c.you,
        maxLines = 1,
    )
}
