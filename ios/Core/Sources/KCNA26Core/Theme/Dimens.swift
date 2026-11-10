import Foundation

/// Layout conventions (Kotlin theme/Theme.kt `Dimens`), in points (Android dp ≈ iOS pt).
enum Dimens {
    /// Minimum touch target for anything tappable (iOS HIG: 44; the app keeps Android's 48).
    static let touchTarget: Double = 48
    /// Horizontal page padding on phones (.wrap).
    static let pagePadding: Double = 16
    /// Gap between cards (.list gap).
    static let cardGap: Double = 8
    /// Card corner radius (.card).
    static let cardRadius: Double = 10
    /// Banner / big panel radius (.mine).
    static let bannerRadius: Double = 14
    /// Sheet top corner radius (.panel).
    static let sheetRadius: Double = 18
    /// Left category stripe on cards (.card border-left).
    static let categoryStripe: Double = 4
    /// Max width of a single content column (.wrap max-width 760px).
    static let maxContentWidth: Double = 760
    /// Max width for running text (~65ch).
    static let maxTextWidth: Double = 620
    /// Width-class breakpoints (see WidthClass).
    static let mediumBreakpoint: Double = 600
    static let expandedBreakpoint: Double = 840
}

extension String {
    /// Kotlin `caps()` (theme/Type.kt): `uppercase(Locale.ROOT)`, for every Barlow (display)
    /// style, since text is shown uppercased ("ß" -> "SS", no locale rules).
    func caps() -> String { uppercased() }
}
