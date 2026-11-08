package app.kcna26.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kcna26.data.speakerLabel
import app.kcna26.theme.AppColors
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens

/** Web `.pill` / `.tag`: a small uppercase label. [border] draws an outline instead of a fill (`.tag`). */
@Composable
internal fun Pill(
    text: String,
    background: Color,
    content: Color,
    modifier: Modifier = Modifier,
    border: Color? = null,
    style: TextStyle = AppTheme.type.pill,
) {
    val shape = RoundedCornerShape(5.dp)
    val base = if (border != null) {
        modifier.drawWithContent {
            drawRoundRect(border, cornerRadius = CornerRadius(5.dp.toPx()), style = Stroke(1.dp.toPx()))
            drawContent()
        }
    } else {
        modifier.background(background, shape)
    }
    CapsText(
        text,
        style,
        base.padding(start = 6.dp, end = 6.dp, top = 2.dp, bottom = 1.dp),
        color = content,
        maxLines = 1,
    )
}

/**
 * The card surface of the web's `.card`: [fill], a 1 dp [border], a [stripe]
 * down the left edge (`border-left: 4px`), an optional live progress bar along
 * the bottom (`.bar`), and a 2 dp [ring] when the card is selected in the
 * list–detail layout. Drawn in one pass; the caller clips to the same shape.
 */
internal fun Modifier.cardSurface(
    fill: Color,
    border: Color,
    stripe: Color,
    progress: Float? = null,
    progressColor: Color = Color.Unspecified,
    ring: Color? = null,
    radius: Dp = Dimens.cardRadius,
): Modifier = drawWithContent {
    val r = CornerRadius(radius.toPx())
    drawRoundRect(fill, cornerRadius = r)
    val bw = 1.dp.toPx()
    drawRoundRect(
        border,
        topLeft = Offset(bw / 2, bw / 2),
        size = Size(size.width - bw, size.height - bw),
        cornerRadius = CornerRadius(r.x - bw / 2),
        style = Stroke(bw),
    )
    drawRect(stripe, size = Size(Dimens.categoryStripe.toPx(), size.height))
    if (progress != null && progress > 0f) {
        val h = 3.dp.toPx()
        drawRect(progressColor, topLeft = Offset(0f, size.height - h), size = Size(size.width * progress, h))
    }
    drawContent()
    if (ring != null) {
        val rw = 2.dp.toPx()
        drawRoundRect(
            ring,
            topLeft = Offset(rw / 2, rw / 2),
            size = Size(size.width - rw, size.height - rw),
            cornerRadius = CornerRadius(r.x - rw / 2),
            style = Stroke(rw),
        )
    }
}

/** Web `.lrow` / `.empty`: a dashed outline. */
internal fun Modifier.dashedOutline(color: Color, radius: Dp): Modifier = drawWithContent {
    val w = 1.dp.toPx()
    drawRoundRect(
        color,
        topLeft = Offset(w / 2, w / 2),
        size = Size(size.width - w, size.height - w),
        cornerRadius = CornerRadius(radius.toPx()),
        style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
    )
    drawContent()
}

/** Web `.slot>h3` / `.sect>h3`: uppercase heading with a hairline running to the right edge. Sticky in the list. */
@Composable
internal fun RuledHeading(text: String, modifier: Modifier = Modifier, topPadding: Dp = 10.dp) {
    val c = AppTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .background(c.bg)
            .padding(top = topPadding, bottom = 7.dp)
            .semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CapsText(text, AppTheme.type.slotHeading, color = c.ink, maxLines = 1)
        Spacer(Modifier.width(10.dp))
        Box(
            Modifier
                .weight(1f)
                .height(1.dp)
                .background(c.line),
        )
    }
}

/** Web `.nowline`: pink "UP NEXT" with a 2 dp rule. */
@Composable
internal fun UpNextLine(modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .padding(top = 14.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CapsText("Up next", AppTheme.type.nowLine, color = c.you)
        Spacer(Modifier.width(8.dp))
        Box(
            Modifier
                .weight(1f)
                .height(2.dp)
                .background(c.you),
        )
    }
}

/** Web `.empty`: "That’s a wrap for today" / "No matches". */
@Composable
internal fun EmptyState(title: String, text: String, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    Column(
        modifier
            .padding(vertical = 28.dp)
            .fillMaxWidth()
            .dashedOutline(c.line, 12.dp)
            .padding(horizontal = 18.dp, vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CapsText(
            title,
            AppTheme.type.slotHeading.copy(fontSize = 20.sp, lineHeight = 22.sp, letterSpacing = AppTheme.type.brand.letterSpacing),
            color = c.ink,
        )
        Spacer(Modifier.height(4.dp))
        Text(text, style = AppTheme.type.body, color = c.muted, textAlign = TextAlign.Center)
    }
}

/** Web footer under the list. */
@Composable
internal fun ScheduleFooter(modifier: Modifier = Modifier) {
    Text(
        "Times are MST. Finished sessions disappear on their own. Schedule copied from the official KubeCon and " +
            "Maintainer Summit agendas on Nov 8 at 9:20 AM; “~” durations are estimates.",
        style = AppTheme.type.small.copy(fontSize = 13.5.sp),
        color = AppTheme.colors.muted,
        modifier = modifier
            .padding(top = 36.dp, bottom = 24.dp)
            .widthIn(max = Dimens.maxTextWidth),
    )
}

/**
 * Web `who(x)`: speakers joined by ", ", with me shown as bold "You" and
 * Anthropic colleagues in bold clay. On my own (pink) cards every bold name is
 * white ([onMine]).
 */
internal fun speakersLine(
    speakers: List<String>,
    me: String?,
    anthropic: Set<String>,
    colors: AppColors,
    onMine: Boolean,
): AnnotatedString = buildAnnotatedString {
    speakers.forEachIndexed { i, n ->
        if (i > 0) append(", ")
        when {
            me != null && n == me -> withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = if (onMine) colors.onYou else Color.Unspecified)) {
                append(speakerLabel(n, me))
            }
            n in anthropic -> withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = if (onMine) colors.onYou else colors.anthropic)) {
                append(n)
            }
            else -> append(n)
        }
    }
}
