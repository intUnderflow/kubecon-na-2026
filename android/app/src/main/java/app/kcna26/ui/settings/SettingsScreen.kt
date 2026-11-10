package app.kcna26.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.ui.going.GoingReminderSetting

/**
 * Settings: "I’m speaking as" (default None; any speaker in the schedule,
 * searchable), and where the schedule data came from ([DataSourceRow]).
 * Choosing a speaker updates everything "mine" at once: the
 * banner, highlights, "You" labels and day-tab badges follow
 * `settings.speakingAs`, and the App reschedules the reminders whenever that
 * setting changes (KcnaApp → ReminderScheduler.reschedule). The theme follows
 * the system, so there is no control for it.
 *
 * On wide screens the content is one centred column (Dimens.maxTextWidth).
 * The picker's search text and scroll position survive fold/unfold.
 *
 * @param onBack go back (top-bar back button); system back is handled by the shell.
 */
@Composable
fun SettingsScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val graph = LocalAppGraph.current
    val repo = graph.repository
    val settings = graph.settings
    val me by settings.speakingAs.collectAsStateWithLifecycle()

    val options = remember(repo) { SpeakerPicker.options(repo) }
    val search = rememberTextFieldState()
    val terms by remember(search) { derivedStateOf { SpeakerPicker.terms(search.text.toString()) } }
    val shown = remember(options, terms) { SpeakerPicker.filter(options, terms, null) }
    val current = remember(options, me) { me?.let { name -> options.firstOrNull { it.name == name } } }
    val listState = rememberLazyListState()
    val focus = LocalFocusManager.current

    val choose: (String?) -> Unit = { name ->
        focus.clearFocus()
        if (name != me) settings.setSpeakingAs(name)
    }

    val c = AppTheme.colors
    val t = AppTheme.type
    val bottom = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(c.bg),
    ) {
        val side = max(Dimens.pagePadding, (maxWidth - Dimens.maxTextWidth) / 2)
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))
                    .padding(start = (side - 12.dp).coerceAtLeast(0.dp), end = side)
                    .heightIn(min = 56.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back", tint = c.ink)
                }
                Spacer(Modifier.width(4.dp))
                CapsText("Settings", t.dayHeading.copy(fontSize = 26.sp, lineHeight = 28.sp), Modifier.semantics { heading() }, color = c.ink)
            }
            HorizontalDivider(color = c.line)
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = side, end = side, bottom = bottom + 24.dp),
            ) {
                item(key = "going", contentType = "going") {
                    Column(Modifier.padding(top = 18.dp)) {
                        GoingReminderSetting() // "Remind me before sessions I’m going to": Off / 5 / 10 / 15 min
                        HorizontalDivider(color = c.line, modifier = Modifier.padding(top = 18.dp))
                    }
                }
                item(key = "data", contentType = "data") {
                    DataSourceRow(Modifier.padding(top = 18.dp))
                }
                item(key = "intro", contentType = "intro") {
                    Column(Modifier.padding(top = 18.dp)) {
                        CapsText("I’m speaking as", t.sectionLabel, Modifier.semantics { heading() }, color = c.muted)
                        Text(
                            me ?: "None",
                            style = t.sheetTitle,
                            color = if (me != null) c.you else c.ink,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                        Text(
                            when {
                                me == null -> "No talks are marked as yours, so there are no talk reminders."
                                current != null -> current.summary
                                else -> "Not on the schedule."
                            },
                            style = t.small,
                            color = c.muted,
                            modifier = Modifier.padding(top = 2.dp),
                        )
                        Text(
                            "Your talks get the pinned banner, the pink highlight, “You” in speaker lists, " +
                                "a mark on the day tab, and reminders 30 and 10 minutes before.",
                            style = t.body,
                            color = c.ink,
                            modifier = Modifier.padding(top = 12.dp),
                        )
                    }
                }
                stickyHeader(key = "search", contentType = "search") {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .background(c.bg)
                            .padding(top = 14.dp, bottom = 8.dp),
                    ) {
                        SpeakerSearchField(search)
                    }
                }
                item(key = "none", contentType = "option") {
                    OptionRow("None", "Don’t mark any talks as mine", selected = me == null, onClick = { choose(null) })
                }
                items(shown, key = { "sp-" + it.name }, contentType = { "option" }) { o ->
                    OptionRow(o.name, o.summary, selected = me == o.name, onClick = { choose(o.name) })
                }
                if (shown.isEmpty() && terms.isNotEmpty()) {
                    item(key = "nomatch", contentType = "note") {
                        Text(
                            "No speaker matches “${search.text.toString().trim()}”.",
                            style = t.body,
                            color = c.muted,
                            modifier = Modifier.padding(vertical = 16.dp),
                        )
                    }
                }
                item(key = "theme", contentType = "note") {
                    Text(
                        "Light and dark theme follow your system setting.",
                        style = t.small,
                        color = c.muted,
                        modifier = Modifier.padding(top = 24.dp),
                    )
                }
            }
        }
    }
}

/** A radio-style row: name, a muted summary line, and a pink check when selected. */
@Composable
private fun OptionRow(title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    val c = AppTheme.colors
    val t = AppTheme.type
    Column {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    style = t.body.copy(fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal),
                    color = if (selected) c.you else c.ink,
                )
                if (subtitle.isNotEmpty()) Text(subtitle, style = t.tiny, color = c.muted)
            }
            if (selected) {
                Icon(Icons.Rounded.Check, contentDescription = null, tint = c.you, modifier = Modifier.padding(start = 12.dp))
            }
        }
        HorizontalDivider(color = c.line)
    }
}

/** Search box for the speaker picker (same look as the schedule's). */
@Composable
internal fun SpeakerSearchField(state: TextFieldState) {
    val c = AppTheme.colors
    val keyboard = LocalSoftwareKeyboardController.current
    val shape = RoundedCornerShape(Dimens.cardRadius)
    BasicTextField(
        state = state,
        modifier = Modifier.fillMaxWidth(),
        textStyle = AppTheme.type.body.copy(color = c.ink),
        cursorBrush = SolidColor(c.you),
        lineLimits = TextFieldLineLimits.SingleLine,
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.Words,
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
                Box(
                    Modifier
                        .weight(1f)
                        .padding(vertical = 11.dp),
                ) {
                    if (state.text.isEmpty()) {
                        Text("Search speakers", style = AppTheme.type.body, color = c.muted, maxLines = 1)
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
