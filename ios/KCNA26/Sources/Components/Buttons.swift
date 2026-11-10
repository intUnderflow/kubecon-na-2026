import SwiftUI

// The two button looks the Kotlin screens share: the ink-filled Material `Button` (details link
// buttons, the Directions bar) and the hairline `OutlinedButton` (official listing, Skip,
// co-located links, Directions actions). The label is the caller's, normally
// `CapsText(text, style: type.button)`; a plain `Text` gets `type.button` too (Kotlin's Skip).

/// Button corner shapes: the card radius (Kotlin `RoundedCornerShape(Dimens.cardRadius)`) or a
/// capsule (Material's default button shape, Kotlin's Skip button).
enum KcnaButtonShape: Sendable, Equatable {
    case card
    case capsule
}

/// Ink fill, `bg`-coloured content (Kotlin `ButtonDefaults.buttonColors(containerColor = ink,
/// contentColor = bg)`); disabled: `line` fill, `muted` content. At least `minHeight` tall
/// (48, the Directions bar 56); `fillsWidth` for Kotlin `Modifier.weight(1f)` / `fillMaxWidth()`.
struct InkButtonStyle: ButtonStyle {
    var minHeight: CGFloat = CGFloat(Dimens.touchTarget)
    var horizontalPadding: CGFloat = 24
    var fillsWidth: Bool = false
    var shape: KcnaButtonShape = .card

    func makeBody(configuration: Configuration) -> some View {
        KcnaButtonBody(configuration: configuration, filled: true, minHeight: minHeight,
                       horizontalPadding: horizontalPadding, fillsWidth: fillsWidth, shape: shape)
    }
}

/// Transparent with a 1 pt `line` border and `ink` content (Kotlin `OutlinedButton(border =
/// BorderStroke(1.dp, line), contentColor = ink)`); disabled content `muted`.
struct OutlineButtonStyle: ButtonStyle {
    var minHeight: CGFloat = CGFloat(Dimens.touchTarget)
    var horizontalPadding: CGFloat = 24
    var fillsWidth: Bool = false
    var shape: KcnaButtonShape = .card

    func makeBody(configuration: Configuration) -> some View {
        KcnaButtonBody(configuration: configuration, filled: false, minHeight: minHeight,
                       horizontalPadding: horizontalPadding, fillsWidth: fillsWidth, shape: shape)
    }
}

/// The shared body (a View, so it can read the environment: theme and `isEnabled`).
private struct KcnaButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let filled: Bool
    let minHeight: CGFloat
    let horizontalPadding: CGFloat
    let fillsWidth: Bool
    let shape: KcnaButtonShape

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let content: Color = filled ? (isEnabled ? colors.bg : colors.muted) : (isEnabled ? colors.ink : colors.muted)
        let fill: Color = filled ? (isEnabled ? colors.ink : colors.line) : Color.clear
        let radius: CGFloat = shape == .card ? CGFloat(Dimens.cardRadius) : minHeight / 2
        let outline = RoundedRectangle(cornerRadius: radius, style: .circular)
        // The label's default font (Material's `LocalTextStyle`); a CapsText label sets its own.
        configuration.label
            .font(type.button.font)
            .tracking(type.button.tracking)
            .foregroundStyle(content)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
            .background { outline.fill(fill) }
            .overlay {
                if !filled {
                    outline.strokeBorder(colors.line, lineWidth: 1)
                }
            }
            .contentShape(outline)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    /// `.buttonStyle(.ink)`: ``InkButtonStyle`` with the defaults.
    static var ink: InkButtonStyle { InkButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    /// `.buttonStyle(.outline)`: ``OutlineButtonStyle`` with the defaults.
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

#Preview("Buttons") {
    ThemePreview {
        ButtonSpecimen()
    }
}

private struct ButtonSpecimen: View {
    @Environment(\.appType) private var type

    var body: some View {
        FlowRow(horizontalSpacing: 8, verticalSpacing: 8) {
            Button {} label: { CapsText("Slides", style: type.button) }
                .buttonStyle(InkButtonStyle(horizontalPadding: 16))
            Button {} label: { CapsText("Official listing ↗", style: type.button) }
                .buttonStyle(OutlineButtonStyle(horizontalPadding: 16))
        }
        HStack(spacing: 8) {
            Button {} label: {
                HStack(spacing: 8) {
                    AppIconImage(.directionsWalk, size: 22)
                    CapsText("Directions", style: type.button.copy(size: 18))
                }
            }
            .buttonStyle(InkButtonStyle(minHeight: 56, horizontalPadding: 20, fillsWidth: true))
            Button {} label: { CapsText("Directions", style: type.button.copy(size: 18)) }
                .buttonStyle(InkButtonStyle(minHeight: 56, horizontalPadding: 20, fillsWidth: true))
                .disabled(true)
        }
        Button {} label: { Text(verbatim: "Skip") }
            .buttonStyle(OutlineButtonStyle(fillsWidth: true, shape: .capsule))
    }
}
