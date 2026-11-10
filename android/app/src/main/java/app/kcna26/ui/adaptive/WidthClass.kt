package app.kcna26.ui.adaptive

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Window width class.
 * - [Compact] < 600 dp: the Pixel 10 Pro Fold cover screen (~443 dp). Primary design.
 * - [Medium] 600–839 dp and [Expanded] ≥ 840 dp: the unfolded inner screen (~852 × 883 dp).
 */
enum class WidthClass {
    Compact,
    Medium,
    Expanded;

    /** Medium or Expanded: use list–detail / two columns. */
    val isWide: Boolean get() = this != Compact

    companion object {
        fun fromWidth(width: Dp): WidthClass = when {
            width >= 840.dp -> Expanded
            width >= 600.dp -> Medium
            else -> Compact
        }
    }
}

/**
 * The width class of the whole activity window. Provided by MainActivity at the
 * root; recomputed whenever the window size changes (fold/unfold recreates the
 * activity anyway). Screens read it with `LocalWidthClass.current`.
 */
val LocalWidthClass = staticCompositionLocalOf { WidthClass.Compact }

/** Computes the window width class from the current window size. */
@Composable
fun currentWidthClass(): WidthClass = WidthClass.fromWidth(currentWindowWidth())

/** The current window width in dp (updates on resize; fold/unfold recreates the activity anyway). */
@Composable
fun currentWindowWidth(): Dp = LocalWindowInfo.current.containerDpSize.width
