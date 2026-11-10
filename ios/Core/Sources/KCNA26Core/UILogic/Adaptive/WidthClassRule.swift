import Foundation

// The pure part of Kotlin ui/adaptive/WidthClass.kt. The file is not called WidthClass.swift:
// the app keeps its environment part (`\.widthClass`, `.readsWindowWidth()`) in
// ios/KCNA26/Sources/Theme/WidthClass.swift, and file names must be unique in the one module.

/// Window width class.
/// - ``compact`` < 600 pt: every iPhone in portrait (Kotlin: the Pixel 10 Pro Fold cover
///   screen, ~443 dp). Primary design.
/// - ``medium`` 600–839 pt and ``expanded`` ≥ 840 pt: iPad, iPhone landscape, wide Split View /
///   Stage Manager windows (Kotlin: the unfolded inner screen, ~852 × 883 dp).
///
/// Kotlin `Compact` / `Medium` / `Expanded` -> `.compact` / `.medium` / `.expanded`.
enum WidthClass: Sendable, Hashable, CaseIterable {
    case compact
    case medium
    case expanded

    /// Medium or Expanded: use list–detail / two columns.
    var isWide: Bool { self != .compact }

    /// Kotlin `WidthClass.fromWidth(width)`: `width` in points (Kotlin dp), the whole window's
    /// width (safe-area insets included).
    static func fromWidth(_ width: Double) -> WidthClass {
        if width >= Dimens.expandedBreakpoint { return .expanded } // 840
        if width >= Dimens.mediumBreakpoint { return .medium } // 600
        return .compact
    }
}
