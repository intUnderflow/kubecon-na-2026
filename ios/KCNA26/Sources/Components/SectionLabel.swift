import SwiftUI

/// `.panel h3` and the Settings / Going section headings ("SPEAKERS", "ABOUT", "RSVPS",
/// "SCHEDULE DATA", "I’M SPEAKING AS", "CLASHES WITH"): `type.sectionLabel` in muted, uppercase,
/// a VoiceOver heading. No padding: the details add `top 18, bottom 6` (Kotlin `SectionLabel`).
struct SectionLabel: View {
    let text: String
    var isHeading: Bool
    var lineLimit: Int?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(_ text: String, isHeading: Bool = true, lineLimit: Int? = nil) {
        self.text = text
        self.isHeading = isHeading
        self.lineLimit = lineLimit
    }

    var body: some View {
        CapsText(text, style: type.sectionLabel, color: colors.muted, lineLimit: lineLimit)
            .accessibilityAddTraits(isHeading ? .isHeader : [])
    }
}

/// Compose `HorizontalDivider(color = line)` / `VerticalDivider`: a 1 pt hairline in `line`
/// (or `color`), e.g. under the schedule header, between Settings rows, between list and
/// detail panes.
struct HairlineDivider: View {
    enum Orientation: Sendable {
        case horizontal
        case vertical
    }

    var axis: Orientation
    var color: Color?

    @Environment(\.appColors) private var colors

    init(_ axis: Orientation = .horizontal, color: Color? = nil) {
        self.axis = axis
        self.color = color
    }

    var body: some View {
        let fill: Color = color ?? colors.line
        switch axis {
        case .horizontal:
            Rectangle().fill(fill).frame(height: 1).frame(maxWidth: .infinity).accessibilityHidden(true)
        case .vertical:
            Rectangle().fill(fill).frame(width: 1).frame(maxHeight: .infinity).accessibilityHidden(true)
        }
    }
}

#Preview("Section label, dividers") {
    ThemePreview {
        SectionLabel("Speakers")
        HairlineDivider()
        HStack(spacing: 12) {
            SectionLabel("Schedule data")
            HairlineDivider(.vertical)
            SectionLabel("RSVPs")
        }
        .frame(height: 24)
    }
}
