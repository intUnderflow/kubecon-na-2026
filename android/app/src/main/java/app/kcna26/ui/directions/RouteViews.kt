package app.kcna26.ui.directions

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.MeetingRoom
import androidx.compose.material.icons.outlined.MyLocation
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.kcna26.route.Step
import app.kcna26.route.StepKind
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens

/** The web's step ICON shapes (24-unit box) as Compose paths, parsed once (main thread only). */
private object StepPaths {
    val walk: Path by lazy { parse(MapGeometry.ICON_WALK) }
    val up: Path by lazy { parse(MapGeometry.ICON_UP) }
    val down: Path by lazy { parse(MapGeometry.ICON_DOWN) }
    val end: Path by lazy { parse(MapGeometry.ICON_END) }

    private fun parse(d: String): Path = PathParser().parsePathString(d).toPath()
}

/** A step-kind icon in its 34 dp circle (.steps .ic): start dot, walk arrow, up/down stairs, end pin. */
@Composable
fun StepIcon(kind: StepKind, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val (bg, fg) = when (kind) {
        StepKind.UP, StepKind.DOWN -> colors.ink to colors.bg
        StepKind.END -> colors.you to colors.onYou
        else -> colors.bg to colors.ink
    }
    val hole = colors.surface
    Canvas(modifier.size(34.dp)) {
        drawCircle(bg)
        val box = 20.dp.toPx()
        val k = box / 24f
        translate((size.width - box) / 2f, (size.height - box) / 2f) {
            scale(k, k, pivot = Offset.Zero) {
                when (kind) {
                    StepKind.START -> drawCircle(fg, radius = 5f, center = Offset(12f, 12f))
                    StepKind.WALK -> drawPath(StepPaths.walk, fg, style = iconStroke(2.4f))
                    StepKind.UP -> drawPath(StepPaths.up, fg, style = iconStroke(2.2f))
                    StepKind.DOWN -> drawPath(StepPaths.down, fg, style = iconStroke(2.2f))
                    StepKind.END -> {
                        drawPath(StepPaths.end, fg)
                        drawCircle(hole, radius = 2.2f, center = Offset(12f, 11f))
                    }
                }
            }
        }
    }
}

private fun iconStroke(width: Float) = Stroke(width = width, cap = StrokeCap.Round, join = StrokeJoin.Round)

/** Turn-by-turn steps (.steps): icon, text, dotted connector between items; the end step is bold. */
@Composable
fun StepsList(steps: List<Step>, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        steps.forEachIndexed { i, step ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .then(
                        if (i == 0) Modifier else Modifier.drawWithCache {
                            // CSS `border-left: 2px dotted`: round 2 dp dots between the icons.
                            val dot = 2.dp.toPx()
                            val dots = PathEffect.dashPathEffect(floatArrayOf(0.01f, dot * 2f))
                            val x = 17.dp.toPx()
                            val y0 = -6.dp.toPx() + dot / 2f
                            val y1 = 6.dp.toPx()
                            onDrawBehind {
                                drawLine(colors.line, Offset(x, y0), Offset(x, y1), strokeWidth = dot, cap = StrokeCap.Round, pathEffect = dots)
                            }
                        },
                    )
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                StepIcon(step.kind)
                Spacer(Modifier.width(10.dp))
                Text(
                    step.text,
                    style = AppTheme.type.step.copy(
                        fontWeight = if (step.kind == StepKind.END) FontWeight.Bold else FontWeight.Normal,
                    ),
                    color = colors.ink,
                    modifier = Modifier
                        .weight(1f)
                        .padding(top = 6.dp),
                )
            }
        }
    }
}

/**
 * The From picker (web: `<label>From <select>`). The field shows the chosen option's name. The
 * open menu lists My location (GPS) first, then [menu]: with a fix, every entrance and room in one
 * list, nearest first, each with an entrance/room icon, its distance and level; without one, the
 * entrances then the rooms by name, as before. The chosen option keeps its checkmark wherever it
 * sorts.
 *
 * The screen builds [menu] when the menu opens and keeps it while it's open, so fixes never move
 * items. The open state is hoisted ([expanded]/[onExpandedChange]) to the screen, above its
 * compact/wide branch, so an open picker stays open, in the same order, across fold/unfold. The
 * menu scrolls, at most 60 % of the window high ([MENU_MIN_HEIGHT]..[MENU_MAX_HEIGHT]), and opens
 * at the top each time.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FromPicker(
    options: FromOptions,
    menu: FromMenu,
    selected: String,
    onSelect: (String) -> Unit,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AppTheme.colors
    // A new scroll position per opening: a re-sorted list starts with the nearest options.
    var scroll by remember { mutableStateOf(ScrollState(0)) }
    val maxHeight = (LocalWindowInfo.current.containerDpSize.height * 0.6f).coerceIn(MENU_MIN_HEIGHT, MENU_MAX_HEIGHT)
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { open ->
            if (open && !expanded) scroll = ScrollState(0)
            onExpandedChange(open)
        },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = options.label(selected),
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text(DirectionsText.FROM) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            textStyle = AppTheme.type.body,
            shape = RoundedCornerShape(8.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = colors.surface,
                unfocusedContainerColor = colors.surface,
                focusedBorderColor = colors.ink,
                unfocusedBorderColor = colors.line,
                focusedLabelColor = colors.muted,
                unfocusedLabelColor = colors.muted,
                focusedTextColor = colors.ink,
                unfocusedTextColor = colors.ink,
            ),
            modifier = Modifier
                .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
                .fillMaxWidth()
                .heightIn(min = 56.dp),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { onExpandedChange(false) },
            modifier = Modifier.heightIn(max = maxHeight),
            scrollState = scroll,
            containerColor = colors.surface,
            // The menu's surface matches the card under it; a hairline keeps it separate in dark.
            border = BorderStroke(1.dp, colors.line),
        ) {
            val pick = { key: String ->
                onExpandedChange(false)
                onSelect(key)
            }
            if (menu.byDistance) {
                NearestItem(FromMenuItem(menu.live), menu.live.key == selected, pick)
                for (section in menu.sections) {
                    MenuHeader(section.title)
                    section.items.forEach { NearestItem(it, it.key == selected, pick) }
                }
            } else {
                FromItem(menu.live, menu.live.key == selected, pick)
                for (section in menu.sections) {
                    MenuHeader(section.title)
                    section.items.forEach { FromItem(it.option, it.key == selected, pick) }
                }
            }
        }
    }
}

/** Cap on the open From menu's height (it also stays inside the space the window has left). */
private val MENU_MAX_HEIGHT = 480.dp
private val MENU_MIN_HEIGHT = 200.dp

@Composable
private fun MenuHeader(text: String) {
    CapsText(
        text,
        AppTheme.type.sectionLabel,
        color = AppTheme.colors.muted,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 6.dp),
    )
}

@Composable
private fun FromItem(option: FromOption, selected: Boolean, onPick: (String) -> Unit) {
    val colors = AppTheme.colors
    DropdownMenuItem(
        text = {
            Text(
                option.label,
                style = AppTheme.type.body.copy(fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal),
            )
        },
        onClick = { onPick(option.key) },
        trailingIcon = if (selected) {
            { Icon(Icons.Filled.Check, contentDescription = null, tint = colors.you) }
        } else {
            null
        },
        colors = MenuDefaults.itemColors(textColor = colors.ink),
        modifier = Modifier
            .heightIn(min = Dimens.touchTarget)
            .semantics { this.selected = selected },
        contentPadding = MenuDefaults.DropdownMenuItemContentPadding,
    )
}

/**
 * A row of the nearest-first menu: the kind icon (my location, entrance or room), the name, and
 * under it "40 m · L2"; the checkmark slot is always there so the rows line up.
 */
@Composable
private fun NearestItem(item: FromMenuItem, selected: Boolean, onPick: (String) -> Unit) {
    val colors = AppTheme.colors
    val option = item.option
    val details = listOfNotNull(item.distance, item.level).joinToString(" · ")
    DropdownMenuItem(
        text = {
            Column(Modifier.padding(vertical = 6.dp)) {
                Text(
                    option.label,
                    style = AppTheme.type.body.copy(fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (details.isNotEmpty()) {
                    Text(
                        details,
                        style = AppTheme.type.small.copy(fontFeatureSettings = "tnum"),
                        color = colors.muted,
                        maxLines = 1,
                        modifier = Modifier.semantics {
                            contentDescription = listOfNotNull(item.distance, option.level?.let { "Level $it" }).joinToString(", ")
                        },
                    )
                }
            }
        },
        onClick = { onPick(option.key) },
        leadingIcon = {
            Icon(
                option.kind.icon,
                contentDescription = option.kind.description,
                tint = colors.muted,
                modifier = Modifier.size(20.dp),
            )
        },
        trailingIcon = {
            Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = colors.you)
            }
        },
        colors = MenuDefaults.itemColors(textColor = colors.ink),
        modifier = Modifier
            .heightIn(min = Dimens.touchTarget)
            .semantics { this.selected = selected },
        contentPadding = MenuDefaults.DropdownMenuItemContentPadding,
    )
}

private val FromKind.icon: ImageVector
    get() = when (this) {
        FromKind.LIVE -> Icons.Outlined.MyLocation
        FromKind.ENTRANCE -> Icons.AutoMirrored.Outlined.Login
        FromKind.ROOM -> Icons.Outlined.MeetingRoom
    }

/** Spoken before the name; "My location (GPS)" says it already. */
private val FromKind.description: String?
    get() = when (this) {
        FromKind.LIVE -> null
        FromKind.ENTRANCE -> DirectionsText.ENTRANCE
        FromKind.ROOM -> DirectionsText.ROOM
    }
