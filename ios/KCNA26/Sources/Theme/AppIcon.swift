import SwiftUI

/// Every Material icon the Kotlin UI uses (`Icons.*` in ui/ and nav/), mapped to the closest SF
/// Symbol available on iOS 17. Views never name a symbol themselves: `Image(appIcon: .star)` or
/// `AppIconImage(.star, size: 23)`.
///
/// Not mapped: the notification small icon `ic_stat_pin` (iOS notifications show the app icon)
/// and the launcher icons (Assets.xcassets/AppIcon).
enum AppIcon: String, CaseIterable, Sendable {
    /// `Icons.Rounded.Star`: going (filled star) on cards, the Going chip, the "Up next" row, the
    /// details' Going button.
    case star = "star.fill"
    /// `Icons.Rounded.StarBorder`: not going (outlined star).
    case starBorder = "star"
    /// `Icons.AutoMirrored.Filled.DirectionsWalk`: the Directions buttons (details bar, "Up next" row).
    case directionsWalk = "figure.walk"
    /// `Icons.Rounded.NotificationsOff`: the "Notifications are off" hint.
    case notificationsOff = "bell.slash.fill"
    /// `Icons.AutoMirrored.Rounded.ArrowBack` (Settings) and `Icons.AutoMirrored.Filled.ArrowBack`
    /// (Directions): back. On iOS the NavigationStack back button replaces both; kept for any
    /// custom bar.
    case arrowBack = "chevron.backward"
    /// `Icons.Rounded.Check` (Settings: the chosen speaker) and `Icons.Filled.Check` (Directions:
    /// the chosen "from" place).
    case check = "checkmark"
    /// `Icons.Rounded.Search`: the leading icon of the search fields.
    case search = "magnifyingglass"
    /// `Icons.Rounded.Close` in the search fields ("Clear search"): the iOS clear-text glyph.
    case clearSearch = "xmark.circle.fill"
    /// `Icons.Filled.Close`: the details sheet's × ("Close").
    case close = "xmark"
    /// `Icons.Rounded.ExpandLess`: an open co-located card, "Hide agenda".
    case expandLess = "chevron.up"
    /// `Icons.Rounded.ExpandMore`: a closed co-located card.
    case expandMore = "chevron.down"
    /// `Icons.Rounded.Settings`: the schedule header's Settings button.
    case settings = "gearshape.fill"
    /// `Icons.Filled.FitScreen`: the map's "fit the route" button (corner brackets).
    case fitScreen = "viewfinder"
    /// `Icons.Outlined.MyLocation`: "from" = my live location. Material draws a crosshair; iOS
    /// users know the location arrow for "where I am".
    case myLocation = "location"
    /// `Icons.AutoMirrored.Outlined.Login`: "from" = a building entrance (an arrow going in).
    case login = "arrow.right.to.line"
    /// `Icons.Outlined.MeetingRoom`: "from" = a room (an open door; SF Symbols 4, iOS 16+).
    case meetingRoom = "door.left.hand.open"

    /// The SF Symbol name.
    var systemName: String { rawValue }
}

extension Image {
    /// The SF Symbol for an ``AppIcon``.
    init(appIcon: AppIcon) {
        self.init(systemName: appIcon.systemName)
    }
}

/// A Material `Icon(..., modifier = Modifier.size(size))`: the symbol drawn in a `size` × `size`
/// box. Material glyphs fill about 20/24 of their box, so the symbol's point size is 5/6 of it.
/// Decorative (hidden from VoiceOver) unless given a `label` (Kotlin `contentDescription`).
/// Colour: the foreground style (`.foregroundStyle(colors.muted)`, Kotlin `tint`).
struct AppIconImage: View {
    let icon: AppIcon
    var size: CGFloat
    var label: String?

    init(_ icon: AppIcon, size: CGFloat = 24, label: String? = nil) {
        self.icon = icon
        self.size = size
        self.label = label
    }

    var body: some View {
        let glyph = Image(appIcon: icon)
            .font(.system(size: size * 5 / 6))
            .frame(width: size, height: size)
        if let label {
            glyph.accessibilityLabel(Text(verbatim: label))
        } else {
            glyph.accessibilityHidden(true)
        }
    }
}

#Preview("Icons") {
    ThemePreview {
        IconSpecimen()
    }
}

private struct IconSpecimen: View {
    @Environment(\.appColors) private var colors

    var body: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible()), count: 4)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(AppIcon.allCases, id: \.self) { icon in
                VStack(spacing: 2) {
                    AppIconImage(icon, size: 24)
                        .foregroundStyle(colors.ink)
                    Text(verbatim: "\(icon)")
                        .font(.caption2)
                        .foregroundStyle(colors.muted)
                }
            }
        }
    }
}
