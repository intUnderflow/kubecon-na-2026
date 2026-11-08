package app.kcna26.ui.directions

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kcna26.route.FloorReminder
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.theme.caps
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * The header: "LEVEL 2 · SALT PALACE · 251 A–C" in large type (the engine's
 * [FloorReminder.headline], the web's `.loc`), with the level in pink so the floor stands out.
 */
@Composable
fun FloorHeadline(reminder: FloorReminder, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val levelLabel = reminder.levelLabel
    // Keep a short trailing part of a name ("251 A–C", "Room 151") on one line, so the
    // headline never wraps between "251" and "A–C" in the narrow two-column layout.
    val rest = reminder.buildingAndRoom.replace(SHORT_TAIL_SPACE, " ")
    val text = remember(reminder, colors) {
        buildAnnotatedString {
            if (levelLabel != null) {
                withStyle(SpanStyle(color = colors.you)) { append(levelLabel.caps()) }
                if (rest.isNotEmpty()) append(" · ")
            }
            append(rest.caps())
        }
    }
    Text(
        text,
        style = AppTheme.type.display.copy(fontSize = 30.sp, lineHeight = 32.sp),
        color = colors.ink,
        modifier = modifier.semantics { contentDescription = reminder.headline },
    )
}

/** A space before a 1–3 character word that ends a headline part ("251 A–C", "Room 151"). */
private val SHORT_TAIL_SPACE = Regex(""" (?=\S{1,3}(?: · |$))""")

/** "Room is on Level 2: take the North Foyer escalator up", with the up/down step icon. */
@Composable
fun FloorInstruction(reminder: FloorReminder, modifier: Modifier = Modifier) {
    val instruction = reminder.instruction ?: return
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        val dir = reminder.direction
        if (dir != null) {
            StepIcon(dir, Modifier.size(34.dp))
            Spacer(Modifier.width(10.dp))
        }
        Text(
            instruction,
            style = AppTheme.type.body.copy(fontSize = 17.sp, fontWeight = FontWeight.Bold),
            color = AppTheme.colors.ink,
        )
    }
}

/**
 * Everything under the map (the web's lvPaint #lv-d / #lv-s, without the arrow):
 * - the line: "120 M NORTH-EAST · ±12 M", "YOU’RE ABOUT HERE · ±10 M" or the state
 *   ("FINDING YOU…", "LOCATION IS OFF", "NO GPS FIX YET");
 * - the floor instruction;
 * - the floor reminder when about here, or what to do without a fix, plus [action]
 *   (allow location / turn it on);
 * - "GPS is weak indoors: follow the steps." above ±50 m;
 * - the small figure-8 hint while [calibrate] (the map's heading cone needs the compass).
 */
@Composable
fun LiveReadout(
    readout: Readout,
    floor: FloorReminder,
    action: Pair<String, () -> Unit>?,
    calibrate: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = AppTheme.colors
    val type = AppTheme.type
    val weak = readout.weakGps != null
    val line = remember(readout, colors) {
        buildAnnotatedString {
            withStyle(SpanStyle(color = if (readout.here) colors.you else colors.ink)) { append(readout.headline.caps()) }
            val acc = readout.accuracy
            if (acc != null) {
                withStyle(SpanStyle(color = colors.muted)) { append(" · ") }
                withStyle(SpanStyle(color = if (weak) colors.note else colors.muted)) { append(acc.caps()) }
            }
        }
    }
    Column(modifier.fillMaxWidth()) {
        Text(
            line,
            style = type.display.copy(fontSize = if (readout.hasFix) 32.sp else 28.sp, lineHeight = 34.sp),
            modifier = Modifier.semantics {
                liveRegion = LiveRegionMode.Polite
                contentDescription = readout.line
            },
        )
        // About here, a plain "Room is on Level 2" would repeat the pink reminder right below
        // it; an up/down instruction (escalator, stairs) still shows.
        if (!(readout.here && readout.detail != null && floor.action == null)) {
            FloorInstruction(floor, Modifier.padding(top = 10.dp))
        }
        readout.detail?.let {
            Text(
                it,
                style = if (readout.here) {
                    type.body.copy(fontSize = 16.sp, fontWeight = FontWeight.Bold)
                } else {
                    type.small.copy(fontSize = 15.sp)
                },
                color = if (readout.here) colors.you else colors.muted,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        readout.weakGps?.let {
            Text(
                it,
                style = type.small.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
                color = colors.note,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        if (action != null) {
            OutlinedButton(
                onClick = action.second,
                modifier = Modifier
                    .padding(top = 10.dp)
                    .heightIn(min = Dimens.touchTarget),
                shape = RoundedCornerShape(10.dp),
                border = BorderStroke(1.dp, colors.line),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.ink),
            ) {
                CapsText(action.first, type.button)
            }
        }
        CalibrationHint(calibrate, Modifier.padding(top = 8.dp))
    }
}

/** A small, unobtrusive figure-8 hint: the heading cone needs a calibrated compass. */
@Composable
fun CalibrationHint(visible: Boolean, modifier: Modifier = Modifier) {
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn() + expandVertically(),
        exit = fadeOut() + shrinkVertically(),
        modifier = modifier,
    ) {
        val colors = AppTheme.colors
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FigureEight(Modifier.size(width = 34.dp, height = 20.dp))
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = colors.ink)) { append(DirectionsText.CALIBRATE_TITLE) }
                    append(" ")
                    append(DirectionsText.CALIBRATE_BODY)
                },
                style = AppTheme.type.tiny,
                color = colors.muted,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/** A lemniscate with a small phone travelling along it. */
@Composable
private fun FigureEight(modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val t by rememberInfiniteTransition(label = "fig8").animateFloat(
        initialValue = 0f,
        targetValue = (2 * Math.PI).toFloat(),
        animationSpec = infiniteRepeatable(tween(2400, easing = LinearEasing), RepeatMode.Restart),
        label = "fig8t",
    )
    Canvas(modifier) {
        val a = size.width / 2f - 4.dp.toPx()
        val c = Offset(size.width / 2f, size.height / 2f)
        fun at(u: Double): Offset {
            val s = sin(u)
            val d = 1 + s * s
            return Offset(c.x + (a * cos(u) / d).toFloat(), c.y + (a * s * cos(u) / d).toFloat() * 1.3f)
        }
        val path = Path().apply {
            val n = 48
            for (i in 0..n) {
                val p = at(2 * Math.PI * i / n)
                if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y)
            }
            close()
        }
        drawPath(path, colors.note, style = Stroke(1.6.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        val p = at(t.toDouble())
        val q = at(t.toDouble() + 0.05)
        val deg = Math.toDegrees(atan2((q.y - p.y).toDouble(), (q.x - p.x).toDouble())).toFloat()
        val w = 6.dp.toPx()
        val h = 10.dp.toPx()
        rotate(deg + 90f, pivot = p) {
            drawRoundRect(colors.ink, topLeft = Offset(p.x - w / 2, p.y - h / 2), size = Size(w, h), cornerRadius = CornerRadius(1.5.dp.toPx()))
        }
    }
}
