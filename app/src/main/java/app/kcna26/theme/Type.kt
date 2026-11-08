package app.kcna26.theme

import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.kcna26.R
import java.util.Locale

/** Barlow Condensed SemiBold (600) + Bold (700): headings, times, labels. Always UPPERCASE ([caps]). */
val Barlow = FontFamily(
    Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold),
    Font(R.font.barlow_condensed_bold, FontWeight.Bold),
)

/** Atkinson Hyperlegible Regular (400) + Bold (700): body text and titles. */
val Atkinson = FontFamily(
    Font(R.font.atkinson_hyperlegible_regular, FontWeight.Normal),
    Font(R.font.atkinson_hyperlegible_bold, FontWeight.Bold),
)

/** Compose has no text-transform: uppercase display strings with this. */
fun String.caps(): String = uppercase(Locale.ROOT)

private const val TNUM = "tnum"

private fun barlow(size: TextUnit, weight: FontWeight = FontWeight.Bold, spacing: Float = 0.05f, lineHeight: Float = 1.15f) =
    TextStyle(
        fontFamily = Barlow,
        fontWeight = weight,
        fontSize = size,
        lineHeight = (size.value * lineHeight).sp,
        letterSpacing = spacing.em,
        fontFeatureSettings = TNUM,
    )

private fun atkinson(size: TextUnit, weight: FontWeight = FontWeight.Normal, lineHeight: Float = 1.4f) =
    TextStyle(
        fontFamily = Atkinson,
        fontWeight = weight,
        fontSize = size,
        lineHeight = (size.value * lineHeight).sp,
    )

/**
 * Named text styles matching the web CSS. Barlow styles must be shown
 * uppercased ([caps] or [CapsText]); colours are not set (use AppTheme.colors).
 */
@Immutable
data class AppType(
    /** Header brand "KUBECON NA 2026" (.brand h1): Barlow 700 21sp. */
    val brand: TextStyle = barlow(21.sp, spacing = 0.03f, lineHeight = 1f),
    /** Header clock (.clock): Barlow 600 16sp, muted. */
    val clock: TextStyle = barlow(16.sp, FontWeight.SemiBold, 0.05f, 1f),
    /** Day tab weekday (.day small): Barlow 600 12.5sp. */
    val dayTabLabel: TextStyle = barlow(12.5.sp, FontWeight.SemiBold, 0.08f, 1f),
    /** Day tab number (.day b): Barlow 700 22sp. */
    val dayTabNumber: TextStyle = barlow(22.sp, spacing = 0f, lineHeight = 1f),
    /** Small badge on a day tab ("YOU"): Barlow 700 11sp. */
    val badge: TextStyle = barlow(11.sp, spacing = 0.08f, lineHeight = 1f),
    /** Day heading (.dayhead h2): Barlow 700 30sp (36sp on wide screens). */
    val dayHeading: TextStyle = barlow(30.sp, spacing = 0.01f, lineHeight = 1.02f),
    /** "3 on now · Next at 10:15 AM" (.status): Barlow 600 17sp. */
    val status: TextStyle = barlow(17.sp, FontWeight.SemiBold, 0.04f, 1.2f),
    /** Half-hour block / section heading (.slot>h3): Barlow 700 18sp. */
    val slotHeading: TextStyle = barlow(18.sp, spacing = 0.05f, lineHeight = 1f),
    /** "UP NEXT" line (.nowline): Barlow 700 15sp, pink. */
    val nowLine: TextStyle = barlow(15.sp, spacing = 0.1f, lineHeight = 1f),
    /** Card meta row: category, time, duration (.meta): Barlow 600 14sp. */
    val meta: TextStyle = barlow(14.sp, FontWeight.SemiBold, 0.05f, 1.2f),
    /** Pills / tags ("LIVE · 12 MIN LEFT", "ANTHROPIC"): Barlow 700 12.5sp. */
    val pill: TextStyle = barlow(12.5.sp, spacing = 0.06f, lineHeight = 1f),
    /** Session title on a card (.card h4): Atkinson 700 16.5sp. */
    val cardTitle: TextStyle = atkinson(16.5.sp, FontWeight.Bold, 1.28f),
    /** Session title on one of my cards (.card.me h4): Atkinson 700 19sp. */
    val cardTitleMine: TextStyle = atkinson(19.sp, FontWeight.Bold, 1.25f),
    /** Speakers line (.who) and where line (.where): Atkinson 14sp. */
    val small: TextStyle = atkinson(14.sp, lineHeight = 1.35f),
    /** Very small secondary text (.kid .s, notes): Atkinson 13sp. */
    val tiny: TextStyle = atkinson(13.sp, lineHeight = 1.35f),
    /** Group child time (.kid time): Barlow 600 14.5sp. */
    val kidTime: TextStyle = barlow(14.5.sp, FontWeight.SemiBold, 0.03f, 1.35f),
    /** Group child title (.kid .t): Atkinson 700 14.5sp. */
    val kidTitle: TextStyle = atkinson(14.5.sp, FontWeight.Bold, 1.3f),
    /** Body text: Atkinson 16sp / 1.4. */
    val body: TextStyle = atkinson(16.sp),
    /** Long-form description (.desc): Atkinson 16sp / 1.55. Cap the width (Dimens.maxTextWidth). */
    val description: TextStyle = atkinson(16.sp, lineHeight = 1.55f),
    /** Sheet / screen title (.panel h2): Atkinson 700 22sp. */
    val sheetTitle: TextStyle = atkinson(22.sp, FontWeight.Bold, 1.22f),
    /** Section label in sheets ("SPEAKERS", "ABOUT"; .panel h3): Barlow 700 14sp, muted. */
    val sectionLabel: TextStyle = barlow(14.sp, spacing = 0.1f, lineHeight = 1f),
    /** Buttons and link buttons (.links a): Barlow 700 15sp. */
    val button: TextStyle = barlow(15.sp, spacing = 0.06f, lineHeight = 1f),
    /** Banner header "YOU'RE SPEAKING" (.mine-h): Barlow 700 14sp. */
    val bannerLabel: TextStyle = barlow(14.sp, spacing = 0.1f, lineHeight = 1f),
    /** Banner countdown chip (.mine-h .cd): Barlow 700 16sp. */
    val bannerCountdown: TextStyle = barlow(16.sp, spacing = 0.04f, lineHeight = 1f),
    /** Banner time (.mine-next time): Barlow 700 15sp. */
    val bannerTime: TextStyle = barlow(15.sp, spacing = 0.06f, lineHeight = 1.2f),
    /** Banner talk title (.mine-next .t): Atkinson 700 19sp. */
    val bannerTitle: TextStyle = atkinson(19.sp, FontWeight.Bold, 1.22f),
    /** Directions route summary "ABOUT 250 M · 4 MIN · UP 1 LEVEL" (.wf .sum): Barlow 700 17sp. */
    val routeSummary: TextStyle = barlow(17.sp, spacing = 0.04f, lineHeight = 1.2f),
    /** Walking step text (.steps li): Atkinson 16sp / 1.4. */
    val step: TextStyle = atkinson(16.sp),
    /** Level badge "LEVEL 2" (.wf .lv): Barlow 700 14sp. Scale up with copy() for Directions. */
    val levelBadge: TextStyle = barlow(14.sp, spacing = 0.06f, lineHeight = 1f),
    /** Big glanceable figures (Directions distance, "LEVEL 2 · SALT PALACE"): Barlow 700 34sp. */
    val display: TextStyle = barlow(34.sp, spacing = 0.02f, lineHeight = 1.05f),
    /** Biggest figure: Barlow 700 48sp. */
    val displayLarge: TextStyle = barlow(48.sp, spacing = 0.01f, lineHeight = 1f),
)

val LocalAppType = staticCompositionLocalOf { AppType() }

/** Material 3 typography: Barlow for display/headline/label, Atkinson for title/body. */
internal val KcnaTypography: Typography =
    Typography(
        displayLarge = barlow(57.sp, spacing = 0f, lineHeight = 1.1f),
        displayMedium = barlow(45.sp, spacing = 0f, lineHeight = 1.1f),
        displaySmall = barlow(36.sp, spacing = 0.01f, lineHeight = 1.1f),
        headlineLarge = barlow(32.sp, spacing = 0.01f, lineHeight = 1.05f),
        headlineMedium = barlow(28.sp, spacing = 0.01f, lineHeight = 1.05f),
        headlineSmall = barlow(24.sp, spacing = 0.02f, lineHeight = 1.1f),
        titleLarge = atkinson(22.sp, FontWeight.Bold, 1.22f),
        titleMedium = atkinson(16.5.sp, FontWeight.Bold, 1.28f),
        titleSmall = atkinson(14.sp, FontWeight.Bold, 1.3f),
        bodyLarge = atkinson(16.sp),
        bodyMedium = atkinson(14.sp, lineHeight = 1.35f),
        bodySmall = atkinson(13.sp, lineHeight = 1.35f),
        labelLarge = barlow(15.sp, spacing = 0.06f, lineHeight = 1f),
        labelMedium = barlow(14.sp, FontWeight.SemiBold, 0.05f, 1.1f),
        labelSmall = barlow(12.5.sp, spacing = 0.06f, lineHeight = 1f),
    )

/** Text that is always uppercased: use for every Barlow (display) style. */
@Composable
fun CapsText(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
) {
    Text(
        text = text.caps(),
        style = style,
        color = color,
        modifier = modifier,
        maxLines = maxLines,
        overflow = overflow,
    )
}
