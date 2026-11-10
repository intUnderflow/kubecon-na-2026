package app.kcna26.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.BorderStroke
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.settings.SettingsStore
import app.kcna26.theme.AppTheme
import app.kcna26.theme.Dimens
import kotlinx.coroutines.launch

/**
 * First-run picker: "Speaking at KubeCon? Pick your name", over the schedule while
 * [SettingsStore.firstRunPending]. The same searchable speaker list as Settings; picking a
 * name sets "I'm speaking as" (and so the reminders), Skip leaves it at None. Either way it
 * never shows again. Swiping it away (or Back, or a tap outside) only hides it until the next
 * cold start, since that is easy to do by accident ([SettingsStore.dismissFirstRunForNow]).
 *
 * One-handed: the search field and Skip sit at the bottom, under the list. TalkBack reads the
 * title, the description, search and Skip first, then the list (traversal order), so nobody has
 * to swipe through every speaker to reach them. While the keyboard is up the title and
 * description are hidden, so the list keeps its room with large text or in landscape.
 * Visibility comes from the settings store and the search text and scroll position are
 * saveable, so it survives fold/unfold. Call once, from the root, after the data has loaded.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun FirstRunSpeakerSheet() {
    val graph = LocalAppGraph.current
    val settings = graph.settings
    val pending by settings.firstRunPending.collectAsStateWithLifecycle()
    if (!pending) return

    val repo = graph.repository
    val options = remember(repo) { SpeakerPicker.options(repo) }
    val search = rememberTextFieldState()
    val terms by remember(search) { derivedStateOf { SpeakerPicker.terms(search.text.toString()) } }
    val shown = remember(options, terms) { SpeakerPicker.filter(options, terms, null) }
    val listState = rememberLazyListState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val c = AppTheme.colors
    val t = AppTheme.type

    val finish: (String?) -> Unit = { name ->
        focus.clearFocus()
        scope.launch { sheetState.hide() }.invokeOnCompletion { settings.finishFirstRun(name) }
    }

    ModalBottomSheet(
        onDismissRequest = settings::dismissFirstRunForNow,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = Dimens.sheetRadius, topEnd = Dimens.sheetRadius),
        containerColor = c.bg,
        contentColor = c.ink,
        scrimColor = c.scrim,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.9f)
                .padding(horizontal = Dimens.pagePadding)
                .semantics { isTraversalGroup = true },
        ) {
            if (!WindowInsets.isImeVisible) {
                Text(
                    "Speaking at KubeCon? Pick your name",
                    style = t.sheetTitle,
                    color = c.ink,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    "Your talks get the pinned banner, the pink highlight and reminders 30 and 10 minutes " +
                        "before. You can change this any time in Settings.",
                    style = t.small,
                    color = c.muted,
                    modifier = Modifier.padding(top = 6.dp, bottom = 8.dp),
                )
            }
            HorizontalDivider(color = c.line)
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    // After search and Skip in TalkBack's order (they are below it on screen).
                    .semantics { isTraversalGroup = true; traversalIndex = 1f },
                contentPadding = PaddingValues(bottom = 8.dp),
            ) {
                items(shown, key = { "sp-" + it.name }, contentType = { "option" }) { o ->
                    PickRow(o.name, o.summary, onClick = { finish(o.name) })
                }
                if (shown.isEmpty()) {
                    item(key = "nomatch", contentType = "note") {
                        Text(
                            "No speaker matches “${search.text.toString().trim()}”.",
                            style = t.body,
                            color = c.muted,
                            modifier = Modifier.padding(vertical = 16.dp),
                        )
                    }
                }
            }
            Column(
                Modifier
                    .padding(top = 8.dp, bottom = 12.dp)
                    .semantics { isTraversalGroup = true },
            ) {
                SpeakerSearchField(search)
                OutlinedButton(
                    onClick = { finish(null) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp)
                        .heightIn(min = Dimens.touchTarget),
                    border = BorderStroke(1.dp, c.line),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = c.ink),
                ) {
                    Text("Skip", style = t.button)
                }
            }
        }
    }
}

/** A speaker row that picks the name and closes the sheet: a button, not a radio button. */
@Composable
private fun PickRow(title: String, subtitle: String, onClick: () -> Unit) {
    val c = AppTheme.colors
    val t = AppTheme.type
    Column {
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clickable(role = Role.Button, onClick = onClick)
                .padding(vertical = 8.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(title, style = t.body, color = c.ink)
            if (subtitle.isNotEmpty()) Text(subtitle, style = t.tiny, color = c.muted)
        }
        HorizontalDivider(color = c.line)
    }
}
