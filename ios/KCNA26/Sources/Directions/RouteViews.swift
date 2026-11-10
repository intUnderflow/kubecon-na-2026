import SwiftUI

// Kotlin ui/directions/RouteViews.kt: the step icons, the turn-by-turn steps and the From picker.
// The rules (colours per step kind, the menu's order and texts) are Core's
// (`DirectionsScreenUI`, `FromMenu`, `FromOptions`); this file only draws and lays out.

/// The web's step ICON shapes (24-unit box) as SwiftUI paths, parsed once.
private enum StepPaths {
    static let walk = Path(svgCommands: SvgPath.parse(MapGeometry.ICON_WALK))
    static let up = Path(svgCommands: SvgPath.parse(MapGeometry.ICON_UP))
    static let down = Path(svgCommands: SvgPath.parse(MapGeometry.ICON_DOWN))
    static let end = Path(svgCommands: SvgPath.parse(MapGeometry.ICON_END))
}

/// Kotlin `StepIcon`: a step-kind icon in its 34 pt circle (.steps .ic): start dot, walk arrow,
/// up/down stairs, end pin. Decorative (the step's text says it).
struct StepIcon: View {
    let kind: StepKind

    @Environment(\.appColors) private var colors

    init(_ kind: StepKind) {
        self.kind = kind
    }

    var body: some View {
        let roles = DirectionsScreenUI.stepIconRoles(kind)
        let background: Color = Color(argb: roles.background.argb(in: colors.palette))
        let foreground: Color = Color(argb: roles.foreground.argb(in: colors.palette))
        let hole: Color = colors.surface
        let kind: StepKind = self.kind
        Canvas { ctx, size in
            ctx.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(background))
            let box: CGFloat = 20
            let k: CGFloat = box / 24
            var icon = ctx
            icon.translateBy(x: (size.width - box) / 2, y: (size.height - box) / 2)
            icon.scaleBy(x: k, y: k)
            switch kind {
            case .start:
                icon.fill(Path(ellipseIn: CGRect(x: 7, y: 7, width: 10, height: 10)), with: .color(foreground))
            case .walk:
                icon.stroke(StepPaths.walk, with: .color(foreground), style: stepIconStroke(2.4))
            case .up:
                icon.stroke(StepPaths.up, with: .color(foreground), style: stepIconStroke(2.2))
            case .down:
                icon.stroke(StepPaths.down, with: .color(foreground), style: stepIconStroke(2.2))
            case .end:
                icon.fill(StepPaths.end, with: .color(foreground))
                icon.fill(Path(ellipseIn: CGRect(x: 12 - 2.2, y: 11 - 2.2, width: 4.4, height: 4.4)), with: .color(hole))
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// The step icons' round-capped, round-joined stroke (in the 24-unit icon box).
private func stepIconStroke(_ width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
}

/// Kotlin `StepsList`: turn-by-turn steps (.steps): icon, text, a dotted connector between the
/// icons; the end step is bold.
struct StepsList: View {
    let steps: [Step]

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(steps: [Step]) {
        self.steps = steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(steps.indices, id: \.self) { i in
                let step: Step = steps[i]
                let style: AppTextStyle = type.step.copy(weight: DirectionsScreenUI.stepIsBold(step.kind) ? .bold : .regular)
                HStack(alignment: .top, spacing: 10) {
                    StepIcon(step.kind)
                    Text(verbatim: step.text)
                        .appTextStyle(style)
                        .foregroundStyle(colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .background(alignment: .topLeading) {
                    if i > 0 {
                        // CSS `border-left: 2px dotted`: round 2 pt dots between the icons, from
                        // 6 pt above this row to 6 pt into it.
                        StepConnector()
                            .stroke(colors.line, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.01, 4]))
                            .frame(width: 2, height: 12)
                            .offset(x: 16, y: -6)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// The dotted line between two step icons: down the middle of its rect, the first dot's centre
/// 1 pt below the top.
private struct StepConnector: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// Kotlin `FromPicker`'s field (web: `<label>From <select>`): an outlined, read-only field
/// labelled "From" that shows the chosen option's name, with the dropdown chevron.
///
/// iOS: tapping it opens ``FromMenuSheet`` (the screen presents it, with the open state and the
/// frozen menu hoisted above its compact/wide branch like Kotlin's). A SwiftUI `Menu` cannot be
/// used: it reports no open/close, so the menu could not be sorted from the fix at the moment it
/// opens and kept in that order while it is open.
struct FromPicker: View {
    let options: FromOptions
    let selected: String
    let expanded: Bool
    let onExpandedChange: (Bool) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(options: FromOptions, selected: String, expanded: Bool, onExpandedChange: @escaping (Bool) -> Void) {
        self.options = options
        self.selected = selected
        self.expanded = expanded
        self.onExpandedChange = onExpandedChange
    }

    var body: some View {
        let value: String = options.label(selected)
        let field = RoundedRectangle(cornerRadius: 8, style: .circular)
        Button {
            onExpandedChange(!expanded)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: value)
                    .appTextStyle(type.body)
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AppIconImage(.expandMore, size: 24)
                    .foregroundStyle(colors.muted)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(colors.surface, in: field)
            .overlay {
                // Material: ink and 2 pt while open (focused), else a 1 pt hairline.
                field.strokeBorder(expanded ? colors.ink : colors.line, lineWidth: expanded ? 2 : 1)
            }
            .overlay(alignment: .topLeading) {
                // The floating label, centred on the top border with a gap cut into it.
                Text(verbatim: DirectionsText.FROM)
                    .appTextStyle(type.material.bodySmall)
                    .foregroundStyle(colors.muted)
                    .padding(.horizontal, 4)
                    .background(colors.surface)
                    .padding(.leading, 12)
                    .alignmentGuide(.top) { d in d[VerticalAlignment.center] }
            }
            .contentShape(field)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: DirectionsText.FROM))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityAddTraits(.isButton)
    }
}

/// Kotlin `FromPicker`'s open menu, as the content of a sheet (detents medium/large): My
/// location (GPS) first, then `menu`: with a fix, every entrance and room in one list, nearest
/// first, each with an entrance/room icon, its distance and level; without one, the entrances
/// then the rooms by name. The chosen option keeps its checkmark wherever it sorts.
///
/// The screen builds `menu` when the picker opens and keeps it while it is open, so fixes never
/// move items. A new sheet each opening, so it always starts at the top (Kotlin: a fresh scroll
/// state per opening). Picking closes it.
struct FromMenuSheet: View {
    let menu: FromMenu
    let selected: String
    let onPick: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(menu: FromMenu, selected: String, onPick: @escaping (String) -> Void) {
        self.menu = menu
        self.selected = selected
        self.onPick = onPick
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(verbatim: DirectionsText.FROM)
                    .appTextStyle(type.sheetTitle)
                    .foregroundStyle(colors.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                if menu.byDistance {
                    NearestItem(item: FromMenuItem(menu.live), selected: menu.live.key == selected, onPick: onPick)
                    ForEach(menu.sections.indices, id: \.self) { s in
                        let section: FromMenuSection = menu.sections[s]
                        MenuHeader(text: section.title)
                        ForEach(section.items.indices, id: \.self) { i in
                            let item: FromMenuItem = section.items[i]
                            NearestItem(item: item, selected: item.key == selected, onPick: onPick)
                        }
                    }
                } else {
                    FromItem(option: menu.live, selected: menu.live.key == selected, onPick: onPick)
                    ForEach(menu.sections.indices, id: \.self) { s in
                        let section: FromMenuSection = menu.sections[s]
                        MenuHeader(text: section.title)
                        ForEach(section.items.indices, id: \.self) { i in
                            let item: FromMenuItem = section.items[i]
                            FromItem(option: item.option, selected: item.key == selected, onPick: onPick)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(colors.surface)
    }
}

/// Kotlin `MenuHeader`: "NEAREST FIRST", "ENTRANCES", "ROOMS".
private struct MenuHeader: View {
    let text: String

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        CapsText(text, style: type.sectionLabel, color: colors.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

/// Kotlin `FromItem`: a row of the grouped menu (no fix): the name (bold when chosen) and the
/// checkmark.
private struct FromItem: View {
    let option: FromOption
    let selected: Bool
    let onPick: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        Button {
            onPick(option.key)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: option.label)
                    .appTextStyle(type.body.copy(weight: selected ? .bold : .regular))
                    .foregroundStyle(colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    AppIconImage(.check, size: 24)
                        .foregroundStyle(colors.you)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget), alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(FromRowButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Kotlin `NearestItem`: a row of the nearest-first menu: the kind icon (my location, entrance or
/// room), the name, and under it "40 m · L2"; the checkmark slot is always there so the rows line up.
private struct NearestItem: View {
    let item: FromMenuItem
    let selected: Bool
    let onPick: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let option: FromOption = item.option
        let details: String = DirectionsScreenUI.nearestDetails(item)
        var detailsStyle: AppTextStyle = type.small
        detailsStyle.tabularNumbers = true
        return Button {
            onPick(option.key)
        } label: {
            HStack(spacing: 12) {
                AppIconImage(option.kind.appIcon, size: 20, label: DirectionsScreenUI.kindDescription(option.kind))
                    .foregroundStyle(colors.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: option.label)
                        .appTextStyle(type.body.copy(weight: selected ? .bold : .regular))
                        .foregroundStyle(colors.ink)
                        .lineLimit(2)
                    if !details.isEmpty {
                        Text(verbatim: details)
                            .appTextStyle(detailsStyle)
                            .foregroundStyle(colors.muted)
                            .lineLimit(1)
                            .accessibilityLabel(Text(verbatim: DirectionsScreenUI.nearestDetailsDescription(item)))
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    if selected {
                        AppIconImage(.check, size: 24)
                            .foregroundStyle(colors.you)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget), alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(FromRowButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A menu row's press feedback (Material's ripple): the `pressed` ink wash.
private struct FromRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FromRowButtonBody(configuration: configuration)
    }
}

private struct FromRowButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.appColors) private var colors

    var body: some View {
        configuration.label
            .background(configuration.isPressed ? colors.pressed : Color.clear)
    }
}

private extension FromKind {
    /// Kotlin `FromKind.icon`.
    var appIcon: AppIcon {
        switch self {
        case .live: return .myLocation
        case .entrance: return .login
        case .room: return .meetingRoom
        }
    }
}

#Preview("Steps") {
    ThemePreview {
        StepsList(steps: [
            Step(.start, "Start at the 200 South entrance.", 1),
            Step(.walk, "Walk north along the Lower Concourse.", 1),
            Step(.up, "Take the North Foyer escalator up to Level 2.", 2),
            Step(.end, "251 A–C is on your left.", 2),
        ])
    }
}
