package app.kcna26.ui.going

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.rounded.NotificationsOff
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.data.Session
import app.kcna26.going.Clash
import app.kcna26.going.GoingLogic
import app.kcna26.going.GoingNext
import app.kcna26.going.GoingStore
import app.kcna26.going.GoingText
import app.kcna26.going.NotificationAsk
import app.kcna26.going.rememberNotificationsBlocked
import app.kcna26.reminders.ReminderNotifier
import app.kcna26.reminders.ReminderPlanner
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.schedule.ScheduleLogic
import app.kcna26.theme.AppColors
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.theme.mix
import app.kcna26.time.TimeFormat
import app.kcna26.time.rememberNowState
import app.kcna26.ui.schedule.cardSurface

/*
 * "Going" UI: the star toggle on cards, the day header's Going chip, the "Up next" row, the
 * details' Going button and clash note, the Settings reminder choice and the inline
 * notifications-off hint. Quiet ink accents, never the pink "You" treatment.
 */

/**
 * Starred card fill. Light: the plain surface (an ink tint lands on the page colour and reads as
 * greyed out), so the border and the filled star carry it. Dark: a faint ink lift.
 */
internal val AppColors.goingCardBg: Color get() = if (isDark) mix(ink, surface, 0.045f) else surface

/** Starred card border: ink 60% into the hairline in light (the main cue there), 40% in dark. */
internal val AppColors.goingCardBorder: Color get() = mix(ink, line, if (isDark) 0.40f else 0.60f)

/** Starred kid row inside a group card: a faint ink lift in dark only (in light it would look pressed). */
internal val AppColors.goingRowBg: Color get() = if (isDark) ink.copy(alpha = 0.055f) else Color.Transparent

/** Starred kid row: the ink rule down its left edge, in both themes. */
internal val AppColors.goingRule: Color get() = mix(ink, line, 0.60f)

/** "Clash" tag and note: the hands-on amber (as "Sold out"). */
internal val AppColors.clash: Color get() = note
internal val AppColors.clashBg: Color get() = mix(note, surface, 0.08f)
internal val AppColors.clashBorder: Color get() = mix(note, line, 0.45f)

/**
 * The 48 dp star toggle. Outlined in muted ink when not going, filled ink when going; white on
 * my own pink cards ([onCard]). TalkBack: "Mark as going: <[label]>" / "Going: <[label]>", as a
 * checkbox, so each star in a list says which session it is for.
 */
@Composable
internal fun StarToggle(
    going: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    onCard: Boolean = false,
    iconSize: Dp = 23.dp,
) {
    val c = AppTheme.colors
    val haptics = LocalHapticFeedback.current
    val tint = when {
        onCard -> if (going) c.onYou else c.onYou.copy(alpha = 0.8f)
        going -> c.ink
        else -> c.muted
    }
    Box(
        modifier
            .size(Dimens.touchTarget)
            .toggleable(
                value = going,
                interactionSource = null,
                indication = ripple(bounded = false, radius = 20.dp),
                role = Role.Checkbox,
            ) {
                haptics.performHapticFeedback(if (it) HapticFeedbackType.ToggleOn else HapticFeedbackType.ToggleOff)
                onToggle()
            }
            .semantics { contentDescription = GoingText.starDescription(going, label) },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (going) Icons.Rounded.Star else Icons.Rounded.StarBorder,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(iconSize),
        )
    }
}

/** Space a card keeps free at its top-right corner for the [GoingStarFrame] star. */
internal val StarReserve: Dp = 34.dp

/** A session card with the star toggle over its top-right corner ([content] keeps [StarReserve] free). */
@Composable
internal fun GoingStarFrame(
    going: Boolean,
    onToggle: () -> Unit,
    onCard: Boolean,
    label: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(modifier) {
        content()
        StarToggle(going, onToggle, Modifier.align(Alignment.TopEnd), label = label, onCard = onCard)
    }
}

/** Small non-interactive filled star (group card header: one of its sessions is starred). */
@Composable
internal fun GoingMark(description: String, modifier: Modifier = Modifier) {
    Icon(
        Icons.Rounded.Star,
        contentDescription = description,
        tint = AppTheme.colors.ink,
        modifier = modifier.size(17.dp),
    )
}

/** The day header's "Going" filter chip: only starred sessions and my talks. Ink when on. */
@Composable
internal fun GoingChip(on: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val shape = RoundedCornerShape(8.dp)
    val haptics = LocalHapticFeedback.current
    val fg = if (on) c.bg else c.ink
    Row(
        modifier
            .minimumInteractiveComponentSize()
            .clip(shape)
            .background(if (on) c.ink else c.surface)
            .border(1.dp, if (on) c.ink else c.line, shape)
            .toggleable(value = on, role = Role.Checkbox) {
                haptics.performHapticFeedback(if (it) HapticFeedbackType.ToggleOn else HapticFeedbackType.ToggleOff)
                onToggle()
            }
            .semantics { contentDescription = GoingText.CHIP_DESCRIPTION }
            .padding(start = 9.dp, end = 11.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (on) Icons.Rounded.Star else Icons.Rounded.StarBorder,
            contentDescription = null,
            tint = fg,
            modifier = Modifier.size(17.dp),
        )
        Spacer(Modifier.width(5.dp))
        CapsText(GoingText.CHIP, AppTheme.type.button.copy(fontSize = 14.sp, lineHeight = 16.sp), color = fg, maxLines = 1)
    }
}

/**
 * My next (or live) starred session today, compact enough for the cover screen: "Your next ·
 * in 12 min" or "On now · 8 min left" (not "Up next", which is the timeline line's name).
 * Tapping the text opens the session; the walk button opens Directions.
 */
@Composable
internal fun GoingNextCard(
    next: GoingNext,
    onOpen: () -> Unit,
    onDirections: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val shape = RoundedCornerShape(Dimens.cardRadius)
    val s = next.session
    Row(
        modifier
            .padding(top = 12.dp)
            .fillMaxWidth()
            .clip(shape)
            .cardSurface(fill = c.goingCardBg, border = c.goingCardBorder, stripe = c.ink),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            Modifier
                .weight(1f)
                .clickable(role = Role.Button, onClickLabel = "Open details", onClick = onOpen)
                .padding(start = Dimens.categoryStripe + 12.dp, end = 8.dp, top = 9.dp, bottom = 10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Star, contentDescription = null, tint = c.ink, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(5.dp))
                CapsText(next.label, t.bannerLabel, Modifier.semantics { heading() }, color = c.ink, maxLines = 1)
                Spacer(Modifier.width(8.dp))
                CapsText(
                    next.countdown,
                    t.bannerLabel,
                    Modifier.weight(1f, fill = false),
                    color = if (next.live) c.you else c.muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                s.title,
                style = t.cardTitle,
                color = c.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 3.dp),
            )
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.ink)) { append(next.time) }
                    append(" · ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.ink)) { append(next.roomName) }
                    next.level?.let {
                        append(" · ")
                        append(it)
                    }
                },
                style = t.small,
                color = c.muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 3.dp),
            )
        }
        if (next.canRoute) {
            Box(
                Modifier
                    .padding(end = 10.dp)
                    .size(Dimens.touchTarget)
                    .clip(RoundedCornerShape(Dimens.cardRadius))
                    .background(c.ink)
                    .clickable(role = Role.Button, onClick = onDirections)
                    .semantics { contentDescription = "Directions to ${next.roomName}" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Filled.DirectionsWalk, contentDescription = null, tint = c.bg, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/**
 * The details' "Going" toggle, as tall as the Directions button beside it: outlined star when
 * not going ("Mark as going"), filled star on an ink-tinted fill when going ("Going"). Nothing
 * for break rows.
 */
@Composable
internal fun GoingToggleButton(session: Session, modifier: Modifier = Modifier) {
    val graph = LocalAppGraph.current
    val index = remember(graph.repository) { ScheduleIndex.of(graph.repository) }
    if (index.isBreak(session)) return
    val ids by graph.going.ids.collectAsStateWithLifecycle()
    val going = session.id in ids
    val c = AppTheme.colors
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(Dimens.cardRadius)
    Row(
        modifier
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(if (going) mix(c.ink, c.surface, 0.09f) else c.surface)
            .border(if (going) 2.dp else 1.dp, if (going) c.ink else c.line, shape)
            .toggleable(value = going, role = Role.Checkbox) {
                haptics.performHapticFeedback(if (it) HapticFeedbackType.ToggleOn else HapticFeedbackType.ToggleOff)
                graph.going.setGoing(session.id, it)
            }
            .semantics { contentDescription = if (going) GoingText.GOING else GoingText.MARK }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (going) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                contentDescription = null,
                tint = c.ink,
                modifier = Modifier.size(22.dp),
            )
            Spacer(Modifier.width(8.dp))
            CapsText(if (going) GoingText.GOING else GoingText.MARK, AppTheme.type.button.copy(fontSize = 18.sp), color = c.ink, maxLines = 1)
        }
    }
}

/** The details' "Clash" note: what this starred session overlaps (other starred sessions, my talks). */
@Composable
internal fun GoingClashNote(session: Session, modifier: Modifier = Modifier) {
    val graph = LocalAppGraph.current
    val ids by graph.going.ids.collectAsStateWithLifecycle()
    if (session.id !in ids) return
    val me by graph.settings.speakingAs.collectAsStateWithLifecycle()
    val nowState = rememberNowState(graph.clock)
    val minute by remember(nowState) { derivedStateOf { ScheduleLogic.minuteOf(nowState.value) } }
    val repo = graph.repository
    val index = remember(repo) { ScheduleIndex.of(repo) }
    val clashes = remember(index, session, ids, me, minute) { GoingLogic.clashesFor(index, session, ids, me, minute) }
    if (clashes.isEmpty()) return
    ClashNote(clashes, index, repo.days.associate { it.key to it.dow }, session.day, modifier)
}

@Composable
private fun ClashNote(clashes: List<Clash>, index: ScheduleIndex, dows: Map<String, String>, day: String, modifier: Modifier) {
    val c = AppTheme.colors
    val t = AppTheme.type
    val shape = RoundedCornerShape(Dimens.cardRadius)
    Column(
        modifier
            .padding(top = 12.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(c.clashBg)
            .border(1.dp, c.clashBorder, shape)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ClashTag()
            Spacer(Modifier.width(8.dp))
            CapsText(GoingText.CLASHES_WITH, t.sectionLabel, Modifier.semantics { heading() }, color = c.muted, maxLines = 1)
        }
        for (cl in clashes) {
            val s = cl.session
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        if (s.day != day) dows[s.day]?.let { append("$it ") }
                        append(TimeFormat.range(s))
                    }
                    append(" · ")
                    if (cl.mine) {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.you)) { append(GoingText.YOUR_TALK) }
                        append(": ")
                    }
                    append(s.title)
                    withStyle(SpanStyle(color = c.muted)) {
                        append(" · ")
                        append(index.roomName(s.room))
                    }
                },
                style = t.small.copy(fontSize = 14.5.sp, lineHeight = 19.sp),
                color = c.ink,
            )
        }
    }
}

/** The "Clash" tag (amber, like the web's notes), for cards and the details. */
@Composable
internal fun ClashTag(modifier: Modifier = Modifier, onCard: Boolean = false) {
    val c = AppTheme.colors
    CapsText(
        GoingText.CLASH,
        AppTheme.type.pill,
        modifier
            .background(if (onCard) c.onYou else c.clash, RoundedCornerShape(5.dp))
            .padding(start = 6.dp, end = 6.dp, top = 2.dp, bottom = 1.dp),
        color = if (onCard) c.you else c.surface,
        maxLines = 1,
    )
}

/**
 * Under the details' buttons: the notifications-off hint, when this session has a reminder to
 * come (mine, or starred with reminders on) and the app's notifications are off. A channel
 * the user turned off on purpose is only mentioned in Settings.
 */
@Composable
internal fun GoingReminderHint(session: Session, modifier: Modifier = Modifier) {
    val graph = LocalAppGraph.current
    val ids by graph.going.ids.collectAsStateWithLifecycle()
    val minutes by graph.going.remindMinutes.collectAsStateWithLifecycle()
    val me by graph.settings.speakingAs.collectAsStateWithLifecycle()
    val spec = ReminderPlanner.specFor(session, me, ids, minutes) ?: return
    val now by rememberNowState(graph.clock)
    if (!session.start.isAfter(now)) return
    NotificationsOffHint(ReminderNotifier.channelFor(spec.kind), modifier)
}

/** The "Sessions you’re going to" notification channel, for [NotificationsOffHint]. */
internal const val GOING_CHANNEL: String = ReminderNotifier.GOING_CHANNEL_ID

/**
 * "Notifications are off for this app…" with a button to the notification settings; nothing
 * when they're on (or while the permission is still to be asked, or its dialog is up). With
 * [channelLevel], also says when only [channelId] is turned off ("Reminders for sessions
 * you’re going to are turned off."): Settings, where that choice belongs.
 */
@Composable
internal fun NotificationsOffHint(channelId: String, modifier: Modifier = Modifier, channelLevel: Boolean = false) {
    val text = when (rememberNotificationsBlocked(channelId)) {
        NotificationAsk.Block.APP -> GoingText.NOTIFICATIONS_OFF
        NotificationAsk.Block.CHANNEL -> if (!channelLevel) {
            null
        } else if (channelId == ReminderNotifier.GOING_CHANNEL_ID) {
            GoingText.GOING_CHANNEL_OFF
        } else {
            GoingText.TALKS_CHANNEL_OFF
        }
        NotificationAsk.Block.NONE -> null
    } ?: return
    val c = AppTheme.colors
    val context = LocalContext.current
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(c.clashBg)
            .padding(start = 12.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.NotificationsOff, contentDescription = null, tint = c.clash, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(
            text,
            style = AppTheme.type.small,
            color = c.ink,
            modifier = Modifier
                .weight(1f)
                .padding(vertical = 8.dp),
        )
        TextButton(onClick = { NotificationAsk.openSettings(context, channelId) }) {
            CapsText(GoingText.TURN_ON, AppTheme.type.button, color = c.ink, maxLines = 1)
        }
    }
}

/** Settings: "Remind me before sessions I’m going to": Off / 5 / 10 / 15 min (default 10). */
@Composable
internal fun GoingReminderSetting(modifier: Modifier = Modifier) {
    val graph = LocalAppGraph.current
    val going = graph.going
    val minutes by going.remindMinutes.collectAsStateWithLifecycle()
    val me by graph.settings.speakingAs.collectAsStateWithLifecycle()
    val c = AppTheme.colors
    val t = AppTheme.type
    val shape = RoundedCornerShape(Dimens.cardRadius)
    Column(modifier) {
        CapsText("RSVPs", t.sectionLabel, Modifier.semantics { heading() }, color = c.muted)
        Text(
            GoingText.SETTING_TITLE,
            style = t.body.copy(fontWeight = FontWeight.Bold),
            color = c.ink,
            modifier = Modifier.padding(top = 8.dp),
        )
        Row(
            Modifier
                .padding(top = 10.dp)
                .fillMaxWidth()
                .selectableGroup(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            for (m in GoingStore.REMIND_OPTIONS) {
                val on = m == minutes
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = Dimens.touchTarget)
                        .clip(shape)
                        .background(if (on) c.ink else c.surface)
                        .border(1.dp, if (on) c.ink else c.line, shape)
                        .selectable(selected = on, role = Role.RadioButton) { going.setRemindMinutes(m) },
                    contentAlignment = Alignment.Center,
                ) {
                    CapsText(GoingText.optionLabel(m), t.button, color = if (on) c.bg else c.ink, maxLines = 1)
                }
            }
        }
        Text(
            GoingText.settingSummary(minutes, me),
            style = t.small,
            color = c.muted,
            modifier = Modifier.padding(top = 8.dp),
        )
        val channel = when {
            minutes > 0 -> ReminderNotifier.GOING_CHANNEL_ID
            me != null -> ReminderNotifier.CHANNEL_ID
            else -> null
        }
        if (channel != null) NotificationsOffHint(channel, Modifier.padding(top = 10.dp), channelLevel = true)
    }
}
